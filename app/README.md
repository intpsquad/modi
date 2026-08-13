# app

팀 목표 협업 앱

## Widgetbook

페이지별 화면은 `widgetbook.dart`에서 실제 화면과 독립적인 샘플 API를 조합해 확인한다. Firebase나 백엔드 호출 없이 렌더링되므로 UI 작업과 리뷰에 사용한다.

```bash
cd app
flutter pub get
flutter run -d chrome -t widgetbook.dart
```

스토리는 `widgetbook/main.dart`에 추가하고, 화면이 요구하는 API 데이터는 `widgetbook/fakes.dart`의 어댑터에 등록한다. Widgetbook의 페이지 목록에서는 iPhone 12와 iPad 뷰포트를 전환할 수 있다.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
