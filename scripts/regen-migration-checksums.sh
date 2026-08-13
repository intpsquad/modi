#!/usr/bin/env bash
#
# Flyway 마이그레이션 지문 목록을 다시 만든다.
# 대상: server/src/test/resources/db/migration-checksums.txt (FlywayMigrationImmutabilityTest 가 읽는다)
#
# 🔴 **평소에는 돌릴 일이 없다.** 이 목록의 존재 이유는 "이미 적용된 마이그레이션이 바뀌었다"를
# 잡는 것이다. 목록을 다시 만들면 그 가드를 스스로 해제하는 셈이므로, 아래 두 경우에만 쓴다:
#
#   ① 새 마이그레이션(V<다음번호>)을 추가했다      ← 정상적인 경우
#   ② 과거 파일을 정말 고쳐야 했다(되돌릴 수 없는 이유가 있다)
#      → 이때는 **모든 환경 DB 에서 flyway repair 를 함께** 해야 한다. 안 하면 그 DB 는
#        다음 배포에서 `Validate failed: checksum mismatch` 로 **부팅이 깨진다**
#        (2026-08-13 운영에서 실제로 그렇게 멈췄다 — README "스키마 변경 규칙" 참고).
#
# 지문은 CRLF 를 LF 로 정규화한 내용의 SHA-256 이다 — 윈도우 체크아웃에서도 같은 값이 나와야 한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS="${ROOT}/server/src/main/resources/db/migration"
MANIFEST="${ROOT}/server/src/test/resources/db/migration-checksums.txt"

[ -d "$MIGRATIONS" ] || { echo "!! 마이그레이션 디렉터리가 없다: $MIGRATIONS"; exit 1; }

# 기존 머리말(# 로 시작하는 줄)은 그대로 보존한다 — 사고 기록이 거기 있다.
header="$(sed -n '/^#/p' "$MANIFEST" 2>/dev/null || true)"
if [ -z "$header" ]; then
  echo "!! 매니페스트의 머리말을 못 찾았다. 사고 기록이 사라지지 않게 손으로 확인할 것: $MANIFEST"
  exit 1
fi

tmp="$(mktemp)"
printf '%s\n' "$header" > "$tmp"

# V 번호 숫자 순으로 정렬한다(문자열 정렬이면 V10 이 V2 앞에 온다).
while IFS= read -r f; do
  name="$(basename "$f")"
  # CRLF -> LF 정규화 후 SHA-256
  sum="$(tr -d '\r' < "$f" | sha256sum | cut -d' ' -f1)"
  printf '%s  %s\n' "$name" "$sum" >> "$tmp"
done < <(find "$MIGRATIONS" -name '*.sql' | sort -t/ -k99 | sed 's|.*/||' | sort -V | sed "s|^|${MIGRATIONS}/|")

mv "$tmp" "$MANIFEST"
echo "==> 갱신 완료: $MANIFEST"
echo "    마이그레이션 $(grep -cvE '^#|^$' "$MANIFEST")개"
echo
echo "다음: cd server && ./gradlew test --tests '*FlywayMigrationImmutabilityTest'"
