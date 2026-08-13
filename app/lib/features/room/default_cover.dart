/// 이미지가 없을 때 쓰는 기본 배경.
///
/// `assets/images/covers/cover_01~05.png` 다섯 장 중 하나를 **id 로 정해** 쓴다
/// (2026-08-05 사용자 확정). 저장하지 않으므로 기기를 바꾸거나 앱을 지웠다 깔아도 같은 대상은
/// 늘 같은 배경이고, 대상마다는 서로 다른 배경이 나온다. 서버에는 아무것도 보내지 않는다 —
/// 표시 전용이라 실제 이미지가 있으면 그쪽이 이긴다.
///
/// 쓰는 곳: 방 대표 이미지 미설정(홈 히어로·방 전환 시트), **홈 모아보기 미리보기의 썸네일 없는
/// 자료**(2026-08-05 추가 — 회색 채움만 두면 빈 카드처럼 보였다).
library;

/// 기본 커버 장수. 파일을 늘리면 이 값과 `assets/images/covers/`를 함께 맞춘다.
const int defaultCoverCount = 5;

/// [seed](방 id·자료 id 등)에 해당하는 기본 커버 에셋 경로.
///
/// **무작위로 뽑지 않는다** — 리빌드마다 달라지면 스크롤할 때 배경이 깜빡인다.
String defaultCoverAsset(int seed) {
  // 음수 id 가 들어와도(테스트·비정상 데이터) 범위를 벗어나지 않게 abs 로 접는다.
  final index = seed.abs() % defaultCoverCount + 1;
  return 'assets/images/covers/cover_0$index.png';
}
