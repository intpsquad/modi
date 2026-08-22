#!/usr/bin/env bash
# scripts/instagram-doc-id.sh 의 오프라인 테스트. 네트워크를 쓰지 않는다.
#
#   bash scripts/test/instagram-doc-id.test.sh
#
# 픽스처(scripts/test/fixtures/instagram/)는 전부 손으로 만든 합성 조각이다 —
# 실제 인스타 번들·페이지를 복사하지 않았다. 네트워크 경로는 IG_FETCH_DIR 가짜 응답으로 돈다
# (스크립트 머리말의 "가짜 응답" 절 참고).
#
# bash 3.2(macOS 기본) 호환 — declare -A, mapfile, ${v,,} 를 쓰지 않는다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/instagram-doc-id.sh"
FX="$ROOT/scripts/test/fixtures/instagram"
YML="$ROOT/server/src/main/resources/application.yml"
JAVA="$ROOT/server/src/main/java/com/nomara/modi/server/domain/archive/client/InstagramUrlCrawler.java"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

assert_eq() { # want got label
  if [ "$1" = "$2" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$3"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      want: %s\n      got:  %s\n' "$3" "$1" "$2"
  fi
}

assert_exit() { # want-code label cmd...
  local want="$1" label="$2" got
  shift 2
  "$@" >/dev/null 2>&1
  got=$?
  assert_eq "$want" "$got" "$label"
}

# ── 1~6. parse-bundle ────────────────────────────────────────────────────────
DOC_ONE="11111111111111111"
PV_STD="__relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider"

assert_eq "doc_id=$DOC_ONE" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-match.js" 2>/dev/null | grep '^doc_id=')" \
  "1  parse-bundle: 정의부에서 doc_id 를 뽑는다"
assert_eq "pv=$PV_STD" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-match.js" 2>/dev/null | grep '^pv=')" \
  "1b parse-bundle: providedVariables 키를 뽑는다"

assert_eq "" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-reference-only.js" 2>/dev/null)" \
  "2  parse-bundle: 의존 배열의 참조만 있으면 아무것도 안 나온다"

assert_eq "1" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-two-same.js" 2>/dev/null | grep -c '^doc_id=')" \
  "3  parse-bundle: 같은 값이 두 번 나와도 한 줄"

assert_eq "$(printf 'doc_id=11111111111111111\ndoc_id=22222222222222222')" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-two-differ-a.js" "$FX/bundle-two-differ-b.js" 2>/dev/null | grep '^doc_id=')" \
  "4  parse-bundle: 다른 값 둘은 둘 다 보고한다(고르지 않는다)"

assert_eq "2" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-pv-drift.js" 2>/dev/null | grep -c '^pv=')" \
  "5  parse-bundle: providedVariables 가 늘면 전부 나온다"

assert_eq "pv=$PV_STD" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-neighbor-pv.js" 2>/dev/null | grep '^pv=')" \
  "6  parse-bundle: 앞뒤 이웃 쿼리의 providedVariables 가 새지 않는다"

assert_eq "0" \
  "$("$SCRIPT" parse-bundle "$FX/bundle-neighbor-pv-after.js" 2>/dev/null | grep -c '^pv=')" \
  "6b parse-bundle: 우리 쿼리에 pv 가 없으면 바로 뒤 이웃 것을 가져오지 않는다"

# ── 7~8. parse-page ──────────────────────────────────────────────────────────
assert_eq "$(printf '%s\n%s\n%s' \
  'https://static.cdninstagram.com/rsrc.php/v4/yA/l/ko_KR/aaa111.js?_nc_x=abc' \
  'https://static.cdninstagram.com/rsrc.php/v4/yB/r/bbb222.js' \
  'https://static.cdninstagram.com/rsrc.php/v4/yC/r/ccc333.js')" \
  "$("$SCRIPT" parse-page "$FX/page-with-bundles.html" 2>/dev/null)" \
  "7  parse-page: link·script·이스케이프 JSON 의 번들을 중복 없이 모은다(css 제외)"

assert_eq "" \
  "$("$SCRIPT" parse-page "$FX/page-login.html" 2>/dev/null)" \
  "8  parse-page: 로그인 페이지에는 번들이 없다"

# ── 9. classify-graphql ──────────────────────────────────────────────────────
assert_eq "ok" "$("$SCRIPT" classify-graphql 200 "$FX/graphql-ok.json" 2>/dev/null)" \
  "9a classify-graphql: items 가 있으면 ok"
assert_eq "empty" "$("$SCRIPT" classify-graphql 200 "$FX/graphql-empty.json" 2>/dev/null)" \
  "9b classify-graphql: 200 인데 items 가 비면 empty"
assert_eq "login_wall" "$("$SCRIPT" classify-graphql 200 "$FX/graphql-login.html" 2>/dev/null)" \
  "9c classify-graphql: 200 이어도 HTML 이면 login_wall"
assert_eq "login_wall" "$("$SCRIPT" classify-graphql 302 "$FX/graphql-ok.json" 2>/dev/null)" \
  "9d classify-graphql: 200 이 아니면 본문과 무관하게 login_wall"

# ── 10. current ──────────────────────────────────────────────────────────────
# shellcheck disable=SC2016  # ${…} 는 펼치지 않고 글자 그대로 yml 에 적어야 한다
printf 'modi:\n  archive:\n    instagram:\n      # 마지막 확인: 2026-01-01\n      doc-id: ${ARCHIVE_INSTAGRAM_DOC_ID:12345678901234567}\n' > "$TMP/fixture.yml"
assert_eq "$(printf 'doc_id=12345678901234567\npv=%s' "$PV_STD")" \
  "$("$SCRIPT" current --yml "$TMP/fixture.yml" --java "$JAVA" 2>/dev/null)" \
  "10 current: application.yml 의 \${ARCHIVE_INSTAGRAM_DOC_ID:…} 기본값과 Java 의 pv 집합을 읽는다"
# 실제 저장소 파일은 값을 박지 않는다 — 회전 때 yml 을 고치면 이 테스트가 같이 깨지면 안 된다
case "$("$SCRIPT" current --yml "$YML" --java "$JAVA" 2>/dev/null | sed -n 's/^doc_id=//p')" in
  [0-9][0-9][0-9][0-9][0-9]*) assert_eq ok ok "10b current: 저장소의 application.yml 에서 숫자 doc_id 를 읽는다" ;;
  *) assert_eq "숫자" "$("$SCRIPT" current --yml "$YML" --java "$JAVA" 2>&1 | head -1)" "10b current: 저장소의 application.yml 에서 숫자 doc_id 를 읽는다" ;;
esac

# ── 11. check 판정표 (IG_FETCH_DIR 가짜 응답) ────────────────────────────────
CURRENT_DOC="$("$SCRIPT" current --yml "$YML" --java "$JAVA" | sed -n 's/^doc_id=//p')"

make_bundle() { # doc_id [pv...]  → 정의부 + params 조각을 stdout 으로
  local doc="$1" pvs="" name
  shift
  for name in "$@"; do pvs="${pvs}${pvs:+,}${name}:g(\"${name}\")"; done
  printf '__d("PolarisPostRootQuery_instagramRelayOperation",[],(function(a,b,c,d,e,f){"use strict";e.exports="%s"}),null);\n' "$doc"
  printf '__d("PolarisPostRootQuery.graphql",[],(function(a,b,c,d,e,f,g){"use strict";var h={params:{id:g("PolarisPostRootQuery_instagramRelayOperation"),name:"PolarisPostRootQuery",operationKind:"query",providedVariables:{%s}}};e.exports=h}),null);\n' "$pvs"
}

scenario() { # name bundle-doc page-status [cur-status cur-body new-status new-body]
  local d="$TMP/$1"
  mkdir -p "$d/bundles"
  # SCENARIO_PV 가 있으면 번들의 providedVariables 를 그걸로(공백 구분) 만든다
  # shellcheck disable=SC2086
  make_bundle "$2" ${SCENARIO_PV:-$PV_STD} > "$d/bundles/a.js"
  cp "$FX/page-with-bundles.html" "$d/page.body"
  printf '%s\n' "$3" > "$d/page.status"
  if [ $# -ge 7 ]; then
    printf '%s\n' "$4" > "$d/graphql-$CURRENT_DOC.status"
    cp "$5" "$d/graphql-$CURRENT_DOC.body"
    printf '%s\n' "$6" > "$d/graphql-$2.status"
    cp "$7" "$d/graphql-$2.body"
  fi
  printf '%s' "$d"
}

run_check() { # fetch-dir
  IG_FETCH_DIR="$1" IG_PROBE_SHORTCODES="AAA BBB" CURRENT_YML="$YML" CURRENT_JAVA="$JAVA" \
    IG_RESULT_FILE="$1/result.txt" "$SCRIPT" check
}

# (a) 번들 값 == 현재값 → 0. graphql 가짜 파일을 일부러 두지 않는다 — verify 를 타면 실패해야 한다.
d="$(scenario a "$CURRENT_DOC" 200)"
assert_exit 0 "11a check: 값이 같으면 0 이고 verify 를 하지 않는다" run_check "$d"

# (b) 새값 발견, 현재값은 아직 동작 → 10 (사전 통보)
d="$(scenario b "$DOC_ONE" 200 200 "$FX/graphql-ok.json" 200 "$FX/graphql-ok.json")"
assert_exit 10 "11b check: 새값이 나왔고 현재값도 아직 되면 10" run_check "$d"
assert_eq "status=changed_current_still_works" "$(grep '^status=' "$d/result.txt")" \
  "11b result: 사전 통보로 분류한다"

# (c) 현재값 empty + 새값 ok → 10 (회전 확정)
d="$(scenario c "$DOC_ONE" 200 200 "$FX/graphql-empty.json" 200 "$FX/graphql-ok.json")"
assert_exit 10 "11c check: 현재값이 죽고 새값이 되면 10" run_check "$d"
assert_eq "status=rotated" "$(grep '^status=' "$d/result.txt")" \
  "11c result: 회전 확정으로 분류한다"

# (d) 둘 다 empty → 30 (기준 게시물 삭제·비공개 또는 변형 차단)
d="$(scenario d "$DOC_ONE" 200 200 "$FX/graphql-empty.json" 200 "$FX/graphql-empty.json")"
assert_exit 30 "11d check: 둘 다 비면 판정 불가 30" run_check "$d"
assert_eq "status=both_empty" "$(grep '^status=' "$d/result.txt")" \
  "11d result: 사유가 both_empty 다(다른 이유의 30 과 구분)"

# (e) 로그인 벽 → 30
d="$(scenario e "$DOC_ONE" 200 200 "$FX/graphql-login.html" 200 "$FX/graphql-login.html")"
assert_exit 30 "11e check: 로그인 벽이면 30" run_check "$d"
assert_eq "status=blocked_graphql" "$(grep '^status=' "$d/result.txt")" \
  "11e result: 사유가 blocked_graphql 다(다른 이유의 30 과 구분)"

# (f) 페이지 GET 자체가 302 → 30 (verify 이전 단계에서 차단)
d="$(scenario f "$DOC_ONE" 302)"
assert_exit 30 "11f check: 게시물 페이지가 3xx 면 30" run_check "$d"
assert_eq "status=blocked_page" "$(grep '^status=' "$d/result.txt")" \
  "11f result: 사유가 blocked_page 다(다른 이유의 30 과 구분)"

# (g) 번들 후보가 둘 → 30
d="$TMP/g"; mkdir -p "$d/bundles"
cp "$FX/bundle-two-differ-a.js" "$d/bundles/a.js"; cp "$FX/bundle-two-differ-b.js" "$d/bundles/b.js"
cp "$FX/page-with-bundles.html" "$d/page.body"; printf '200\n' > "$d/page.status"
assert_exit 30 "11g check: 후보가 둘이면 고르지 않고 30" run_check "$d"
assert_eq "status=ambiguous_candidates" "$(grep '^status=' "$d/result.txt")" \
  "11g result: 사유가 ambiguous_candidates 다(다른 이유의 30 과 구분)"

# (h) 번들에 정의부가 없음 → 30
d="$TMP/h"; mkdir -p "$d/bundles"
cp "$FX/bundle-reference-only.js" "$d/bundles/a.js"
cp "$FX/page-with-bundles.html" "$d/page.body"; printf '200\n' > "$d/page.status"
assert_exit 30 "11h check: 정의부를 못 찾으면 30" run_check "$d"
assert_eq "status=bundle_not_found" "$(grep '^status=' "$d/result.txt")" \
  "11h result: 사유가 bundle_not_found 다(다른 이유의 30 과 구분)"

# (j) doc_id 는 같은데 providedVariables 만 늘었다 → verify 를 타고, 현재값이 살아 있으면 10 사전 통보
d="$(SCENARIO_PV="$PV_STD __relay_internal__pv__PolarisNewFlagrelayprovider" \
     scenario j "$CURRENT_DOC" 200 200 "$FX/graphql-ok.json" 200 "$FX/graphql-ok.json")"
assert_exit 10 "11j check: pv 만 늘어도 10" run_check "$d"
assert_eq "new_pv=__relay_internal__pv__PolarisNewFlagrelayprovider" "$(grep '^new_pv=' "$d/result.txt")" \
  "11j result: 새 pv 이름을 적는다"

# (k) 기준 게시물이 자리표시(TODO…)면 판정하지 않고 1 로 죽는다 — 워크플로가 빨갛게 끝나야 한다
d="$(scenario k "$CURRENT_DOC" 200)"
assert_exit 1 "11k check: IG_PROBE_SHORTCODES 가 TODO 자리표시면 1" \
  env IG_FETCH_DIR="$d" IG_PROBE_SHORTCODES="TODO_SHORTCODE_1 TODO_SHORTCODE_2" CURRENT_YML="$YML" CURRENT_JAVA="$JAVA" "$SCRIPT" check

# (i) 토큰이 result 파일·stdout 에 새지 않는다
d="$(scenario i "$DOC_ONE" 200 200 "$FX/graphql-ok.json" 200 "$FX/graphql-ok.json")"
out="$(run_check "$d" 2>&1; cat "$d/result.txt")"
case "$out" in
  *FAKE_LSD_TOKEN*|*FAKE_CSRF*) assert_eq "없음" "토큰 노출" "11i check: lsd/csrf 가 출력에 새지 않는다" ;;
  *) assert_eq "없음" "없음" "11i check: lsd/csrf 가 출력에 새지 않는다" ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $((fail > 0))
