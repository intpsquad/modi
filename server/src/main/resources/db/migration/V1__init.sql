-- specs/0002-data-model.md 기준 초기 스키마.
-- 방장 개념 없음(멤버 동일 권한), 진행률 등 계산값은 테이블화하지 않음.

CREATE TABLE users (
    id             VARCHAR(128) PRIMARY KEY,
    nickname       VARCHAR(255) NOT NULL,
    profile_image  VARCHAR(1024),
    created_at     TIMESTAMPTZ NOT NULL
);

CREATE TABLE rooms (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(255) NOT NULL,
    cover_image  VARCHAR(1024),
    goal         VARCHAR(255) NOT NULL,
    goal_detail  TEXT,
    start_date   DATE NOT NULL,
    end_date     DATE NOT NULL,
    status       VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED')),
    created_at   TIMESTAMPTZ NOT NULL
);

CREATE TABLE room_members (
    room_id    BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    user_id    VARCHAR(128) NOT NULL REFERENCES users (id),
    joined_at  TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (room_id, user_id)
);
CREATE INDEX idx_room_members_user_id ON room_members (user_id);

CREATE TABLE invite_codes (
    code        VARCHAR(6) PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_invite_codes_room_id ON invite_codes (room_id);

CREATE TABLE categories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_categories_room_id ON categories (room_id);

CREATE TABLE todos (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id       BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    category_id   BIGINT REFERENCES categories (id) ON DELETE SET NULL,
    title         VARCHAR(255) NOT NULL,
    detail        TEXT,
    completed     BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_todos_room_id ON todos (room_id);
CREATE INDEX idx_todos_category_id ON todos (category_id);

CREATE TABLE todo_assignees (
    todo_id  BIGINT NOT NULL REFERENCES todos (id) ON DELETE CASCADE,
    user_id  VARCHAR(128) NOT NULL REFERENCES users (id),
    PRIMARY KEY (todo_id, user_id)
);
CREATE INDEX idx_todo_assignees_user_id ON todo_assignees (user_id);

CREATE TABLE schedules (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    date        DATE NOT NULL,
    time        TIME,
    detail      TEXT,
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_schedules_room_id ON schedules (room_id);

CREATE TABLE archive_folders (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_archive_folders_room_id ON archive_folders (room_id);

CREATE TABLE archive_items (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    folder_id   BIGINT NOT NULL REFERENCES archive_folders (id) ON DELETE CASCADE,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    url         VARCHAR(2048),
    body_text   TEXT NOT NULL,
    source      VARCHAR(255),
    thumbnail   VARCHAR(1024),
    pinned      BOOLEAN NOT NULL DEFAULT FALSE,
    created_by  VARCHAR(128) NOT NULL REFERENCES users (id),
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_archive_items_folder_id ON archive_items (folder_id);
CREATE INDEX idx_archive_items_room_id ON archive_items (room_id);
CREATE INDEX idx_archive_items_created_by ON archive_items (created_by);

CREATE TABLE archive_item_tags (
    item_id  BIGINT NOT NULL REFERENCES archive_items (id) ON DELETE CASCADE,
    tag      VARCHAR(50) NOT NULL,
    PRIMARY KEY (item_id, tag)
);

CREATE TABLE archive_likes (
    item_id     BIGINT NOT NULL REFERENCES archive_items (id) ON DELETE CASCADE,
    user_id     VARCHAR(128) NOT NULL REFERENCES users (id),
    created_at  TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (item_id, user_id)
);
CREATE INDEX idx_archive_likes_user_id ON archive_likes (user_id);

CREATE TABLE pokes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    from_user   VARCHAR(128) NOT NULL REFERENCES users (id),
    to_user     VARCHAR(128) NOT NULL REFERENCES users (id),
    type        VARCHAR(10) NOT NULL CHECK (type IN ('POKE', 'KNOCK')),
    created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_pokes_room_id ON pokes (room_id);
CREATE INDEX idx_pokes_to_user ON pokes (to_user);

CREATE TABLE notification_settings (
    user_id        VARCHAR(128) PRIMARY KEY REFERENCES users (id),
    all_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
    poke_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    knock_enabled  BOOLEAN NOT NULL DEFAULT TRUE
);
