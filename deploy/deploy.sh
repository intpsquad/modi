#!/usr/bin/env bash
#
# 앱 층 **무중단 배포**(blue/green). dev 브랜치에 push 될 때 GitHub Actions
# (.github/workflows/ci.yml 의 deploy 잡)가 SSH 로 접속해 이 스크립트를 돌린다.
# **빌드도 서버에서 한다** — Actions 러너는 트리거만 하고, 이미지는 서버(ARM)에서 만들어진다.
# 그래야 아키텍처가 어긋나지 않는다.
#
# 흐름:
#   1) 활성 파일에서 지금 트래픽을 받는 색을 읽는다 (없으면 첫 배포 → blue)
#   2) 반대 색을 빌드해 띄우고 healthy 를 기다린다   ← 이 동안 옛 색이 계속 서비스한다
#   3) 활성 파일을 새 색으로 바꾸고 `caddy reload`   ← 여기가 전환 순간(연결을 떨구지 않는다)
#   4) 옛 색을 graceful 하게 세운다 (in-flight 요청을 끝내고 죽는다)
#
# 2)에서 실패하면 아무것도 전환하지 않고 종료한다 — **옛 색이 그대로 서비스한다.**
#
# 롤백(10초): 활성 파일을 옛 색으로 되돌리고 그 컨테이너를 start 한 뒤 reload 하면 된다.
#   docker start maramodi-spring-blue
#   printf 'reverse_proxy spring-blue:8080\n' > ~/maramodi/active-upstream.conf
#   docker exec maramodi-caddy caddy reload --config /etc/caddy/Caddyfile
# ⚠️ **롤백해도 Flyway 마이그레이션은 되돌아오지 않는다** — README "배포 → 스키마 변경 규칙".
#
# 재배포 대상은 docker-compose.app.yml(spring 두 색/ai/postgres/redis/minio)뿐이다.
# Caddy 는 docker-compose.infra.yml 에 있어 **컨테이너를 건드리지 않는다** — TLS 인증서를 들고
# 있어서다. 설정만 reload 로 갈아 끼운다.
#
# 손으로 돌릴 때도 같은 스크립트를 쓴다:
#   ssh modi
#   cd ~/maramodi/repo && ./deploy/deploy.sh
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.app.yml"

# 운영 환경변수. 저장소 밖(홈 디렉터리)에 두어 배포로 덮이지 않게 한다.
# 다른 경로에 두려면 MARAMODI_ENV_FILE 로 덮는다.
ENV_FILE="${MARAMODI_ENV_FILE:-/home/ubuntu/maramodi/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "!! 환경파일이 없다: $ENV_FILE"
  echo "   deploy/.env.example 을 복사해 값을 채운다 (README '배포' 절 참고)."
  exit 1
fi

compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

# 배포 상태 디렉터리(저장소 밖). 활성 색 파일이 여기 있다.
# ⚠️ `.env` 의 MARAMODI_STATE_DIR 을 읽는다 — compose 가 아니라 이 스크립트가 쓰는 값이라
# grep 으로 꺼낸다(`.env` 를 source 하면 그 안의 모든 비밀값이 셸 환경에 퍼진다).
STATE_DIR="$(grep -E '^MARAMODI_STATE_DIR=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
STATE_DIR="${STATE_DIR:-/home/ubuntu/maramodi}"
ACTIVE_FILE="${STATE_DIR}/active-upstream.conf"

CADDY_CONTAINER=maramodi-caddy

echo "==> 배포 대상 커밋"
git -C "${DEPLOY_DIR}/.." --no-pager log -1 --format='%h %an %s' || true

# ---------------------------------------------------------------------------
# 1) 지금 트래픽을 받는 색
# ---------------------------------------------------------------------------
current=""
if [ -f "$ACTIVE_FILE" ]; then
  current="$(sed -nE 's/^[[:space:]]*reverse_proxy[[:space:]]+(spring-(blue|green)):8080.*/\1/p' "$ACTIVE_FILE" | tail -1)"
fi

case "$current" in
  spring-blue)  next=spring-green ;;
  spring-green) next=spring-blue ;;
  "")
    # 첫 배포거나 활성 파일이 아직 없다. blue 로 시작하고 파일을 만들어 준다.
    next=spring-blue
    echo "==> 활성 색을 찾지 못했다 — 첫 배포로 보고 ${next} 로 시작한다"
    if [ ! -f "$ACTIVE_FILE" ]; then
      echo "!! 활성 파일이 없다: $ACTIVE_FILE"
      echo "   deploy/active-upstream.conf.example 을 그 경로로 복사한 뒤 인프라 층을 다시 올려야"
      echo "   Caddy 가 이 파일을 마운트한다(README '배포' 절). 지금은 파일만 만들어 둔다."
      mkdir -p "$STATE_DIR"
      printf 'reverse_proxy %s:8080\n' "$next" > "$ACTIVE_FILE"
    fi
    ;;
  *)
    echo "!! 활성 파일의 내용을 해석할 수 없다: $ACTIVE_FILE"
    echo "-- 파일 내용 -------------------------------------------------"
    cat "$ACTIVE_FILE" || true
    echo "   'reverse_proxy spring-blue:8080' 또는 spring-green 한 줄이어야 한다."
    echo "   함부로 덮으면 트래픽이 멈춘 색으로 갈 수 있어 여기서 멈춘다."
    exit 1
    ;;
esac

echo "==> 전환: ${current:-(없음)} -> ${next}"

# ---------------------------------------------------------------------------
# 2) 이전 이미지 보관 + 새 색 빌드·기동 + healthy 대기
# ---------------------------------------------------------------------------
# 배포가 잘못됐을 때 재빌드 없이 되돌릴 수 있게 :previous 를 남긴다. blue/green 이라 보통은
# 옛 색 컨테이너를 다시 start 하는 것이 더 빠르지만, 두 색이 다 깨진 경우의 두 번째 그물이다.
# docker image prune 은 태그 없는 것만 지우므로 :previous 는 살아남는다.
echo "==> 이전 이미지 보관 (:previous)"
for img in maramodi-spring maramodi-ai; do
  if docker image inspect "${img}:latest" >/dev/null 2>&1; then
    docker tag "${img}:latest" "${img}:previous"
    echo "    ${img}:latest -> ${img}:previous"
  else
    echo "    ${img}:latest 없음 (첫 배포)"
  fi
done

echo "==> 이미지 빌드 (${next}, ai)"
compose build "$next" ai

# 새 색만 올린다. 옛 색은 건드리지 않는다 — compose 는 지정한 서비스와 그 의존성만 본다.
# (postgres/redis/minio 는 이미 떠 있으면 그대로 두고, 없으면 여기서 healthy 까지 기다린다.)
# ⚠️ `--remove-orphans` 를 쓰지 않는다 — 지금 서비스 중인 컨테이너를 지울 수 있다.
echo "==> ${next} 기동"
compose up -d "$next"

echo "==> ${next} 헬스체크 대기 (최대 240초)"
deadline=$(( SECONDS + 240 ))
while :; do
  health="$(docker inspect -f '{{.State.Health.Status}}' "maramodi-${next}" 2>/dev/null || echo missing)"
  [ "$health" = healthy ] && break

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "!! ${next} 헬스체크 실패 (${health})"
    echo "   🔴 **전환하지 않는다 — ${current:-옛 색} 이 계속 서비스한다.**"
    echo "-- ${next} 로그 ----------------------------------------------"
    compose logs --tail=150 "$next" || true
    # spring 은 minio/postgres/redis 가 healthy 해야 시작한다. 안 떴을 때 원인이 여기 있는
    # 경우가 많아 의존 서비스 로그도 같이 찍는다.
    echo "-- 의존 서비스 로그 (minio/postgres/redis) --------------------"
    compose logs --tail=30 minio postgres redis || true
    exit 1
  fi

  echo "    ${next}=${health} ... 대기"
  sleep 5
done

# ---------------------------------------------------------------------------
# 3) 전환 — 활성 파일 교체 + caddy reload
# ---------------------------------------------------------------------------
# 🔴 **`printf > 파일` 로 제자리 truncate 한다.** 리눅스에서 단일 파일 bind-mount 는 inode 를
# 묶는 것이라, `sed -i`·`mv` 처럼 새 파일을 만들어 갈아치우면 Caddy 컨테이너가 **옛 내용을 계속
# 본다** — 호스트에서 cat 하면 새 내용인데 트래픽은 옛 색으로 가는, 찾기 어려운 실패가 된다.
# ⚠️ 이 함정은 **Docker Desktop(Windows/macOS)에서는 재현되지 않는다**(파일 공유가 경로 기반이다,
#    2026-08-13 실측). 로컬에서 확인하고 규칙을 지우면 운영에서만 터진다.
echo "==> Caddy 를 ${next} 로 전환"
printf 'reverse_proxy %s:8080\n' "$next" > "$ACTIVE_FILE"

if ! docker exec "$CADDY_CONTAINER" caddy reload --config /etc/caddy/Caddyfile; then
  echo "!! caddy reload 실패 — 활성 파일을 ${current:-원래 값} 으로 되돌린다"
  if [ -n "$current" ]; then
    printf 'reverse_proxy %s:8080\n' "$current" > "$ACTIVE_FILE"
  fi
  echo "   Caddy 는 reload 가 실패하면 **옛 설정을 유지**하므로 서비스는 멈추지 않았다."
  echo "   ${next} 컨테이너는 떠 있는 채로 남겨 둔다(원인을 보고 다시 시도할 수 있게)."
  exit 1
fi
echo "    reload 완료 — 새 요청은 ${next} 로 간다"

# ---------------------------------------------------------------------------
# 4) 옛 색 정리 + AI 서버 교체
# ---------------------------------------------------------------------------
if [ -n "$current" ]; then
  # graceful shutdown 이 in-flight 요청을 끝낸다(application.yml 의 server.shutdown: graceful,
  # 최대 30초). compose 의 stop_grace_period 40s 안에 끝나므로 SIGKILL 까지 가지 않는다.
  # 컨테이너는 **지우지 않는다** — 그대로 두면 롤백이 `docker start` 한 번이다.
  echo "==> 옛 색 ${current} 정지 (graceful, 최대 40초)"
  compose stop "$current"
fi

# ⚠️ **AI 서버는 아직 blue/green 이 아니다.** 이 교체 동안 몇 초 끊긴다 — 아카이브 태깅·요약은
# 폴백이 있어 조용히 스킵되지만 **투두 추천은 사용자에게 실패로 보인다.**
echo "==> AI 서버 교체 (단일 — 이 순간 몇 초 끊긴다)"
compose up -d ai

# 교체로 태그를 잃은 이전 레이어들을 정리한다. 놔두면 디스크가 계속 찬다.
# 멈춘 옛 색 컨테이너가 자기 이미지를 붙잡고 있어 롤백 대상은 지워지지 않는다.
echo "==> 태그 없는 이미지 정리"
docker image prune -f >/dev/null || true

echo "==> 배포 완료 (활성: ${next})"
compose ps
