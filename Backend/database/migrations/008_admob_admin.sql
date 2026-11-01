-- AdMob rewarded SSV and admin-managed advertising configuration.
CREATE TABLE IF NOT EXISTS studygo_admin_users (
    user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    admin_role ENUM('owner','admin','editor','support') NOT NULL DEFAULT 'admin',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_studygo_admin_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS studygo_admin_settings (
    setting_key VARCHAR(100) NOT NULL PRIMARY KEY,
    setting_value TEXT NULL,
    updated_by BIGINT UNSIGNED NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_admin_setting_user FOREIGN KEY (updated_by) REFERENCES studygo_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO studygo_admin_settings(setting_key,setting_value) VALUES
('ads.admob_app_id_android',''),('ads.admob_app_id_ios',''),
('ads.admob_banner_unit_id_android',''),('ads.admob_banner_unit_id_ios',''),
('ads.admob_rewarded_unit_id_android',''),('ads.admob_rewarded_unit_id_ios',''),
('ads.admob_interstitial_unit_id_android',''),('ads.admob_interstitial_unit_id_ios',''),
('ads.admob_reward_item','studygo_questions'),('ads.admob_reward_amount','3'),
('ads.admob_ssv_enabled','0');

CREATE TABLE IF NOT EXISTS study_admob_ssv_events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(190) NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    ad_unit VARCHAR(190) NOT NULL,
    reward_item VARCHAR(100) NOT NULL,
    reward_amount INT UNSIGNED NOT NULL,
    event_timestamp BIGINT UNSIGNED NOT NULL,
    key_id BIGINT UNSIGNED NOT NULL,
    verified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_admob_ssv_transaction (transaction_id),
    INDEX idx_admob_ssv_user_verified (user_id,verified_at),
    CONSTRAINT fk_admob_ssv_user FOREIGN KEY (user_id) REFERENCES studygo_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
