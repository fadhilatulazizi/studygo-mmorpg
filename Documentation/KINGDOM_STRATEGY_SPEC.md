# Kingdom Strategy System Specification

Status: Approved direction / initial product specification
Product: StudyGo MMORPG — Aetheria
Repository: fadhilatulazizi/studygo-mmorpg

## 1. Product direction

The Kingdom Strategy System combines:
- Clash of Clans-style personal base construction, grid placement, walls, traps and defensive buildings.
- Lords Mobile-style server world map with X/Y coordinates, resource gathering, monster hunting, scouting, marches, player attacks, rallies and guild territory.
- Existing Aetheria character collection and auto-battle combat.

Each game server owns its own persistent world map and coordinate space. Players are assigned to a server/kingdom. Coordinates are unique only within that server. A player may search and interact with targets on the same server unless a future cross-server event explicitly provides otherwise.

## 2. World map: server-scoped X/Y

### 2.1 Coordinate model
- Every server has a world map identified by server_id.
- Each map location is addressed by (server_id, x, y).
- X and Y are integer tile coordinates. The map is logically partitioned into regions/chunks for loading, simulation and scaling.
- Coordinates must be unique only for exclusive map objects (player castles, resource nodes, monster lairs, event structures) within the relevant occupancy rules.
- World map bounds, region size, terrain distribution and spawn density are server configuration, not client constants.
- A map can expand through additional regions/chunks without changing existing coordinates.
- The client loads nearby map chunks and visible entities only; use AOI (area of interest) and pagination for search results.
- Server-side validation is authoritative for occupancy, pathing, range, movement, march arrival and battle resolution.

### 2.2 Regions and scaling
- A server is one kingdom/world identity; it may be backed by multiple map-region services and simulation workers.
- Region/chunk boundaries are infrastructure partitions, not separate player-facing worlds.
- Marches can cross region boundaries while preserving one server coordinate system.
- Use stable entity IDs; never use X/Y alone as a database primary key.
- Support server status: preparing, open, protected/new, transfer-locked, maintenance, closed.
- Keep the previously specified New Server Release Cooldown rule: a newly released server blocks incoming transfers for the configured initial 30 days, while fresh character creation may be allowed. This is independent of world-map coordinates.

### 2.3 Map objects
Object categories:
- Player castle/base.
- Guild buildings and territory markers.
- Resource tiles: food, wood, stone, iron and gold (if enabled as a gatherable node).
- Monster lairs and roaming monsters.
- NPC camps, ruins, abandoned structures and event objectives.
- Rally points, neutral forts and conquest objectives.

Every object has an ID, server_id, X/Y, type, level, state, owner (optional), capacity/health (where relevant), spawn/respawn rules and visibility policy.

## 3. Personal base building

Each player has one personal base/castle on their assigned server. Base construction uses a separate build-grid layout associated with the castle, while the castle itself occupies one world-map coordinate.

### 3.1 Building placement and upgrades
- Place, move, rotate (if supported), upgrade and demolish eligible buildings.
- Validate grid bounds, collisions, prerequisites, Town Hall level, builder availability and resource costs on the server.
- Upgrades have server-timed construction durations. Client timers are display-only.
- Support saved layouts and a preview/edit mode.
- Buildings have stable IDs, levels, footprints, prerequisites, costs, build times, effects and asset versions.

### 3.2 Initial building categories
- Castle / Town Hall: unlocks building tiers and progression.
- Barracks: infantry recruitment/training.
- Archery Range: archer recruitment/training.
- Stable: cavalry recruitment/training.
- Mage Tower: mage/support recruitment.
- Siege Workshop: siege unit production.
- Farm: food production.
- Lumber Mill: wood production.
- Quarry: stone production.
- Iron Mine: iron production.
- Gold Mine: optional gold production, balanced carefully.
- Warehouse: resource protection and storage capacity.
- Hospital: eligible troop recovery.
- Wall, Archer Tower, Cannon Tower, Mage Tower defense, traps: base defense.
- Academy: research and military/economic technologies.
- Market: controlled resource exchange if enabled.
- Rally Hall / War Council: rally capacity and march coordination.

Admin must be able to configure buildings, footprints, level caps, prerequisites, construction costs/time, production, storage, defense stats and content versions without an app release.

## 4. Resources and gathering

### 4.1 Core resources
- Food: troop upkeep, recruitment and selected upgrades.
- Wood: construction and equipment/war machines.
- Stone: walls, defenses and structures.
- Iron: advanced troops, weapons and upgrades.
- Gold: selected research, crafting and premium-neutral sinks.

EXP is progression, not a spendable resource. Gems remain a premium currency and must not replace the core gameplay resource loop.

### 4.2 Resource nodes
Each node has resource type, level, remaining capacity, gather rate, server coordinate, spawn rules, occupancy state and optional contest/protection rules.

### 4.3 Gathering flow
1. Select a resource node on the same server map.
2. Inspect level, remaining capacity, travel estimate and contest/occupancy status.
3. Select a march and assign troops/commander.
4. Server validates march slots, troop availability, carrying capacity and path.
5. March travels to the node.
6. Gathering begins on server time.
7. Gathering stops on capacity reached, node depleted, recall, interruption or configured event.
8. March returns and deposits resources after arrival.

The server calculates travel, gathering rate, capacity, node depletion and reward. Do not trust client-supplied durations or quantities. Define whether multiple marches may gather from one node and how contested nodes are resolved.

## 5. Monster hunting and PvE expeditions

World map monsters have type, level, HP, element, rewards, spawn schedule, location and respawn rules.

Monster categories:
- Common roaming monster.
- Elite monster.
- Rare monster.
- World Boss.
- Event monster / lair.

Hunt flow:
1. Find or select a monster.
2. View its level, element, threat and known reward preview.
3. Assign hero/commander and troops.
4. Server validates march and encounter requirements.
5. March travels and battle resolves using server-authoritative combat.
6. Return battle report, eligible drops, wounded/lost troops and march status.

Connect monster rewards to the existing character, equipment, crafting-resource and game-economy catalogues. Drop tables and rates are admin-controlled and auditable.

## 6. Target search, scouting and player attacks

### 6.1 Search
Players can search same-server targets by:
- Exact X/Y coordinates.
- Player display name or player ID (with privacy-safe result limits).
- Guild name/tag.
- Nearest visible player castle.
- Castle/Town Hall level range.
- Monster/resource type and level.
- Region or territory.

Search must respect privacy, block lists, server status, protection rules and rate limits. Avoid exposing sensitive account data.

### 6.2 Scouting
A scout march can inspect an eligible target. The server decides what information is revealed based on scout strength, target countermeasures, report level and game rules. Possible report fields:
- Castle/building overview.
- Defensive troop estimate or exact count depending on scouting outcome.
- Wall and trap information.
- Resource quantities, including protected vs lootable amounts.
- Active shield/protection state where appropriate.

Scouting should not reveal hidden account data, exact live presence unless explicitly designed, or information blocked by game rules.

### 6.3 Attack types
- Solo attack.
- Guild rally attack.
- Revenge attack (only under defined eligibility and cooldown rules).
- Territory/fort attack.
- Castle siege.
- Monster/lair attack.

Attack flow:
1. Select target and inspect attack eligibility.
2. Scout optionally.
3. Choose commander/heroes, troop composition and formation.
4. Server validates target protection, range, march slot, troop availability, rally rules and anti-abuse limits.
5. March travels toward target.
6. At arrival, server locks a battle snapshot and resolves combat.
7. Persist battle result and generate battle report.
8. Survivors return; wounded troops follow hospital/recovery rules; permanent losses are applied according to mode.
9. Loot is calculated server-side within protection, storage, capacity and anti-farming limits.

### 6.4 Protection and fairness
- New-player protection with configurable eligibility and duration.
- Castle shield with clear server-side expiry.
- Attack/march limits and anti-farming protections.
- Prevent repeated attacks against the same low-power target for resource abuse.
- Define safe zones, protected states, offline protection policy and guild/territory restrictions.
- Clear warning/confirmation before a player commits to an attack.
- PvP rewards must not create unlimited resource or troop duplication.
- Use battle snapshots and idempotent settlement to prevent replay/double rewards.

## 7. Army, marches and formations

Troop families:
- Infantry.
- Archer.
- Cavalry.
- Mage.
- Support/healer.
- Siege.

Each troop definition includes stable ID, tier, training building, training cost/time, upkeep, capacity, HP, ATK, DEF, SPD, range, role, counters, carry capacity (where applicable), asset refs and balance version.

A march is a server-owned task with:
- march_id, server_id, owner_player_id.
- origin and destination coordinates.
- mission type (gather, hunt, scout, attack, reinforce, return).
- troop composition and commander/hero assignment.
- depart/arrival/return timestamps.
- state and cancellation/recall rules.
- idempotent reward/settlement key.

March slots and capacity can be upgraded through gameplay, buildings or research. Avoid selling direct unlimited march power.

Formations and troop counters should be understandable and balanced. Siege units specialize in structures/walls and should not dominate ordinary field combat. Heroes from Character Collection can lead marches and provide bounded bonuses; they must not replace troop composition or make paid characters mandatory for competitive participation.

## 8. Battle resolution

- Strategic world-map battles are resolved server-side, not by trusting Unity/Flutter client calculations.
- Reuse the existing Combat System specification for stats, elements, status effects and authoritative damage calculations where appropriate.
- Base defense includes walls, traps, defensive buildings, garrison and eligible reinforcements.
- Siege attack uses building/wall damage rules separate from ordinary troop-vs-troop damage.
- Battle report records attacker/defender snapshots, formations, modifiers, losses, wounded, loot, duration, ruleset version and result.
- For large rallies, use deterministic/controlled simulation with bounded battle size and reproducible logs.
- Client may animate the battle presentation, but animation cannot change the result.

## 9. Guild and territory layer

- Guilds may establish or contest territory and build eligible guild structures.
- Rally Hall and guild research can affect coordination within configured caps.
- Territory objectives may include forts, resource bonuses, monster lairs and event structures.
- Guild war and territory battles have scheduled windows, matchmaking/eligibility, contribution logs and reward rules.
- Personal castles remain owned by individual players; guild structures and territory are governed by guild rules.
- Guild leadership changes and member departures must not duplicate or orphan assets.

## 10. Economy, persistence and anti-exploit

- Keep game economy entirely separate from StudyGo Education wallets, grades, quotas and learning rewards.
- Use atomic transactions for resource spend, troop training, march assignment, loot settlement and battle losses.
- Use server time for construction, training, gathering, march travel, shield expiry and battle resolution.
- Use idempotency keys for commands and settlement.
- Maintain immutable audit records for purchases, transfers, resource grants, battle settlements and admin changes.
- Apply rate limits, bot detection, anomaly detection and server-side validation.
- Do not trust client coordinates, resource counts, troop counts, battle outcomes or timers.
- Provide admin controls for map generation, node spawn rates, monster spawns, protection, attack limits, troop balance, building balance and event configuration.

## 11. Suggested backend entities

Initial logical tables/collections:
- game_servers
- world_regions
- world_map_objects
- player_castles
- castle_buildings
- castle_layouts
- player_resources
- resource_nodes
- troop_definitions
- player_troops
- troop_training_queue
- player_marches
- march_troop_assignments
- monster_definitions
- monster_spawn_instances
- scouting_reports
- battle_instances
- battle_reports
- battle_participants
- guild_territories
- guild_structures
- world_events
- game_audit_logs

Use server_id on all server-scoped records. Use stable IDs and indexes such as:
- UNIQUE(server_id, x, y) where exclusive occupancy applies.
- INDEX(server_id, region_id, object_type).
- INDEX(server_id, owner_player_id, status).
- INDEX(server_id, status, arrival_at) for active marches.
Exact schema and sharding strategy must be validated against expected scale and database engine.

## 12. API surface (illustrative)

- GET /world/map?server_id=&center_x=&center_y=&radius=
- GET /world/search?server_id=&type=&query=&min_level=&max_level=
- GET /world/objects/{object_id}
- POST /world/marches/gather
- POST /world/marches/hunt
- POST /world/marches/scout
- POST /world/marches/attack
- POST /world/marches/recall
- GET /world/marches
- GET /world/battle-reports
- POST /base/buildings/place
- POST /base/buildings/upgrade
- POST /base/buildings/move
- GET /base/layout
- GET /base/resources
- POST /army/train
- GET /army/status

All endpoints require authenticated player identity. Server ID must be checked against the player's assigned server; never accept arbitrary cross-server actions from client input.

## 13. Implementation phases

Phase 1 — Base and map foundation:
- Server assignment, map coordinate service, region/chunk loading, personal castle placement.
- Base grid, building placement/upgrades, basic production/storage.

Phase 2 — Army and gathering:
- Troop definitions/training, march queue, resource nodes, gathering and return.

Phase 3 — PvE:
- Monster spawn, hunt marches, server battle simulation, drops and reports.

Phase 4 — PvP:
- Player search, scouting, protection/shields, solo attack, loot and battle reports.

Phase 5 — Guild warfare:
- Rally, reinforcement, territory objectives, siege and scheduled guild events.

Load-test region streaming, map search, march processing, battle settlement and concurrent resource-node contention before opening a server to large populations.

## 14. Acceptance criteria for first playable strategy loop

- A player is assigned to one server and has a unique castle coordinate on that server.
- Player can load nearby map chunks and search valid objects by X/Y.
- Player can place and upgrade at least one economic and one military building.
- Player can train troops and send a march to a resource node.
- Server processes travel, gathering, return and resource deposit exactly once.
- Player can send a march to a PvE monster and receive a server-generated battle report.
- Client cannot forge coordinates, travel time, troop availability, battle outcome or rewards.
- No strategy-system currency or progression can affect StudyGo education features.
