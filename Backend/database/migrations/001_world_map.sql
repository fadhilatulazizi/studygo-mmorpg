-- World Map Engine foundation (MySQL 8 / MariaDB compatible).
-- Apply as a versioned migration; do not run destructive schema changes automatically.

CREATE TABLE IF NOT EXISTS game_servers (
    server_id VARCHAR(48) NOT NULL PRIMARY KEY,
    display_name VARCHAR(80) NOT NULL,
    region_size SMALLINT UNSIGNED NOT NULL DEFAULT 64,
    map_min_coordinate INT NOT NULL DEFAULT 0,
    map_max_coordinate INT NOT NULL DEFAULT 4095,
    server_status ENUM('preparing','open','protected','transfer_locked','maintenance','closed')
        NOT NULL DEFAULT 'preparing',
    released_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_server_region_size CHECK (region_size > 0),
    CONSTRAINT chk_server_map_bounds CHECK (map_min_coordinate < map_max_coordinate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS world_regions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    server_id VARCHAR(48) NOT NULL,
    region_x INT NOT NULL,
    region_y INT NOT NULL,
    region_status ENUM('active','inactive','maintenance') NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_world_region_server FOREIGN KEY (server_id)
        REFERENCES game_servers(server_id) ON DELETE CASCADE,
    UNIQUE KEY uq_world_region_coordinates (server_id, region_x, region_y),
    INDEX idx_world_region_status (server_id, region_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS world_map_objects (
    object_id VARCHAR(80) NOT NULL PRIMARY KEY,
    server_id VARCHAR(48) NOT NULL,
    region_x INT NOT NULL,
    region_y INT NOT NULL,
    coordinate_x INT NOT NULL,
    coordinate_y INT NOT NULL,
    object_type VARCHAR(32) NOT NULL,
    object_level SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    display_name VARCHAR(100) NOT NULL,
    owner_player_id BIGINT UNSIGNED NULL,
    object_status VARCHAR(24) NOT NULL DEFAULT 'active',
    remaining_capacity BIGINT UNSIGNED NULL,
    object_data JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_map_object_server FOREIGN KEY (server_id)
        REFERENCES game_servers(server_id) ON DELETE CASCADE,
    UNIQUE KEY uq_map_object_tile (server_id, coordinate_x, coordinate_y),
    INDEX idx_map_region_objects (server_id, region_x, region_y, object_type),
    INDEX idx_map_search_type_level (server_id, object_type, object_level),
    INDEX idx_map_owner_status (server_id, owner_player_id, object_status),
    INDEX idx_map_name (server_id, display_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Important:
-- 1. Every map query must be scoped by server_id.
-- 2. object_id is the stable identity; coordinates are not primary keys.
-- 3. The unique tile constraint assumes one exclusive map object per tile.
--    If game design later allows stacked objects, replace it with a suitable
--    occupancy/slot model through a reviewed migration.
-- 4. The first C# WorldMapService currently uses in-memory development seed data.
--    Wire these tables through a repository and authenticated player/server
--    assignment before production use.
