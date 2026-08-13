# pre-commit 게이트 (개념 정의)
커밋 전 자동 실행되어야 하는 검사. husky/lefthook 또는 git hook로 연결.
- app/:  `dart format --set-exit-if-changed .`  +  `flutter analyze`  +  `flutter test`
- server/: `./gradlew spotlessCheck test` (또는 사용 포매터)
- 시크릿 스캔 (.env/키 커밋 방지)
실패 시 커밋 차단. AI가 무엇을 했든 이 게이트를 통과하지 못하면 커밋되지 않는다.
