#!/usr/bin/env bash
#
# 백업 복구 — deploy/backup.sh 가 만든 세대를 운영에 되돌린다.
#
# 🔴 **이 스크립트는 되돌릴 수 없다.** 지금 DB 와 MinIO 의 내용을 백업 시점으로 **덮어쓴다.**
# 백업 이후에 생긴 데이터는 사라진다. 그래서 실행 전에 **현재 상태를 먼저 백업하고**,
# 확인 문구를 손으로 치게 한다.
#
# 사용법:
#   ~/maramodi/repo/deploy/restore.sh                      # 복구 가능한 세대 목록만 본다
#   ~/maramodi/repo/deploy/restore.sh 20260814-190000      # 그 세대로 복구
#   ~/maramodi/repo/deploy/restore.sh <세대> --db-only     # DB 만
#   ~/maramodi/repo/deploy/restore.sh <세대> --minio-only  # 이미지만
#   ~/maramodi/repo/deploy/restore.sh <세대> --yes         # 확인 생략(자동화용, 사람은 쓰지 말 것)
#
# 흐름:
#   1) 지금 상태를 먼저 백업한다 (복구가 잘못돼도 돌아올 곳을 만든다)
#   2) spring 두 색을 세운다   ← 복구 중에 앱이 쓰기를 하면 안 된다
#   3) DB 복구 (pg_restore --clean, 기존 객체를 지우고 다시 만든다)
#   4) MinIO 복구 (볼륨을 비우고 tar 를 푼다)
#   5) 복구 전에 켜져 있던 색을 다시 띄운다
#
# ⚠️ **앱 코드는 되돌아가지 않는다.** 오래된 백업을 지금 코드에 복구하면 Flyway 가
# "이미 적용된 마이그레이션이 DB 에 없다"며 부팅을 막을 수 있다. 그때는 앱도 그 시점
# 커밋으로 함께 되돌려야 한다(README "배포 → 스키마 변경 규칙").
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${MARAMODI_ENV_FILE:-/home/ubuntu/maramodi/.env}"
STATE_DIR=""
if [ -f "$ENV_FILE" ]; then
  STATE_DIR="$(grep -E '^MARAMODI_STATE_DIR=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
fi
STATE_DIR="${STATE_DIR:-/home/ubuntu/maramodi}"
BACKUP_ROOT="${MARAMODI_BACKUP_DIR:-${STATE_DIR}/backups}"
ACTIVE_FILE="${STATE_DIR}/active-upstream.conf"

PG_CONTAINER="${MARAMODI_PG_CONTAINER:-maramodi-postgres}"
MINIO_CONTAINER="${MARAMODI_MINIO_CONTAINER:-maramodi-minio}"

fail() { printf '!! 복구 실패: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 인자
# ---------------------------------------------------------------------------
TARGET=""; DO_DB=1; DO_MINIO=1; ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --db-only)    DO_MINIO=0 ;;
    --minio-only) DO_DB=0 ;;
    --yes)        ASSUME_YES=1 ;;
    -*)           fail "모르는 옵션: $arg" ;;
    *)            TARGET="$arg" ;;
  esac
done

list_backups() {
  printf '복구 가능한 세대 (%s):\n\n' "$BACKUP_ROOT"
  local found=0 d
  for kind in daily weekly; do
    [ -d "${BACKUP_ROOT}/${kind}" ] || continue
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      found=1
      printf '  %-8s %s   (%s)\n' "$kind" "$(basename "$d")" "$(du -sh "$d" | cut -f1)"
    done <<< "$(find "${BACKUP_ROOT}/${kind}" -mindepth 1 -maxdepth 1 -type d -name '2*' | sort -r)"
  done
  [ "$found" = 1 ] || printf '  (없다 — deploy/backup.sh 를 먼저 돌린다)\n'
}

if [ -z "$TARGET" ]; then
  list_backups
  printf '\n복구하려면: %s <세대이름>\n' "$0"
  exit 0
fi

# 세대 이름만 받아도, 전체 경로를 받아도 되게 한다.
SRC=""
for cand in "$TARGET" "${BACKUP_ROOT}/daily/${TARGET}" "${BACKUP_ROOT}/weekly/${TARGET}"; do
  [ -d "$cand" ] && { SRC="$(cd "$cand" && pwd)"; break; }
done
# 목록도 stderr 로 보낸다 — stdout 으로 내보내면 에러 메시지와 순서가 뒤섞여 보인다.
[ -n "$SRC" ] || { printf '!! 그런 세대가 없다: %s\n\n' "$TARGET" >&2; list_backups >&2; exit 1; }

[ "$DO_DB" = 1 ]    && { [ -f "${SRC}/db.dump" ]      || fail "${SRC}/db.dump 가 없다"; }
[ "$DO_MINIO" = 1 ] && { [ -f "${SRC}/minio.tar.gz" ] || fail "${SRC}/minio.tar.gz 가 없다"; }

# ---------------------------------------------------------------------------
# 확인
# ---------------------------------------------------------------------------
printf '\n========================================================\n'
printf '  복구 대상: %s\n' "$SRC"
printf '========================================================\n'
[ -f "${SRC}/manifest.txt" ] && cat "${SRC}/manifest.txt"
printf '\n덮어쓸 것: %s%s\n' \
  "$([ "$DO_DB" = 1 ] && echo 'PostgreSQL ' || echo '')" \
  "$([ "$DO_MINIO" = 1 ] && echo 'MinIO' || echo '')"
printf '이 시점 이후에 쌓인 데이터는 사라진다.\n\n'

if [ "$ASSUME_YES" != 1 ]; then
  printf "계속하려면 RESTORE 를 그대로 입력한다: "
  read -r answer
  [ "$answer" = "RESTORE" ] || { printf '취소했다.\n'; exit 1; }
fi

docker inspect -f '{{.State.Running}}' "$PG_CONTAINER" 2>/dev/null | grep -q true \
  || fail "${PG_CONTAINER} 가 떠 있지 않다"

PGUSER="$(docker exec "$PG_CONTAINER" printenv POSTGRES_USER)"
PGDB="$(docker exec "$PG_CONTAINER" printenv POSTGRES_DB)"

# ---------------------------------------------------------------------------
# 1) 지금 상태를 먼저 백업 — 복구가 잘못됐을 때 돌아올 곳
# ---------------------------------------------------------------------------
printf '\n==> 복구 전 현재 상태 백업\n'
"${DEPLOY_DIR}/backup.sh" || fail "복구 전 백업이 실패했다 — 여기서 멈춘다(안전장치)"

# ---------------------------------------------------------------------------
# 2) 앱을 세운다 (복구 중 쓰기 차단)
# ---------------------------------------------------------------------------
ACTIVE_COLOR=""
[ -f "$ACTIVE_FILE" ] && ACTIVE_COLOR="$(grep -oE 'spring-(blue|green)' "$ACTIVE_FILE" | head -1 || true)"
printf '\n==> 앱 정지 (현재 활성: %s)\n' "${ACTIVE_COLOR:-알 수 없음}"
for c in maramodi-spring-blue maramodi-spring-green; do
  docker stop "$c" >/dev/null 2>&1 && printf '  - %s 정지\n' "$c" || true
done

# ---------------------------------------------------------------------------
# 3) DB
# ---------------------------------------------------------------------------
if [ "$DO_DB" = 1 ]; then
  printf '\n==> PostgreSQL 복구\n'
  # --clean --if-exists : 기존 객체를 지우고 다시 만든다(없어도 에러 아님)
  # --no-owner          : 덤프에 적힌 롤 이름에 얽매이지 않는다
  # --exit-on-error     : 조용한 부분 실패를 막는다. 반쯤 복구된 DB 가 제일 위험하다.
  docker exec -i "$PG_CONTAINER" \
    pg_restore -U "$PGUSER" -d "$PGDB" --clean --if-exists --no-owner --exit-on-error \
    < "${SRC}/db.dump" \
    || fail "pg_restore 가 실패했다 — DB 가 중간 상태일 수 있다. 위 로그를 보고 판단한다"
  printf '  - 완료\n'
fi

# ---------------------------------------------------------------------------
# 4) MinIO
# ---------------------------------------------------------------------------
if [ "$DO_MINIO" = 1 ]; then
  printf '\n==> MinIO 복구\n'
  MINIO_VOLUME="$(docker inspect -f \
    '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' \
    "$MINIO_CONTAINER" 2>/dev/null || true)"
  [ -n "$MINIO_VOLUME" ] || fail "${MINIO_CONTAINER} 의 /data 볼륨을 찾지 못했다"

  docker stop "$MINIO_CONTAINER" >/dev/null && printf '  - %s 정지\n' "$MINIO_CONTAINER"
  # 볼륨을 비운다. 숨김 파일(.minio.sys)이 있어서 `/data/*` 만으로는 부족하다.
  docker run --rm -v "${MINIO_VOLUME}:/data" alpine:3 \
    sh -c 'rm -rf /data/..?* /data/.[!.]* /data/* 2>/dev/null; true'
  docker run --rm -i -v "${MINIO_VOLUME}:/data" alpine:3 \
    tar xzf - -C /data < "${SRC}/minio.tar.gz" || fail "MinIO tar 를 푸는 데 실패했다"
  docker start "$MINIO_CONTAINER" >/dev/null && printf '  - %s 재시작\n' "$MINIO_CONTAINER"
fi

# ---------------------------------------------------------------------------
# 5) 앱을 다시 띄운다
# ---------------------------------------------------------------------------
printf '\n==> 앱 재시작\n'
if [ -n "$ACTIVE_COLOR" ]; then
  docker start "maramodi-${ACTIVE_COLOR}" >/dev/null && printf '  - maramodi-%s 시작\n' "$ACTIVE_COLOR"
else
  printf '  !! 활성 색을 몰라 자동으로 못 띄운다. 손으로:\n'
  printf '     docker start maramodi-spring-blue\n'
fi

printf '\n==> 복구 완료. 상태를 확인한다:\n'
printf '   docker ps\n'
printf '   curl -sS https://api.maramodi.cloud/actuator/health\n'
