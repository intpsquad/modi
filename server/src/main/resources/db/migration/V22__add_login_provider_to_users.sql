ALTER TABLE users ADD COLUMN login_provider VARCHAR(20);

-- 카카오는 uid 접두사("kakao:")로 과거 유저까지 확실히 구분 가능해 백필한다.
-- 구글/이메일은 Firebase가 발급한 uid 형태가 provider와 무관하게 동일해서 과거 유저는 구분 불가하다 —
-- null로 남기고 프론트가 "연결됨" 중립 배지로 폴백한다(요청서 명시 동작, specs/OPEN.md 참고).
UPDATE users SET login_provider = 'KAKAO' WHERE id LIKE 'kakao:%';
