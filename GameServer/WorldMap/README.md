# World Map Engine — Development Slice 1

This folder contains the first server-scoped X/Y map prototype.

## Current implementation

- Integer world coordinates per server.
- Region/chunk lookup (default 64 x 64 tiles).
- Nearby-object query bounded by a radius.
- Server-scoped object search by type, name/ID and level.
- Development-only in-memory seed objects for server aetheria-01 and aetheria-02.
- Stable object IDs; coordinates are not used as entity IDs.

## Run locally

From the repository root:

```bash
cd GameServer
dotnet run
```

The API uses the ASP.NET Core launch URL printed by dotnet.

## Development endpoints

Load a region:

```http
GET /world/region?serverId=aetheria-01&regionX=0&regionY=0
```

Load nearby map objects:

```http
GET /world/map?serverId=aetheria-01&centerX=20&centerY=20&radius=40&limit=100
```

Search objects:

```http
GET /world/search?serverId=aetheria-01&type=monster&minLevel=1&maxLevel=10
```

Try server isolation:

```http
GET /world/map?serverId=aetheria-02&centerX=20&centerY=20&radius=40
```

The demo castle on aetheria-02 is deliberately not returned for aetheria-01 queries.

## Important limitations — not production-ready

1. The current service is in-memory and resets on restart. The SQL migration is a persistence design foundation, not yet wired to a repository.
2. Endpoints do not yet authenticate players or derive server assignment from a trusted session. Never expose this prototype publicly as a production game API.
3. No castle placement, movement/march simulation, resource gathering, monster combat or PvP commands are implemented yet.
4. No Redis cache, AOI streaming, region worker distribution or load testing is implemented yet.
5. Map seed data is development-only and must be replaced by admin-managed spawn/configuration data.

## Next implementation slice

1. Add authenticated player sessions and resolve server_id from the player's server assignment.
2. Implement a MySQL/MariaDB repository using the migration in Backend/database/migrations/001_world_map.sql.
3. Add admin-controlled server/map creation and safe object spawning.
4. Add player castle placement with atomic coordinate reservation.
5. Add AOI/chunk subscriptions and rate-limited search.
