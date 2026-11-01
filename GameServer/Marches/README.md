# March System — Foundation

This phase establishes persistent, server-authoritative troop dispatch and travel. It does not yet settle gathering rewards, monster combat, scouting intelligence, or PvP battle outcomes.

## Supported mission intents

- `gather`: destination must be a live `resource` map object.
- `hunt`: destination must be a live `monster` map object.
- `scout`: destination may be a live map object.
- `attack`: currently rejected with `pvp_resolution_not_enabled` until battle resolution and protection rules exist.

The march API is deliberately not exposed in the current public Minimal API. The repository method must be called only after the backend authenticates the StudyGo account and resolves its trusted `game_players.id` and selected server. Never accept `playerId` as an authoritative client-supplied identity.

## Database

Apply after migrations 001–003:

```sh
mysql -u USER -p DATABASE < Backend/database/migrations/004_march_system.sql
```

Tables:
- `troop_definitions`: admin-controlled troop type, speed and carry capacity.
- `player_troops`: owned quantity and reserved quantity per player/server.
- `player_marches`: origin/destination snapshots, mission, state and UTC timestamps.
- `march_troop_assignments`: troop composition locked to a march.
- `player_resources`: per-server resource inventory foundation for later gather settlement.

## Runtime behavior

`MySqlMarchRepository.SendAsync`:
1. Validates identifiers, mission and troop composition.
2. Uses a DB transaction and idempotency key (`requestId`) to avoid duplicate dispatch on retry.
3. Locks and verifies the player's castle and destination on the same server.
4. Checks target type and current availability.
5. Locks troop rows, checks unreserved quantity and uses the slowest troop speed.
6. Calculates Euclidean map distance and a provisional travel-time formula: 60 seconds per tile at speed 1, minimum 10 seconds.
7. Creates the march and reserves troop quantities atomically.

`MarchArrivalWorker` checks every five seconds and changes due marches from `traveling` to `arrived`. Troops remain reserved until mission settlement and return-trip logic are implemented. No troop quantities are destroyed by this phase.

## Configuration and testing

Register `MySqlMarchRepository` and `MarchArrivalWorker` only when `ConnectionStrings:GameDatabase` is configured. The worker requires the same DB connection as the spawn worker.

Seed troop definitions are starter values only. Admin/game design must tune them after testing. Player troop balances must be provisioned by a trusted training/GM flow; this migration does not grant troops automatically.

## Not production-ready yet

- No authenticated HTTP endpoint is wired. Integrate with the StudyGo token/session middleware before exposing dispatch.
- No recall/return movement or automatic troop release yet.
- Gather resource depletion and inventory settlement are not yet implemented.
- Hunt combat, drops, scout reports and PvP battle resolution are not yet implemented.
- Travel speed, distance modifiers, march slots, safe zones, shields, anti-farming and guild rally rules remain to be designed.
- Add integration tests against the exact production MySQL/MariaDB version and concurrent reservation tests before launch.
