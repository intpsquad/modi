#!/usr/bin/env bash
#
# 운영 데이터 백업 — **PostgreSQL 덤프 + MinIO 오브젝트 스냅샷**.
# systemd 타이머(deploy/systemd/modi-backup.timer)가 매일 04:00 KST 에 돌린다.
#
# 🔴 **왜 필요한가**: 서버가 한 대고 디스크도 한 장이다. `postgres-data` 볼륨이 날아가면
# 가입자·방·투두·아카이브가 전부 사라지고 되돌릴 방법이 없다. blue/green 무중단 배포는
# **배포 사고**를 막아줄 뿐 **데이터 손실**과는 아무 상관이 없다.
#
# 🔴 **MinIO 도 같이 뜬다.** DB 만 복구하면 archive_items 의 image_url 이 전부 깨진 링크가
# 된다. 둘은 한 시점의 짝으로만 의미가 있어서 **같은 디렉터리에 같은 타임스탬프로** 넣는다.
#
# 산출물 (저장소 밖 — 배포 rsync 의 `--delete` 가 건드리지 않는다):
#   ~/maramodi/backups/daily/<타임스탬프>/db.dump        pg_dump 커스텀 포맷(압축됨)
#   ~/maramodi/backups/daily/<타임스탬프>/minio.tar.gz   MinIO 볼륨 통째
#   ~/maramodi/backups/daily/<타임스탬프>/manifest.txt   커밋·크기·행수 요약
#   ~/maramodi/backups/weekly/<타임스탬프>/…             일요일자를 하드링크로 따로 보관
#
# 보관 세대: daily 14개, weekly 8개. (2026-08-14 기준 DB 10MB·MinIO 50MB 라
# 22세대를 다 합쳐도 2GB 미만이다. 디스크는 96GB 중 86GB 가 비어 있다.)
#
# ⚠️ **덤프를 뜨는 것과 복구되는 것은 다르다.** 그래서 매 실행마다 `pg_restore --list` 와
# `tar tzf` 로 **읽히는지 확인**하고, 깨졌으면 그 세대를 남기지 않고 실패한다. 반쪽짜리
# 백업이 "성공한 백업"인 척 디렉터리에 남는 것이 제일 위험하다 — 그래서 임시 디렉터리에
# 다 만든 뒤 마지막에 이름을 바꾼다.
#
# 손으로 즉시 한 번 뜨려면:
#   ssh modi
#   ~/maramodi/repo/deploy/backup.sh
#
# 복구는 deploy/restore.sh 를 쓴다.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 디렉터리는 deploy.sh 와 같은 규칙으로 찾는다(저장소 밖, 배포로 덮이지 않는 곳).
ENV_FILE="${MARAMODI_ENV_FILE:-/home/ubuntu/maramodi/.env}"
STATE_DIR=""
if [ -f "$ENV_FILE" ]; then
  # `.env` 를 source 하지 않는다 — 그러면 그 안의 비밀값이 전부 셸 환경에 퍼진다(deploy.sh 와 동일).
  STATE_DIR="$(grep -E '^MARAMODI_STATE_DIR=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
fi
STATE_DIR="${STATE_DIR:-/home/ubuntu/maramodi}"

BACKUP_ROOT="${MARAMODI_BACKUP_DIR:-${STATE_DIR}/backups}"
DAILY_DIR="${BACKUP_ROOT}/daily"
WEEKLY_DIR="${BACKUP_ROOT}/weekly"
KEEP_DAILY="${MARAMODI_KEEP_DAILY:-14}"
KEEP_WEEKLY="${MARAMODI_KEEP_WEEKLY:-8}"

PG_CONTAINER="${MARAMODI_PG_CONTAINER:-maramodi-postgres}"
MINIO_CONTAINER="${MARAMODI_MINIO_CONTAINER:-maramodi-minio}"

fail() { printf '!! 백업 실패: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0) 대상이 실제로 떠 있는지
# ---------------------------------------------------------------------------
docker inspect -f '{{.State.Running}}' "$PG_CONTAINER" 2>/dev/null | grep -q true \
  || fail "${PG_CONTAINER} 가 떠 있지 않다 — 덤프할 대상이 없다"

# MinIO 볼륨 이름을 **컨테이너에서 직접 읽는다.** compose 프로젝트 이름이 바뀌면 볼륨 이름도
# 바뀌는데(maramodi_minio-data → maramodi-app_minio-data 로 실제로 바뀐 적이 있다), 하드코딩해
# 두면 조용히 빈 볼륨을 백업하게 된다.
MINIO_VOLUME="$(docker inspect -f \
  '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' \
  "$MINIO_CONTAINER" 2>/dev/null || true)"
[ -n "$MINIO_VOLUME" ] || fail "${MINIO_CONTAINER} 의 /data 볼륨을 찾지 못했다"

# 컨테이너가 자기 환경변수로 들고 있는 값을 그대로 쓴다 — `.env` 를 읽을 필요가 없다.
PGUSER="$(docker exec "$PG_CONTAINER" printenv POSTGRES_USER)"
PGDB="$(docker exec "$PG_CONTAINER" printenv POSTGRES_DB)"
[ -n "$PGUSER" ] && [ -n "$PGDB" ] || fail "컨테이너에서 POSTGRES_USER/POSTGRES_DB 를 읽지 못했다"

# ---------------------------------------------------------------------------
# 1) 공간 확인 — 디스크를 꽉 채우면 백업이 아니라 장애가 된다
# ---------------------------------------------------------------------------
mkdir -p "$DAILY_DIR" "$WEEKLY_DIR"
AVAIL_MB="$(df -Pm "$BACKUP_ROOT" | awk 'NR==2 {print $4}')"
[ "${AVAIL_MB:-0}" -ge 1024 ] \
  || fail "여유 공간이 ${AVAIL_MB}MB 뿐이다 (최소 1GB 필요) — 오래된 세대를 지우거나 디스크를 늘린다"

TS="$(date -u '+%Y%m%d-%H%M%S')"
TMP_DIR="${DAILY_DIR}/.tmp-${TS}"
OUT_DIR="${DAILY_DIR}/${TS}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
# 도중에 죽으면 임시 디렉터리를 남기지 않는다(다음 실행이 헷갈리지 않게).
trap '[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"' EXIT

printf '==> 백업 시작 %s (DB=%s 사용자=%s 볼륨=%s)\n' "$TS" "$PGDB" "$PGUSER" "$MINIO_VOLUME"

# ---------------------------------------------------------------------------
# 2) PostgreSQL — 커스텀 포맷(-Fc)
# ---------------------------------------------------------------------------
# 컨테이너 **안의** pg_dump 를 쓴다. 호스트에 클라이언트를 깔 필요가 없고, 무엇보다
# pg_dump 버전이 서버 버전보다 낮으면 거부당하는데 이 방식은 항상 정확히 일치한다.
# -Fc 는 압축된 단일 파일이고 pg_restore 로 선택 복구가 된다(-Fp 평문보다 낫다).
# --no-owner: 복구 대상의 롤 이름이 달라도 걸리지 않는다.
printf '  - PostgreSQL 덤프\n'
docker exec "$PG_CONTAINER" \
  pg_dump -U "$PGUSER" -d "$PGDB" -Fc --no-owner > "${TMP_DIR}/db.dump" \
  || fail "pg_dump 가 실패했다"

# 검증: 목록이 읽히면 헤더·TOC 가 온전하다는 뜻이다. 잘린 파일은 여기서 걸린다.
TABLE_COUNT="$(docker exec -i "$PG_CONTAINER" pg_restore --list < "${TMP_DIR}/db.dump" 2>/dev/null \
  | grep -c 'TABLE DATA' || true)"
[ "${TABLE_COUNT:-0}" -gt 0 ] \
  || fail "덤프에서 테이블을 하나도 못 읽었다 — 파일이 깨졌거나 DB 가 비어 있다"

# ---------------------------------------------------------------------------
# 3) MinIO — 볼륨 통째로 tar
# ---------------------------------------------------------------------------
# 읽기 전용으로 붙인 임시 컨테이너에서 tar 를 만든다. MinIO 를 세우지 않아도 되는 이유는
# 업로드된 오브젝트가 **한 번 쓰고 끝**이라서다(수정되지 않는다). 백업 도중 새로 올라온
# 파일이 반쯤 들어갈 수는 있는데, 그건 그 오브젝트 하나가 빠지는 것이지 기존 데이터가
# 깨지는 문제가 아니다.
printf '  - MinIO 스냅샷\n'
docker run --rm -v "${MINIO_VOLUME}:/data:ro" alpine:3 \
  tar czf - -C /data . > "${TMP_DIR}/minio.tar.gz" \
  || fail "MinIO tar 가 실패했다"

tar tzf "${TMP_DIR}/minio.tar.gz" >/dev/null 2>&1 \
  || fail "MinIO tar 가 읽히지 않는다 — 파일이 깨졌다"

# ---------------------------------------------------------------------------
# 4) manifest — 나중에 "어느 시점이냐"를 알 수 있게
# ---------------------------------------------------------------------------
{
  printf '시각(UTC)  : %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')"
  printf '커밋       : %s\n' "$(git -C "${DEPLOY_DIR}/.." --no-pager log -1 --format='%h %s' 2>/dev/null || echo '(알 수 없음)')"
  printf 'DB         : %s (사용자 %s)\n' "$PGDB" "$PGUSER"
  printf 'DB 크기    : %s\n' "$(docker exec "$PG_CONTAINER" psql -U "$PGUSER" -d "$PGDB" -tAc \
      'SELECT pg_size_pretty(pg_database_size(current_database()))' 2>/dev/null || echo '?')"
  printf '테이블 수  : %s\n' "$TABLE_COUNT"
  printf 'MinIO 볼륨 : %s\n' "$MINIO_VOLUME"
  printf '파일 크기  : db.dump %s / minio.tar.gz %s\n' \
    "$(du -h "${TMP_DIR}/db.dump" | cut -f1)" \
    "$(du -h "${TMP_DIR}/minio.tar.gz" | cut -f1)"
  printf '\n-- 주요 테이블 행 수 --\n'
  docker exec "$PG_CONTAINER" psql -U "$PGUSER" -d "$PGDB" -tAc "
    SELECT relname || ' = ' || n_live_tup
      FROM pg_stat_user_tables
     WHERE n_live_tup > 0
     ORDER BY n_live_tup DESC
     LIMIT 20" 2>/dev/null || true
} > "${TMP_DIR}/manifest.txt"

# ---------------------------------------------------------------------------
# 5) 여기까지 왔으면 온전한 세대다 — 이제서야 정식 이름을 준다
# ---------------------------------------------------------------------------
rm -rf "$OUT_DIR"
mv "$TMP_DIR" "$OUT_DIR"
trap - EXIT

# 일요일자는 주간 보관으로 하드링크한다(`cp -al`). 같은 파일시스템이라 공간을 더 쓰지 않는다.
if [ "$(date -u '+%u')" = "7" ]; then
  cp -al "$OUT_DIR" "${WEEKLY_DIR}/${TS}"
  printf '  - 일요일 → weekly 보관\n'
fi

# ---------------------------------------------------------------------------
# 6) 세대 정리
# ---------------------------------------------------------------------------
prune() {
  local dir="$1" keep="$2" old
  # 이름이 타임스탬프라 사전순 = 시간순이다. 최신 $keep 개를 빼고 지운다.
  old="$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name '2*' -printf '%f\n' 2>/dev/null \
         | sort -r | tail -n +"$((keep + 1))")"
  [ -n "$old" ] || return 0
  while IFS= read -r d; do
    rm -rf "${dir:?}/${d}"
    printf '  - 정리: %s/%s\n' "$(basename "$dir")" "$d"
  done <<< "$old"
}
prune "$DAILY_DIR" "$KEEP_DAILY"
prune "$WEEKLY_DIR" "$KEEP_WEEKLY"

TOTAL="$(du -sh "$BACKUP_ROOT" | cut -f1)"
printf '==> 완료: %s (테이블 %s개, 전체 백업 %s)\n' "$OUT_DIR" "$TABLE_COUNT" "$TOTAL"
