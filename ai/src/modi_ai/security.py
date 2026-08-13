"""내부 호출 검증.

이 서버는 외부에 포트를 열지 않고 Docker 내부 네트워크에서 Spring 만 호출한다(`CLAUDE.md`).
`X-Internal-Key` 는 그 전제를 코드로 한 번 더 못 박는 공유 시크릿이다.

`INTERNAL_API_KEY` 가 비어 있으면 검증을 건너뛴다 — `FirebaseConfig`/`OpenAiConfig` 의
"키가 없으면 그 기능만 비활성, 나머지는 그대로 동작" 패턴과 같은 방향이다. 로컬에서 curl 로
바로 확인할 수 있어야 하고, CI 에도 키가 없다. 운영에서는 compose 가 반드시 주입한다.
"""

import secrets

from fastapi import Header, HTTPException, status

from modi_ai.config import get_settings


def verify_internal_key(x_internal_key: str | None = Header(default=None)) -> None:
    expected = get_settings().internal_api_key
    if not expected:
        return
    if x_internal_key is None or not secrets.compare_digest(x_internal_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid or missing X-Internal-Key"
        )
