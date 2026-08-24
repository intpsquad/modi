#!/usr/bin/env bash
# 인스타그램 persisted query `doc_id` 감시.
#
# 서버(InstagramUrlCrawler)는 인스타 웹의 `PolarisPostRootQuery` 를 `doc_id` 로 부른다. 인스타가
# 이 값을 몇 주~몇 달마다 바꾸는데, 바뀌면 HTTP 200 에 `items: []` 가 와서 서버는 **비공개 게시물과
# 구분하지 못한다** — 사용자에게 "공개된 게시물만 등록할 수 있어요" 가 뜨고 로그에 구분되는 신호가 없다.
# 이 스크립트는 인스타 웹이 실제로 쓰는 번들에서 지금의 doc_id 를 읽어 우리 값과 비교한다.
#
#   scripts/instagram-doc-id.sh check          # 기본. exit 0 변화 없음 / 10 갱신 필요 / 30 판정 불가
#   scripts/instagram-doc-id.sh extract        # 번들에서 doc_id·providedVariables 만 뽑는다
#   scripts/instagram-doc-id.sh verify <doc_id> <shortcode> [pv,list]   # 실제 조회 → ok/empty/login_wall
#                                      (pv 생략 시 current 의 providedVariables 를 보낸다)
#   scripts/instagram-doc-id.sh current --yml <f> --java <f>  # 우리 값(application.yml + Java 의 pv)
#   scripts/instagram-doc-id.sh parse-page <html> / parse-bundle <js>... / classify-graphql <status> <body>
#
# 환경변수
#   IG_PROBE_SHORTCODES  검증에 쓸 공개 게시물 shortcode, 공백 구분(2개 권장). check 에 필요
#   CURRENT_YML          비교 기준 application.yml (기본: 저장소 파일. 워크플로는 origin/main 것을 준다)
#   CURRENT_JAVA         서버가 보내는 providedVariables 의 원본 Java 파일
#   IG_RESULT_FILE       key=value 결과를 적을 파일(워크플로가 이슈 본문을 만들 때 읽는다)
#   GITHUB_STEP_SUMMARY  있으면 마크다운 요약을 덧붙인다
#   MAX_BUNDLES          받을 번들 상한(기본 300). 넘으면 앞에서 자르고 **그 사실을 기록한다**
#
# 가짜 응답(IG_FETCH_DIR) — 테스트용. 설정되면 네트워크 대신 이 디렉터리를 읽는다:
#   page[-<shortcode>].status / .body / .cookies     게시물 페이지
#   bundles/*.js                                      번들
#   graphql-<doc_id>[-<shortcode>].status / .body     GraphQL 응답
#
# 설계 근거·판정표·리스크는 specs/OPEN.md "인스타그램 크롤링의 doc_id" 항목과 README "인스타 doc_id 감시".
#
# ⚠️ 서버와 **같은 것**을 보내야 검증이 의미가 있다. UA·헤더 12개·variables 는 InstagramUrlCrawler.java
#    (USER_AGENT, graphqlHeaders(), variables 리터럴)와 글자 단위로 같다. 한쪽을 바꾸면 다른 쪽도 바꾼다.
# ⚠️ lsd·csrf·쿠키는 로그·요약·결과 파일에 **절대 쓰지 않는다.** `set -x` 금지.
#
# bash 3.2(macOS 기본) 호환 — declare -A, mapfile, ${v,,}, grep -P, timeout, sha256sum 을 쓰지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── InstagramUrlCrawler.java 와 동일해야 하는 상수 ────────────────────────────
USER_AGENT='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
ACCEPT_LANGUAGE='en-US,en;q=0.9'
APP_ID='936619743392459'
FRIENDLY_NAME='PolarisPostRootQuery'
ROOT_FIELD='xdt_api__v1__media__shortcode__web_info'
BASE_URL="${ARCHIVE_INSTAGRAM_BASE_URL:-https://www.instagram.com}"
RELAY_OP='PolarisPostRootQuery_instagramRelayOperation'

CURRENT_YML="${CURRENT_YML:-$ROOT/server/src/main/resources/application.yml}"
CURRENT_JAVA="${CURRENT_JAVA:-$ROOT/server/src/main/java/com/nomara/modi/server/domain/archive/client/InstagramUrlCrawler.java}"
MAX_BUNDLES="${MAX_BUNDLES:-300}"
BUNDLES_TRUNCATED=no

EXIT_OK=0
EXIT_CHANGED=10
EXIT_UNKNOWN=30

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { printf '==> %s\n' "$*" >&2; }
warn() { printf '!! %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$1" >&2; exit "${2:-1}"; }

# ── 순수 파서 (파일 입력, 네트워크 없음) ─────────────────────────────────────

# 게시물 페이지 HTML → 번들 URL 목록(정렬·중복 제거).
# <link>/<script> 외에 data-sjs JSON 안의 `https:\/\/…` 로 이스케이프된 참조도 잡아야 한다 —
# 참고 문서의 grep 은 그걸 놓친다.
parse_page() {
  perl -0777 -ne '
    s{\\/}{/}g;
    while (m{(https://static\.cdninstagram\.com/rsrc\.php/[^\s"\x27<>\\?]+?\.js(?:\?[^\s"\x27<>\\]*)?)}g) { print "$1\n" }
  ' "$1" | sort -u
}

# 번들 JS 들 → `doc_id=<n>` 후보(전부) + `pv=<이름>`(providedVariables).
# 앵커는 반드시 **정의부** `__d("…_instagramRelayOperation",[]` 다 — 같은 문자열이 다른 모듈의
# 의존 배열에도 나오기 때문이다. providedVariables 는 `name:"PolarisPostRootQuery"` 뒤 2000자 창 안에서,
# 그 사이에 다른 쿼리의 `name:` 이 끼면 무시한다(이웃 쿼리의 pv 가 새는 것을 막는다).
parse_bundle() {
  local f raw="$TMP/parse-bundle.$$"
  : > "$raw"
  for f in "$@"; do
    perl -0777 -ne '
      while (/__d\("'"$RELAY_OP"'",\s*\[\]\s*,.{0,400}?exports\s*=\s*["\x27](\d{10,25})["\x27]/sg) { print "doc_id=$1\n" }
      if (/name\s*:\s*["\x27]'"$FRIENDLY_NAME"'["\x27]((?:(?!name\s*:\s*["\x27]).){0,2000}?)providedVariables\s*:\s*\{([^}]*)\}/s) {
        my $b = $2; print "pv=$_\n" for ($b =~ /(__relay_internal__pv__[A-Za-z0-9_]+)/g);
      }
    ' "$f" >> "$raw"
  done
  { grep '^doc_id=' "$raw" || true; } | sort -u
  { grep '^pv=' "$raw" || true; } | sort -u
}

# GraphQL 응답 → ok / empty / login_wall / error. 기준은 서버와 같다:
#   readGraphqlBody: status != 200 || 본문이 '<' 로 시작 → 로그인 벽
#   toCrawlResult : items 가 비면 "공개된 게시물만 등록할 수 있어요"(= 비공개·삭제·doc_id 만료)
classify_graphql() {
  local status="$1" body="$2" first
  [ "$status" = "200" ] || { echo login_wall; return; }
  first="$(head -c 200 "$body" | tr -d ' \t\r\n' | cut -c1)"
  [ "$first" != "<" ] || { echo login_wall; return; }
  python3 - "$body" "$ROOT_FIELD" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        doc = json.load(f)
    items = ((doc.get("data") or {}).get(sys.argv[2]) or {}).get("items")
    print("ok" if isinstance(items, list) and len(items) > 0 else "empty")
except Exception:
    print("error")
PY
}

# 우리 값: application.yml 의 기본값 + Java 가 variables 에 싣는 providedVariables 집합.
current() {
  local yml="$CURRENT_YML" java="$CURRENT_JAVA" doc pv
  while [ $# -gt 0 ]; do
    case "$1" in
      --yml) yml="$2"; shift 2 ;;
      --java) java="$2"; shift 2 ;;
      *) fail "current: 모르는 인자 $1" ;;
    esac
  done
  doc="$(perl -ne 'if (/doc-id:\s*\$\{ARCHIVE_INSTAGRAM_DOC_ID:(\d+)\}/) { print "$1\n"; exit }' "$yml")"
  [ -n "$doc" ] || fail "application.yml 에서 doc-id 기본값을 못 읽었다: $yml"
  pv="$(perl -ne 'print "$1\n" while /(__relay_internal__pv__[A-Za-z0-9_]+)/g' "$java" | sort -u | paste -sd, -)"
  printf 'doc_id=%s\npv=%s\n' "$doc" "$pv"
}

# ── 네트워크 (IG_FETCH_DIR 가 있으면 가짜 응답) ──────────────────────────────

# 게시물 페이지 GET. 리다이렉트를 따라가지 않는다(서버와 동일 — 3xx 는 차단으로 본다).
# stdout: HTTP 상태. $2 에 본문, $3 에 쿠키 jar.
fetch_page() {
  local shortcode="$1" body="$2" jar="$3" fake
  if [ -n "${IG_FETCH_DIR:-}" ]; then
    fake="$IG_FETCH_DIR/page-$shortcode"
    [ -f "$fake.status" ] || fake="$IG_FETCH_DIR/page"
    cp "$fake.body" "$body"
    if [ -f "$fake.cookies" ]; then cp "$fake.cookies" "$jar"; else : > "$jar"; fi
    tr -d ' \n' < "$fake.status"
    return
  fi
  curl -sS --max-time 20 -A "$USER_AGENT" -H "Accept-Language: $ACCEPT_LANGUAGE" \
    -c "$jar" -o "$body" -w '%{http_code}' "$BASE_URL/p/$shortcode/" || true # 실패해도 -w 가 000 을 찍는다
}

# 번들 다운로드. $1 = URL 목록 파일, $2 = 저장 디렉터리. stdout: "<개수> <바이트>".
# CDN(static.cdninstagram.com)은 봇 검사가 없어 병렬로 받아도 된다.
fetch_bundles() {
  local urls="$1" dir="$2" n=0 total url args
  mkdir -p "$dir"
  if [ -n "${IG_FETCH_DIR:-}" ]; then
    cp "$IG_FETCH_DIR"/bundles/*.js "$dir/" 2>/dev/null || true
  else
    args=()
    while IFS= read -r url; do
      [ -n "$url" ] || continue
      n=$((n + 1))
      if [ "$n" -gt "$MAX_BUNDLES" ]; then
        warn "번들이 $MAX_BUNDLES 개를 넘어 앞에서 잘랐다 — MAX_BUNDLES 를 올리거나 OPEN.md 관측란에 적을 것"
        BUNDLES_TRUNCATED=yes
        break
      fi
      printf '%s\n' "$url" >> "$dir/urls.txt"
      args+=(-o "$dir/$n.js" "$url")
    done < "$urls"
    [ "${#args[@]}" -gt 0 ] || { echo "0 0"; return; }
    curl -sS --parallel --parallel-max 8 --max-time 120 --max-filesize 5000000 \
      -A "$USER_AGENT" "${args[@]}" || warn "일부 번들을 받지 못했다(받은 것만으로 계속한다)"
  fi
  n="$(find "$dir" -name '*.js' | wc -l | tr -d ' ')"
  total="$(cat "$dir"/*.js 2>/dev/null | wc -c | tr -d ' ')"
  # 이 함수는 $(…) 안에서 돌아 전역 변수 대입이 호출부로 돌아오지 않는다 — 잘렸는지도 stdout 으로 돌려준다
  echo "$n ${total:-0} $BUNDLES_TRUNCATED"
}

# jar(Netscape 형식) → Cookie 헤더 값. 서버의 graphqlCookies() 처럼 부트스트랩 쿠키에 csrftoken 을 덮어쓴다.
cookie_header() {
  local jar="$1" csrf="$2"
  awk -v csrf="$csrf" '
    BEGIN { FS = "\t" }
    { sub(/^#HttpOnly_/, "") }   # curl 은 HttpOnly 쿠키를 이 접두로 적는다 — 주석이 아니다
    /^#/ || NF < 7 { next }
    $6 == "csrftoken" { next }
    { printf "%s=%s; ", $6, $7 }
    END { printf "csrftoken=%s", csrf }
  ' "$jar"
}

# GraphQL POST. stdout: HTTP 상태. $7 에 본문. 헤더 12개·폼 5개는 서버(graphqlHeaders / crawl)와 동일.
fetch_graphql() {
  local doc_id="$1" shortcode="$2" lsd="$3" csrf="$4" cookies="$5" pv_json="$6" body="$7" fake variables
  if [ -n "${IG_FETCH_DIR:-}" ]; then
    fake="$IG_FETCH_DIR/graphql-$doc_id-$shortcode"
    [ -f "$fake.status" ] || fake="$IG_FETCH_DIR/graphql-$doc_id"
    [ -f "$fake.status" ] || { warn "가짜 응답 없음: $fake.status"; echo 000; return; }
    cp "$fake.body" "$body"
    tr -d ' \n' < "$fake.status"
    return
  fi
  variables="{\"shortcode\":\"$shortcode\",\"fetch_tagged_user_count\":null,\"hoisted_comment_id\":null,\"hoisted_reply_id\":null$pv_json}"
  curl -sS --max-time 20 -X POST -A "$USER_AGENT" \
    -H "X-IG-App-ID: $APP_ID" \
    -H "X-FB-LSD: $lsd" \
    -H "X-CSRFToken: $csrf" \
    -H "X-FB-Friendly-Name: $FRIENDLY_NAME" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: $BASE_URL" \
    -H "Referer: $BASE_URL/p/$shortcode/" \
    -H "Sec-Fetch-Site: same-origin" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Accept: */*" \
    -H "Accept-Language: $ACCEPT_LANGUAGE" \
    -H "Cookie: $cookies" \
    --data-urlencode "lsd=$lsd" \
    --data-urlencode "doc_id=$doc_id" \
    --data-urlencode "fb_api_req_friendly_name=$FRIENDLY_NAME" \
    --data-urlencode "server_timestamps=true" \
    --data-urlencode "variables=$variables" \
    -o "$body" -w '%{http_code}' "$BASE_URL/graphql/query/" || true # 실패해도 -w 가 000 을 찍는다
}

# pv 이름 목록(콤마 구분) → variables JSON 에 붙일 `,"이름":false` 조각
pv_json_fragment() {
  local list="$1" name out=""
  [ -n "$list" ] || { printf ''; return; }
  for name in $(printf '%s' "$list" | tr ',' ' '); do
    out="$out,\"$name\":false"
  done
  printf '%s' "$out"
}

# ── 조합 명령 ─────────────────────────────────────────────────────────────────

# 번들에서 doc_id 후보·pv 를 뽑는다. stdout 은 parse_bundle 형식 + `bundles=<개수> <바이트>` + `matched=<파일>`.
extract() {
  local shortcode="${1:-}" status page="$TMP/page.html" jar="$TMP/page.jar" urls="$TMP/urls.txt" dir="$TMP/bundles"
  local counts matched f
  [ -n "$shortcode" ] || shortcode="$(printf '%s' "${IG_PROBE_SHORTCODES:-}" | awk '{print $1}')"
  [ -n "$shortcode" ] || fail "extract: shortcode 가 없다(인자 또는 IG_PROBE_SHORTCODES)"
  status="$(fetch_page "$shortcode" "$page" "$jar")"
  [ "$status" = "200" ] || { warn "게시물 페이지가 $status 를 줬다 — 차단으로 본다"; echo "page_status=$status"; return "$EXIT_UNKNOWN"; }
  parse_page "$page" > "$urls"
  counts="$(fetch_bundles "$urls" "$dir")"
  echo "page_status=200"
  echo "bundles=$(printf '%s' "$counts" | awk '{print $1, $2}')"
  echo "bundles_truncated=$(printf '%s' "$counts" | awk '{print $3}')"
  matched=""
  for f in "$dir"/*.js; do
    [ -f "$f" ] || continue
    if grep -q "__d(\"$RELAY_OP\"" "$f"; then
      matched="$matched$(basename "$f") "
      if [ -f "$dir/urls.txt" ]; then
        echo "matched_url=$(sed -n "$(basename "$f" .js)p" "$dir/urls.txt")"
      fi
    fi
  done
  echo "matched=${matched:-none}"
  parse_bundle "$dir"/*.js
}

# 부트스트랩: 게시물 페이지 1회 GET 으로 lsd·csrf·쿠키를 딴다. 성공하면 BOOT_LSD/BOOT_CSRF/BOOT_COOKIES 를 채우고 0,
# 아니면 1 (차단·토큰 없음). 한 shortcode 의 토큰으로 doc_id 여러 개를 조회할 수 있다 — 브라우저도 그렇게 한다.
# ⚠️ 이 셋은 전역 변수에만 산다. 출력하지 않는다.
BOOT_LSD=""; BOOT_CSRF=""; BOOT_COOKIES=""
bootstrap() {
  local shortcode="$1" status
  # bash 3.2 는 한 local 줄 안에서 앞 변수를 뒤에서 못 쓴다 — 두 줄로 나눈다
  local page="$TMP/boot-$shortcode.html" jar="$TMP/boot-$shortcode.jar"
  BOOT_LSD=""; BOOT_CSRF=""; BOOT_COOKIES=""
  status="$(fetch_page "$shortcode" "$page" "$jar")"
  [ "$status" = "200" ] || { warn "게시물 페이지가 $status 를 줬다: $shortcode"; return 1; }
  BOOT_LSD="$(perl -ne 'if (/"LSD",\[\],\{"token":"([^"]+)"/) { print "$1"; exit }' "$page")"
  BOOT_CSRF="$(awk 'BEGIN{FS="\t"} { sub(/^#HttpOnly_/, "") } !/^#/ && NF>=7 && $6=="csrftoken" {print $7; exit}' "$jar")"
  [ -n "$BOOT_CSRF" ] || BOOT_CSRF="$(perl -ne 'if (/"csrf_token":"([^"]+)"/) { print "$1"; exit }' "$page")"
  if [ -z "$BOOT_LSD" ] || [ -z "$BOOT_CSRF" ]; then
    local has_lsd=no has_csrf=no
    [ -z "$BOOT_LSD" ] || has_lsd=yes
    [ -z "$BOOT_CSRF" ] || has_csrf=yes
    warn "토큰을 못 땄다(lsd=$has_lsd, csrf=$has_csrf) — 차단으로 본다: $shortcode"
    return 1
  fi
  BOOT_COOKIES="$(cookie_header "$jar" "$BOOT_CSRF")"
}

# 부트스트랩된 토큰으로 GraphQL 1회. stdout: ok / empty / login_wall / error
query() {
  local doc_id="$1" shortcode="$2" pv_list="${3:-}" status
  local body="$TMP/query-$doc_id-$shortcode.json"
  status="$(fetch_graphql "$doc_id" "$shortcode" "$BOOT_LSD" "$BOOT_CSRF" "$BOOT_COOKIES" "$(pv_json_fragment "$pv_list")" "$body")"
  classify_graphql "$status" "$body"
}

# 주어진 doc_id 로 실제 조회(부트스트랩 + 조회). pv 를 생략하면 current 의 것을 보낸다 —
# 안 보내면 인스타가 missing_required_field_value 로 빈 items 를 줘서 "죽었다" 로 오해한다.
verify() {
  local doc_id="${1:-}" shortcode="${2:-}" pv_list="${3:-}"
  if [ -z "$doc_id" ] || [ -z "$shortcode" ]; then fail "verify <doc_id> <shortcode> [pv,list]"; fi
  [ -n "$pv_list" ] || pv_list="$(current | sed -n 's/^pv=//p')"
  bootstrap "$shortcode" || { echo login_wall; return; }
  query "$doc_id" "$shortcode" "$pv_list"
}

# ── check: 판정표 ────────────────────────────────────────────────────────────
#
#   extracted == current 이고 pv 같음           → 0   (verify 안 함 — www 호출을 아낀다)
#   다르면 verify 를 현재값·새값 둘 다, 기준 게시물마다
#     어느 하나라도 login_wall/error            → 30
#     현재값 ok                                  → 10  changed_current_still_works (사전 통보)
#     현재값 empty 이고 새값 ok                   → 10  rotated (회전 확정)
#     둘 다 empty                                → 30  (기준 게시물 삭제·비공개이거나 변형 차단)
#   정의부 없음 / 후보 2개 이상                    → 30

RESULT_LINES=""
result() { # key value
  RESULT_LINES="$RESULT_LINES$1=$2
"
  [ -z "${IG_RESULT_FILE:-}" ] || printf '%s=%s\n' "$1" "$2" >> "$IG_RESULT_FILE"
}

summary() { # markdown 을 GITHUB_STEP_SUMMARY 에(있으면) + stderr 에
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' "$1" >&2
}

finish() { # exit-code status
  result status "$2"
  result exit_code "$1"
  summary ""
  summary "**판정: \`$2\` (exit $1)**"
  summary ""
  summary '```'
  summary "$RESULT_LINES"
  summary '```'
  exit "$1"
}

check() {
  local cur_doc cur_pv ext ext_docs ext_pv n_docs new_pv shortcodes sc
  local pv_union cur_res new_res cur_any_ok=no new_any_ok=no wall=no

  [ -z "${IG_RESULT_FILE:-}" ] || : > "$IG_RESULT_FILE"
  shortcodes="${IG_PROBE_SHORTCODES:-}"
  [ -n "$shortcodes" ] || fail "IG_PROBE_SHORTCODES 가 비어 있다 — 검증에 쓸 공개 게시물 shortcode 를 공백 구분으로 준다"
  case " $shortcodes " in
    *" TODO"*) fail "IG_PROBE_SHORTCODES 가 자리표시(TODO…)다 — 워크플로 env 나 저장소 Variables 에 실제 공개 게시물 shortcode 를 넣는다" ;;
  esac

  cur_doc="$(current | sed -n 's/^doc_id=//p')"
  cur_pv="$(current | sed -n 's/^pv=//p')"
  result current_doc_id "$cur_doc"
  result current_pv "$cur_pv"
  summary "## 인스타 doc_id 감시"
  summary "- 현재값(application.yml): \`$cur_doc\`"

  ext="$(extract "$(printf '%s' "$shortcodes" | awk '{print $1}')")" || {
    result page_status "$(printf '%s' "$ext" | sed -n 's/^page_status=//p')"
    summary "- 게시물 페이지를 받지 못했다(상태 $(printf '%s' "$ext" | sed -n 's/^page_status=//p')) — 러너 IP 차단일 수 있다"
    finish "$EXIT_UNKNOWN" blocked_page
  }
  result bundles "$(printf '%s' "$ext" | sed -n 's/^bundles=//p')"
  result bundles_truncated "$(printf '%s' "$ext" | sed -n 's/^bundles_truncated=//p')"
  result matched "$(printf '%s' "$ext" | sed -n 's/^matched=//p')"
  result matched_url "$(printf '%s' "$ext" | sed -n 's/^matched_url=//p' | paste -sd' ' -)"
  summary "- 번들: $(printf '%s' "$ext" | sed -n 's/^bundles=//p' | awk '{print $1 "개, " $2 " bytes"}'), 정의부가 든 번들: $(printf '%s' "$ext" | sed -n 's/^matched=//p')"

  ext_docs="$(printf '%s\n' "$ext" | sed -n 's/^doc_id=//p')"
  ext_pv="$(printf '%s\n' "$ext" | sed -n 's/^pv=//p' | paste -sd, -)"
  n_docs="$(printf '%s' "$ext_docs" | grep -c . || true)"
  result extracted_candidates "$(printf '%s' "$ext_docs" | paste -sd' ' -)"
  result extracted_pv "$ext_pv"

  if [ "$n_docs" -eq 0 ]; then
    summary "- 번들에서 \`$RELAY_OP\` 정의부를 찾지 못했다 — 지연 로드 번들이거나 이름이 바뀌었다"
    finish "$EXIT_UNKNOWN" bundle_not_found
  fi
  if [ "$n_docs" -gt 1 ]; then
    summary "- doc_id 후보가 $n_docs 개라 고르지 않는다: $(printf '%s' "$ext_docs" | paste -sd' ' -)"
    finish "$EXIT_UNKNOWN" ambiguous_candidates
  fi
  result extracted_doc_id "$ext_docs"
  summary "- 번들의 값: \`$ext_docs\`"

  # 서버가 안 보내는 pv 가 번들에 생겼나
  new_pv=""
  for sc in $(printf '%s' "$ext_pv" | tr ',' ' '); do
    case ",$cur_pv," in *",$sc,"*) ;; *) new_pv="$new_pv${new_pv:+,}$sc" ;; esac
  done
  result new_pv "$new_pv"
  [ -z "$new_pv" ] || summary "- ⚠️ 서버가 보내지 않는 providedVariables: \`$new_pv\`"

  if [ "$ext_docs" = "$cur_doc" ] && [ -z "$new_pv" ]; then
    summary "- 변화 없음"
    finish "$EXIT_OK" unchanged
  fi

  # 값이 달라졌다 → 현재값·새값을 기준 게시물마다 실제로 조회해 본다
  pv_union="$cur_pv${new_pv:+,$new_pv}"
  for sc in $shortcodes; do
    # shortcode 당 부트스트랩 1회 — 그 토큰으로 현재값·새값을 둘 다 조회한다(www GET 을 아낀다)
    if bootstrap "$sc"; then
      cur_res="$(query "$cur_doc" "$sc" "$cur_pv")"
      new_res="$(query "$ext_docs" "$sc" "$pv_union")"
    else
      cur_res=login_wall; new_res=login_wall
    fi
    result "verify_${sc}_current" "$cur_res"
    result "verify_${sc}_new" "$new_res"
    summary "- 검증 \`$sc\`: 현재값 → \`$cur_res\`, 새값 → \`$new_res\`"
    case "$cur_res$new_res" in *login_wall*|*error*) wall=yes ;; esac
    [ "$cur_res" != ok ] || cur_any_ok=yes
    [ "$new_res" != ok ] || new_any_ok=yes
  done

  if [ "$wall" = yes ]; then
    summary "- 로그인 벽/오류 응답이 있어 판정하지 않는다 — 러너 IP 차단일 수 있다"
    finish "$EXIT_UNKNOWN" blocked_graphql
  fi
  if [ "$cur_any_ok" = yes ]; then
    summary "- **새값이 나왔지만 현재값도 아직 동작한다** — 만료 전에 갱신할 수 있는 사전 통보다"
    finish "$EXIT_CHANGED" changed_current_still_works
  fi
  if [ "$new_any_ok" = yes ]; then
    summary "- **현재값은 빈 응답, 새값은 정상** — doc_id 회전이 확정됐다. 지금 인스타 링크 등록이 전부 실패하고 있다"
    finish "$EXIT_CHANGED" rotated
  fi
  summary "- 현재값·새값 모두 빈 응답 — 기준 게시물이 삭제·비공개됐거나 차단 방식이 바뀌었다"
  finish "$EXIT_UNKNOWN" both_empty
}

# ── 진입점 ───────────────────────────────────────────────────────────────────
cmd="${1:-check}"
[ $# -eq 0 ] || shift
case "$cmd" in
  parse-page) parse_page "$@" ;;
  parse-bundle) parse_bundle "$@" ;;
  classify-graphql) classify_graphql "$@" ;;
  current) current "$@" ;;
  extract) extract "$@" ;;
  verify) verify "$@" ;;
  check) check "$@" ;;
  -h|--help|help) sed -n '2,30p' "$0" ;;
  *) fail "모르는 명령: $cmd (parse-page | parse-bundle | classify-graphql | current | extract | verify | check)" ;;
esac
