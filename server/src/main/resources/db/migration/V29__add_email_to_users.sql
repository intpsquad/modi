ALTER TABLE users ADD COLUMN email VARCHAR(255);

-- 백필 SQL 없음 — login_provider(V22)와 달리 uid만으로는 이메일을 유추할 수 없다.
-- 기존 유저는 다음 로그인(대부분 앱 부팅 시 PUT /me/fcm-token)에서 자연 채워진다(UserService 참고).
-- 카카오 기존 유저는 카카오 개발자 콘솔의 "이메일" 동의항목이 켜져 있어야 다음 카카오 로그인에서 채워진다.
