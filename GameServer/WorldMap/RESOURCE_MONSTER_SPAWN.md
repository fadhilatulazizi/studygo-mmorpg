# Resource & Monster Spawn — Development Slice 3

## Design rules

- Resources and monsters are server-scoped world objects.
- Admins configure spawn templates and rectangular spawn zones.
- A zone has a hard alive-object cap and a per-cycle spawn batch limit.
- The worker runs every 30 seconds when a game database connection is configured.
- Spawned objects occupy exclusive map tiles; the database unique tile key prevents overlap with castles, other resources and monsters.
- Resource depletion and monster defeat are expected to set the instance to depleted/defeated and set respawn_at. The worker restores the object after that timestamp.
- All scheduling timestamps use UTC.
- No spawn zone is enabled by default. Admins must review castle safe areas and configure zones deliberately.

## Migration

Apply in order:

1. Backend/database/schema.sql
2. Backend/database/migrations/001_world_map.sql
3. Backend/database/migrations/002_player_castles.sql
4. Backend/database/migrations/003_resource_monster_spawns.sql

## Configure the game server database

Set this environment variable outside source control:

```text
ConnectionStrings__GameDatabase=Server=127.0.0.1;Port=3306;Database=studygo;User ID=game_api;Password=CHANGE_ME;
```

When this setting is present, the game server starts WorldSpawnWorker. It checks enabled spawn zones every 30 seconds. Without it, the map prototype starts without the spawn worker.

## Example templates

Create templates through a protected admin workflow. The following SQL is an example for a development environment only:

```sql
INSERT INTO world_spawn_templates
(template_code, object_type, display_name, object_level, max_capacity, max_hp, respawn_seconds)
VALUES
('food_field_lv1', 'resource', 'Food Field', 1, 12000, NULL, 300),
('wood_forest_lv1', 'resource', 'Woodland', 1, 12000, NULL, 300),
('ashfang_lv2', 'monster', 'Ashfang Beast', 2, NULL, 5000, 600);
```

## Example zones

Choose zone coordinates only after reviewing the castle spawn/safe-area policy. Do not blindly use these sample coordinates on a live server.

```sql
INSERT INTO world_spawn_zones
(server_id, template_id, zone_code, min_x, min_y, max_x, max_y, max_alive, spawn_batch, is_enabled)
SELECT 'aetheria-01', id, 'north-food-fields', 256, 256, 383, 383, 12, 3, 1
FROM world_spawn_templates WHERE template_code = 'food_field_lv1';

INSERT INTO world_spawn_zones
(server_id, template_id, zone_code, min_x, min_y, max_x, max_y, max_alive, spawn_batch, is_enabled)
SELECT 'aetheria-01', id, 'ashen-forest-monsters', 512, 512, 639, 639, 8, 2, 1
FROM world_spawn_templates WHERE template_code = 'ashfang_lv2';
```

## Runtime behavior

WorldSpawnWorker calls MySqlWorldSpawnRepository.RunAllEnabledServersAsync().
For each enabled zone, the repository:
1. Locks the zone and reads its template and server bounds.
2. Reactivates depleted/defeated instances whose respawn_at has passed.
3. Counts currently alive instances.
4. Attempts to spawn up to spawn_batch objects without exceeding max_alive.
5. Uses random coordinates within the zone; unique tile conflicts are retried.
6. Inserts the world map object and spawn instance in one transaction.

## Important integration work still required

- Implement authoritative resource gathering/depletion and monster combat/defeat commands that update instance_state and respawn_at transactionally.
- Add admin authentication, CRUD UI/API and validation for templates/zones.
- Add safe-zone distance checks around player castles and protected areas.
- Move map reads from the in-memory WorldMapService seed data to MySQL.
- Add monitoring for zone saturation, spawn failures and worker health.
- Add integration tests on the actual MySQL/MariaDB version used in deployment.

This is a development foundation, not a production-ready spawn system. Do not expose spawn configuration or mutation endpoints to unauthenticated clients.
