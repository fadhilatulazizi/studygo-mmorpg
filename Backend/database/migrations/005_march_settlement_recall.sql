-- Mission settlement, return travel, recall and scouting reports.
-- Requires 004_march_system.sql and 003_resource_monster_spawns.sql.

ALTER TABLE player_marches
    ADD COLUMN IF NOT EXISTS return_seconds INT UNSIGNED NULL,
    ADD COLUMN IF NOT EXISTS mission_settled_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS recall_requested_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS result_json JSON NULL;

CREATE TABLE IF NOT EXISTS march_settlements (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    march_id VARCHAR(80) NOT NULL,
    settlement_type ENUM('gather','hunt','scout','recall') NOT NULL,
    result_json JSON NOT NULL,
    settled_at DATETIME NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_march_settlement_march FOREIGN KEY (march_id)
        REFERENCES player_marches(march_id) ON DELETE CASCADE,
    UNIQUE KEY uq_march_settlement_once (march_id),
    INDEX idx_march_settlement_date (settled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS march_scout_reports (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    march_id VARCHAR(80) NOT NULL,
    server_id VARCHAR(48) NOT NULL,
    player_id BIGINT UNSIGNED NOT NULL,
    target_object_id VARCHAR(80) NOT NULL,
    report_json JSON NOT NULL,
    expires_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_scout_report_march FOREIGN KEY (march_id)
        REFERENCES player_marches(march_id) ON DELETE CASCADE,
    CONSTRAINT fk_scout_report_server FOREIGN KEY (server_id)
        REFERENCES game_servers(server_id) ON DELETE CASCADE,
    CONSTRAINT fk_scout_report_player FOREIGN KEY (player_id)
        REFERENCES game_players(id) ON DELETE CASCADE,
    CONSTRAINT fk_scout_report_target FOREIGN KEY (target_object_id)
        REFERENCES world_map_objects(object_id) ON DELETE CASCADE,
    UNIQUE KEY uq_scout_report_march (march_id),
    INDEX idx_scout_report_player (server_id, player_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
