-- March System foundation.
-- Requires 001_world_map.sql and 002_player_castles.sql.
-- Player identity must come from authenticated server context, never request input.

CREATE TABLE IF NOT EXISTS troop_definitions (
    troop_code VARCHAR(48) NOT NULL PRIMARY KEY,
    display_name VARCHAR(80) NOT NULL,
    troop_type ENUM('infantry','archer','cavalry','mage','support','siege') NOT NULL,
    march_speed DECIMAL(8,3) NOT NULL DEFAULT 1.000,
    carry_capacity BIGINT UNSIGNED NOT NULL DEFAULT 0,
    is_enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_troop_speed CHECK (march_speed > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_troops (
    player_id BIGINT UNSIGNED NOT NULL,
    server_id VARCHAR(48) NOT NULL,
    troop_code VARCHAR(48) NOT NULL,
    quantity BIGINT UNSIGNED NOT NULL DEFAULT 0,
    reserved_quantity BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id, server_id, troop_code),
    CONSTRAINT fk_player_troop_player FOREIGN KEY (player_id) REFERENCES game_players(id) ON DELETE CASCADE,
    CONSTRAINT fk_player_troop_server FOREIGN KEY (server_id) REFERENCES game_servers(server_id) ON DELETE CASCADE,
    CONSTRAINT fk_player_troop_definition FOREIGN KEY (troop_code) REFERENCES troop_definitions(troop_code),
    CONSTRAINT chk_troop_reservation CHECK (reserved_quantity <= quantity),
    INDEX idx_player_troop_server (server_id, player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_marches (
    march_id VARCHAR(80) NOT NULL PRIMARY KEY,
    request_id VARCHAR(80) NOT NULL,
    server_id VARCHAR(48) NOT NULL,
    player_id BIGINT UNSIGNED NOT NULL,
    origin_castle_id VARCHAR(80) NOT NULL,
    destination_object_id VARCHAR(80) NOT NULL,
    mission_type ENUM('gather','hunt','scout','attack') NOT NULL,
    march_state ENUM('traveling','arrived','returning','returned','cancelled','failed') NOT NULL DEFAULT 'traveling',
    origin_x INT NOT NULL,
    origin_y INT NOT NULL,
    destination_x INT NOT NULL,
    destination_y INT NOT NULL,
    travel_seconds INT UNSIGNED NOT NULL,
    departed_at DATETIME NOT NULL,
    arrives_at DATETIME NOT NULL,
    return_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_march_server FOREIGN KEY (server_id) REFERENCES game_servers(server_id) ON DELETE CASCADE,
    CONSTRAINT fk_march_player FOREIGN KEY (player_id) REFERENCES game_players(id) ON DELETE CASCADE,
    CONSTRAINT fk_march_castle FOREIGN KEY (origin_castle_id) REFERENCES world_map_objects(object_id),
    CONSTRAINT fk_march_destination FOREIGN KEY (destination_object_id) REFERENCES world_map_objects(object_id),
    UNIQUE KEY uq_march_request (player_id, server_id, request_id),
    INDEX idx_march_due (march_state, arrives_at),
    INDEX idx_march_player (server_id, player_id, march_state),
    INDEX idx_march_destination (server_id, destination_object_id, march_state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS march_troop_assignments (
    march_id VARCHAR(80) NOT NULL,
    troop_code VARCHAR(48) NOT NULL,
    quantity BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (march_id, troop_code),
    CONSTRAINT fk_march_assignment_march FOREIGN KEY (march_id) REFERENCES player_marches(march_id) ON DELETE CASCADE,
    CONSTRAINT fk_march_assignment_troop FOREIGN KEY (troop_code) REFERENCES troop_definitions(troop_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_resources (
    player_id BIGINT UNSIGNED NOT NULL,
    server_id VARCHAR(48) NOT NULL,
    resource_code VARCHAR(48) NOT NULL,
    quantity BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id, server_id, resource_code),
    CONSTRAINT fk_player_resource_player FOREIGN KEY (player_id) REFERENCES game_players(id) ON DELETE CASCADE,
    CONSTRAINT fk_player_resource_server FOREIGN KEY (server_id) REFERENCES game_servers(server_id) ON DELETE CASCADE,
    INDEX idx_player_resource_server (server_id, player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed examples only; tune values in admin after playtesting.
INSERT IGNORE INTO troop_definitions (troop_code, display_name, troop_type, march_speed, carry_capacity) VALUES
('guard_infantry', 'Guard Infantry', 'infantry', 1.000, 10),
('ranger_archer', 'Ranger Archer', 'archer', 1.100, 6),
('swift_cavalry', 'Swift Cavalry', 'cavalry', 1.500, 8),
('apprentice_mage', 'Apprentice Mage', 'mage', 0.900, 2),
('field_support', 'Field Support', 'support', 0.850, 12),
('siege_engine', 'Siege Engine', 'siege', 0.600, 0);
