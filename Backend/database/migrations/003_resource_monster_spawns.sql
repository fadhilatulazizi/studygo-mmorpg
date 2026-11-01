-- Resource and monster spawn configuration/runtime.
-- Requires migrations 001_world_map.sql and 002_player_castles.sql.

CREATE TABLE IF NOT EXISTS world_spawn_templates (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    template_code VARCHAR(64) NOT NULL UNIQUE,
    object_type ENUM('resource','monster') NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    object_level SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    max_capacity BIGINT UNSIGNED NULL,
    max_hp BIGINT UNSIGNED NULL,
    respawn_seconds INT UNSIGNED NOT NULL DEFAULT 300,
    object_data JSON NULL,
    is_enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_spawn_template_values CHECK (
        (object_type = 'resource' AND max_capacity IS NOT NULL AND max_capacity > 0)
        OR (object_type = 'monster' AND max_hp IS NOT NULL AND max_hp > 0)
    ),
    INDEX idx_spawn_template_type_enabled (object_type, is_enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS world_spawn_zones (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    server_id VARCHAR(48) NOT NULL,
    template_id BIGINT UNSIGNED NOT NULL,
    zone_code VARCHAR(64) NOT NULL,
    min_x INT NOT NULL,
    min_y INT NOT NULL,
    max_x INT NOT NULL,
    max_y INT NOT NULL,
    max_alive SMALLINT UNSIGNED NOT NULL DEFAULT 10,
    spawn_batch SMALLINT UNSIGNED NOT NULL DEFAULT 2,
    is_enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_spawn_zone_server FOREIGN KEY (server_id)
        REFERENCES game_servers(server_id) ON DELETE CASCADE,
    CONSTRAINT fk_spawn_zone_template FOREIGN KEY (template_id)
        REFERENCES world_spawn_templates(id),
    CONSTRAINT chk_spawn_zone_bounds CHECK (min_x <= max_x AND min_y <= max_y),
    CONSTRAINT chk_spawn_zone_capacity CHECK (max_alive > 0 AND spawn_batch > 0),
    UNIQUE KEY uq_spawn_zone_code (server_id, zone_code),
    INDEX idx_spawn_zone_scheduler (server_id, is_enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS world_spawn_instances (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    object_id VARCHAR(80) NOT NULL,
    zone_id BIGINT UNSIGNED NOT NULL,
    template_id BIGINT UNSIGNED NOT NULL,
    instance_state ENUM('alive','depleted','defeated','respawning') NOT NULL DEFAULT 'alive',
    respawn_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_spawn_instance_object FOREIGN KEY (object_id)
        REFERENCES world_map_objects(object_id) ON DELETE CASCADE,
    CONSTRAINT fk_spawn_instance_zone FOREIGN KEY (zone_id)
        REFERENCES world_spawn_zones(id) ON DELETE CASCADE,
    CONSTRAINT fk_spawn_instance_template FOREIGN KEY (template_id)
        REFERENCES world_spawn_templates(id),
    UNIQUE KEY uq_spawn_instance_object (object_id),
    INDEX idx_spawn_instance_zone_state (zone_id, instance_state),
    INDEX idx_spawn_instance_respawn (instance_state, respawn_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admins must create templates and zones after reviewing map bounds and
-- castle safe-spawn buffers. No spawn zones are enabled automatically.
