-- Guest-first sessions and guest-owned planner/AI quota.
CREATE TABLE IF NOT EXISTS studygo_guest_sessions (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 token_hash CHAR(64) NOT NULL UNIQUE,
 expires_at DATETIME NOT NULL,
 claimed_by BIGINT UNSIGNED NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 last_seen_at DATETIME NULL,
 INDEX idx_guest_expiry(expires_at),
 CONSTRAINT fk_guest_claimed_user FOREIGN KEY(claimed_by) REFERENCES studygo_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_guest_tasks (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 guest_id BIGINT UNSIGNED NOT NULL,
 title VARCHAR(180) NOT NULL,
 priority ENUM('low','normal','high') NOT NULL DEFAULT 'normal',
 status ENUM('todo','in_progress','done','cancelled') NOT NULL DEFAULT 'todo',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 INDEX idx_guest_tasks(guest_id,created_at),
 CONSTRAINT fk_guest_task_session FOREIGN KEY(guest_id) REFERENCES studygo_guest_sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_guest_ai_usage (
 guest_id BIGINT UNSIGNED NOT NULL,
 usage_date DATE NOT NULL,
 questions_used SMALLINT UNSIGNED NOT NULL DEFAULT 0,
 PRIMARY KEY(guest_id,usage_date),
 CONSTRAINT fk_guest_ai_session FOREIGN KEY(guest_id) REFERENCES studygo_guest_sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
