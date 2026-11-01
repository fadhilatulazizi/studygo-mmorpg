# Castle Placement — Development Slice 2

## Rules

- One main castle per player per server.
- A castle occupies one exclusive X/Y tile.
- The server must exist and be in open, protected or transfer_locked state.
- transfer_locked is the new-server transfer-in protection window; it does not prevent a new player from creating a fresh castle.
- Coordinates must be within the server's configured map bounds.
- Castle object and player ownership are inserted in one database transaction.
- MySQL unique constraints are the final concurrency guard against two players claiming one tile.

## Database setup

Apply migrations in order:

1. Backend/database/migrations/001_world_map.sql
2. Backend/database/migrations/002_player_castles.sql

The base schema in Backend/database/schema.sql must also be applied so game_players exists.

Create each server row in game_servers before allowing castle placement. Configure server status and map bounds through a trusted admin operation.

## Game server configuration

Set the connection string outside source control, for example through the ASP.NET Core environment variable:

```text
ConnectionStrings__GameDatabase=Server=127.0.0.1;Port=3306;Database=studygo;User ID=game_api;Password=CHANGE_ME;
```

Do not commit real database credentials. Use a least-privilege database account and TLS when connecting across hosts.

## Repository

MySqlCastlePlacementRepository.PlaceAsync(serverId, playerId, x, y, castleName)

The method:
1. Locks and validates the server row.
2. Checks player existence.
3. Checks whether the player already owns a castle on that server.
4. Inserts the world map object and player castle in one transaction.
5. Relies on unique constraints to resolve concurrent tile claims safely.

## Important security boundary

The repository is intentionally not exposed as an anonymous HTTP endpoint yet. Before adding a placement API:
- Authenticate the player using the StudyGo account token/session.
- Resolve player_id from the verified identity, never from request JSON.
- Resolve server_id from the player's trusted server assignment, never trust a client-supplied server_id.
- Apply placement eligibility, spawn-zone rules, rate limits and audit logging.
- Add an authenticated integration test for duplicate placement and simultaneous tile claims.

## Not yet implemented

- Safe spawn-zone selection and protection radius.
- Player-selected tile preview / server-side placement confirmation.
- Castle movement, relocation items and cooldown policy.
- Full map reads from MySQL; the existing map read service still uses development seed data.
- Integration tests against a real MySQL/MariaDB instance.
