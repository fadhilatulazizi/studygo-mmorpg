-- StudyGo AI education domain. Independent from MMORPG economy.
CREATE TABLE IF NOT EXISTS study_subjects (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT NULL,
    icon VARCHAR(80) NULL,
    sort_order SMALLINT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_tasks (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    subject_id BIGINT UNSIGNED NULL,
    title VARCHAR(180) NOT NULL,
    description TEXT NULL,
    due_at DATETIME NULL,
    priority ENUM('low','normal','high') NOT NULL DEFAULT 'normal',
    status ENUM('todo','in_progress','done','cancelled') NOT NULL DEFAULT 'todo',
    reminder_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_study_task_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
    CONSTRAINT fk_study_task_subject FOREIGN KEY (subject_id) REFERENCES study_subjects(id) ON DELETE SET NULL,
    INDEX idx_study_task_user_due (user_id,due_at),
    INDEX idx_study_task_user_status (user_id,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_notes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    subject_id BIGINT UNSIGNED NULL,
    title VARCHAR(180) NOT NULL,
    content MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_study_note_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
    CONSTRAINT fk_study_note_subject FOREIGN KEY (subject_id) REFERENCES study_subjects(id) ON DELETE SET NULL,
    INDEX idx_study_note_user_updated (user_id,updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_ai_daily_usage (
    user_id BIGINT UNSIGNED NOT NULL,
    usage_date DATE NOT NULL,
    questions_used SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    rewarded_questions SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    reward_ads_used TINYINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id,usage_date),
    CONSTRAINT fk_ai_usage_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_ai_requests (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    request_id CHAR(36) NOT NULL,
    provider VARCHAR(24) NOT NULL,
    model VARCHAR(100) NOT NULL,
    prompt_hash CHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ai_request_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_ai_request_id (user_id,request_id),
    INDEX idx_ai_request_user_created (user_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_ad_reward_events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    provider VARCHAR(24) NOT NULL,
    transaction_id VARCHAR(190) NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    reward_amount SMALLINT UNSIGNED NOT NULL DEFAULT 3,
    verified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_ad_reward_transaction (provider,transaction_id),
    CONSTRAINT fk_ad_reward_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO study_subjects(code,name,sort_order) VALUES
('matematika','Matematika',1),('bahasa-indonesia','Bahasa Indonesia',2),
('bahasa-inggris','Bahasa Inggris',3),('ipa','Ilmu Pengetahuan Alam',4),
('ips','Ilmu Pengetahuan Sosial',5),('informatika','Informatika',6);
