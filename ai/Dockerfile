# AI 서버(FastAPI, 투두 추천 S-16-B) 이미지.
# 외부에 포트를 열지 않고 Spring 만 호출한다 — deploy/docker-compose.app.yml 에서
# internal 네트워크에만 붙이고 호스트 포트 바인딩을 하지 않는다.
#
# 태그는 .github/workflows/ci.yml 의 `ai` 잡(astral-sh/setup-uv 의 version)과 **같은 값**으로 고정한다.
# CI 와 운영이 다른 uv/python 으로 돌면 uv.lock 이 같아도 결과가 갈릴 수 있다.
#
# 런타임 이미지를 python:3.12-slim 으로 한 번 더 나누지 않은 이유: 이 uv 이미지가 이미
# python:3.12-slim-trixie 파생이라 줄어드는 용량이 uv 바이너리 정도(수십 MB)뿐인데,
# .venv 를 다른 베이스로 옮기면 인터프리터 경로가 어긋나 조용히 깨질 위험이 붙는다.
FROM ghcr.io/astral-sh/uv:0.11.26-python3.12-trixie-slim

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1

# 락파일만 먼저 → 소스만 바뀐 커밋에서 의존성 레이어를 재사용한다.
# --frozen: uv.lock 을 갱신하지 않는다(CI 게이트와 같은 의도 — 락과 pyproject 가 어긋나면 실패).
# --no-dev: pytest/ruff 는 런타임에 필요 없다.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

COPY src ./src
RUN uv sync --frozen --no-dev

# 비루트 실행. (--system 을 붙이면 uid 1001 이 SYS_UID_MAX 를 넘는다며 경고가 뜬다.)
RUN useradd --create-home --uid 1001 modi && chown -R modi:modi /app
USER modi

# uv run 을 거치지 않고 바로 실행되게 venv 를 PATH 앞에 둔다.
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000
CMD ["uvicorn", "modi_ai.main:app", "--host", "0.0.0.0", "--port", "8000"]
