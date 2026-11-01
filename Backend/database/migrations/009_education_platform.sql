-- Account recovery, device sessions, study materials, reminders and notifications.
ALTER TABLE studygo_refresh_tokens ADD COLUMN session_id CHAR(36) NULL AFTER device_label;
UPDATE studygo_refresh_tokens SET session_id=UUID() WHERE session_id IS NULL;
ALTER TABLE studygo_refresh_tokens MODIFY session_id CHAR(36) NOT NULL;
ALTER TABLE studygo_refresh_tokens ADD INDEX idx_refresh_session (user_id,session_id,revoked_at);

CREATE TABLE IF NOT EXISTS studygo_email_tokens (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 token_hash CHAR(64) NOT NULL,
 purpose ENUM('verify_email','password_reset') NOT NULL,
 expires_at DATETIME NOT NULL,
 consumed_at DATETIME NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_email_token_hash(token_hash),
 INDEX idx_email_token_user(user_id,purpose,expires_at),
 CONSTRAINT fk_email_token_user FOREIGN KEY(user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_materials (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 subject_id BIGINT UNSIGNED NULL,
 title VARCHAR(180) NOT NULL,
 description TEXT NULL,
 original_name VARCHAR(255) NOT NULL,
 storage_name VARCHAR(100) NOT NULL,
 mime_type VARCHAR(120) NOT NULL,
 file_size BIGINT UNSIGNED NOT NULL,
 material_type ENUM('pdf','docx','pptx','video','image','other') NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_material_user_created(user_id,created_at),
 CONSTRAINT fk_material_user FOREIGN KEY(user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
 CONSTRAINT fk_material_subject FOREIGN KEY(subject_id) REFERENCES study_subjects(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_reminders (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 task_id BIGINT UNSIGNED NULL,
 title VARCHAR(180) NOT NULL,
 message VARCHAR(1000) NULL,
 remind_at DATETIME NOT NULL,
 status ENUM('pending','sent','cancelled') NOT NULL DEFAULT 'pending',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_reminder_due(status,remind_at),
 CONSTRAINT fk_reminder_user FOREIGN KEY(user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
 CONSTRAINT fk_reminder_task FOREIGN KEY(task_id) REFERENCES study_tasks(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_notifications (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 title VARCHAR(180) NOT NULL,
 body VARCHAR(1000) NOT NULL,
 notification_type VARCHAR(40) NOT NULL DEFAULT 'general',
 data_json JSON NULL,
 read_at DATETIME NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_notification_user_created(user_id,created_at),
 CONSTRAINT fk_notification_user FOREIGN KEY(user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS studygo_admin_audit (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 admin_user_id BIGINT UNSIGNED NOT NULL,
 action VARCHAR(100) NOT NULL,
 target_type VARCHAR(80) NULL,
 target_id VARCHAR(80) NULL,
 metadata_json JSON NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_admin_audit_created(created_at),
 CONSTRAINT fk_admin_audit_user FOREIGN KEY(admin_user_id) REFERENCES studygo_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
