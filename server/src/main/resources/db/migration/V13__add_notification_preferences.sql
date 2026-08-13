ALTER TABLE notification_settings
    ADD COLUMN schedule_day_before_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN schedule_dday_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN room_member_joined_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN room_member_left_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN assigned_todo_added_enabled BOOLEAN NOT NULL DEFAULT TRUE;
