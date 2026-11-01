-- Castle placement and ownership.
-- Requires 001_world_map.sql and the existing game_players table.

CREATE TABLE IF NOT EXISTS player_castles (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    server_id VARCHAR(48) NOT NULL,
    player_id BIGINT UNSIGNED NOT NULL,
    map_object_id VARCHAR(80) NOT NULL,
    castle_name VARCHAR(80) NOT NULL,
    castle_level SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_player_castle_server FOREIGN KEY (server_id)
        REFERENCES game_servers(server_id) ON DELETE CASCADE,
    CONSTRAINT fk_player_castle_player FOREIGN KEY (player_id)
        REFERENCES game_players(id) ON DELETE CASCADE,
    CONSTRAINT fk_player_castle_object FOREIGN KEY (map_object_id)
        REFERENCES world_map_objects(object_id) ON DELETE CASCADE,
    UNIQUE KEY uq_player_castle_per_server (server_id, player_id),
    UNIQUE KEY uq_player_castle_object (map_object_id),
    INDEX idx_player_castle_server (server_id, player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
