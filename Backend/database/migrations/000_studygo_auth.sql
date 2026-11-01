-- StudyGo AI account foundation. Apply before schema.sql and game migrations.
CREATE TABLE IF NOT EXISTS studygo_users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(190) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(80) NOT NULL,
    account_status ENUM('active','suspended','pending') NOT NULL DEFAULT 'active',
    email_verified_at DATETIME NULL,
    last_login_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_studygo_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS studygo_refresh_tokens (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) NOT NULL,
    token_type ENUM('access','refresh') NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_refresh_token_hash (token_hash),
    INDEX idx_refresh_user_expiry (user_id, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_server_members (
    server_id VARCHAR(48) NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    membership_status ENUM('active','blocked') NOT NULL DEFAULT 'active',
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (server_id, user_id),
    CONSTRAINT fk_server_member_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
    CONSTRAINT fk_server_member_server FOREIGN KEY (server_id) REFERENCES game_servers(server_id) ON DELETE CASCADE,
    INDEX idx_server_member_user (user_id, membership_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
