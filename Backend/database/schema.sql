-- Initial schema scaffold for MySQL 8 / MariaDB.
-- Apply through a controlled migration process in non-development environments.

CREATE TABLE IF NOT EXISTS game_players (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    studygo_user_id BIGINT UNSIGNED NOT NULL UNIQUE,
    display_name VARCHAR(40) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_characters (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    rarity ENUM('common','rare','epic','legendary','mythic') NOT NULL,
    asset_key VARCHAR(255) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_characters (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    player_id BIGINT UNSIGNED NOT NULL,
    character_id BIGINT UNSIGNED NOT NULL,
    level SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    experience BIGINT UNSIGNED NOT NULL DEFAULT 0,
    acquired_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pc_player FOREIGN KEY (player_id) REFERENCES game_players(id),
    CONSTRAINT fk_pc_character FOREIGN KEY (character_id) REFERENCES game_characters(id),
    INDEX idx_pc_player (player_id),
    INDEX idx_pc_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_wallets (
    player_id BIGINT UNSIGNED PRIMARY KEY,
    gold BIGINT UNSIGNED NOT NULL DEFAULT 0,
    gems BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_wallet_player FOREIGN KEY (player_id) REFERENCES game_players(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_transactions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    player_id BIGINT UNSIGNED NOT NULL,
    transaction_type VARCHAR(40) NOT NULL,
    currency VARCHAR(16) NOT NULL,
    amount BIGINT NOT NULL,
    reference_id VARCHAR(128) NULL,
    status ENUM('pending','completed','failed','reversed') NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_tx_player FOREIGN KEY (player_id) REFERENCES game_players(id),
    INDEX idx_tx_player_created (player_id, created_at),
    UNIQUE KEY uq_tx_reference (reference_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
