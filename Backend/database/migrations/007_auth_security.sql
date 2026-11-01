-- Authentication hardening: login throttling and refresh-token rotation metadata.
CREATE TABLE IF NOT EXISTS studygo_login_throttles (
    identity_hash CHAR(64) NOT NULL PRIMARY KEY,
    failed_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    window_started_at DATETIME NOT NULL,
    locked_until DATETIME NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_login_throttle_lock (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE studygo_refresh_tokens
    ADD COLUMN device_label VARCHAR(100) NULL AFTER token_type,
    ADD COLUMN last_used_at DATETIME NULL AFTER expires_at;

