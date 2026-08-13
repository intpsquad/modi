-- 회원 탈퇴(계정 삭제, specs/0012-설정.md S-40) 지원. users.id 를 참조하는 FK 7곳이 전부
-- ON DELETE 절 없이(기본 NO ACTION) 생성돼 있어(V1__init.sql), 지금 상태로는 room_members 등에
-- 행이 하나라도 남아 있는 유저는 삭제 자체가 FK 위반으로 실패한다.
--
-- room_members 는 일부러 그대로 둔다 — 탈퇴 로직이 유저 삭제 전에 모든 방을 먼저 나가게 하므로,
-- 만약 로직에 구멍이 있으면 여기서 시끄럽게 실패하는 편이 유령 멤버십을 조용히 남기는 것보다 낫다.
--
-- archive_items.created_by 는 CASCADE 가 아니라 SET NULL 이다 — 탈퇴한 사람이 쓴 자료라도
-- 같은 방의 다른 멤버들이 계속 보는 공유 콘텐츠이기 때문이다(사용자 확정, 2026-08-03). 나머지
-- (todo_assignees·archive_likes·pokes·notification_settings)는 공유 콘텐츠가 아니라 본인의
-- 개인 활동 기록이라 CASCADE 로 함께 지운다.
ALTER TABLE archive_items ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE archive_items DROP CONSTRAINT archive_items_created_by_fkey;
ALTER TABLE archive_items
    ADD CONSTRAINT archive_items_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE todo_assignees DROP CONSTRAINT todo_assignees_user_id_fkey;
ALTER TABLE todo_assignees
    ADD CONSTRAINT todo_assignees_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE archive_likes DROP CONSTRAINT archive_likes_user_id_fkey;
ALTER TABLE archive_likes
    ADD CONSTRAINT archive_likes_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE pokes DROP CONSTRAINT pokes_from_user_fkey;
ALTER TABLE pokes
    ADD CONSTRAINT pokes_from_user_fkey
    FOREIGN KEY (from_user) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE pokes DROP CONSTRAINT pokes_to_user_fkey;
ALTER TABLE pokes
    ADD CONSTRAINT pokes_to_user_fkey
    FOREIGN KEY (to_user) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE notification_settings DROP CONSTRAINT notification_settings_user_id_fkey;
ALTER TABLE notification_settings
    ADD CONSTRAINT notification_settings_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;
