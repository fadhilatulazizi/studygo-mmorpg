# StudyGo MMORPG — Combat System Specification

**Status:** Proposed baseline for implementation  
**Game world:** Aetheria  
**Client:** Unity 2D side-scrolling gameplay  
**Backend:** PHP Native account/economy APIs + authoritative real-time game server  
**Initial combat model:** Auto Battle + Side View + Hybrid Targeting

## 1. Product decisions

The launch combat model is fixed as follows:

- **Combat style: Auto Battle.** Once combat is engaged, the character performs basic attacks automatically and uses eligible skills according to the configured auto-combat policy. Players do not need to tap an attack button repeatedly.
- **Camera: Side-scrolling 2D.** The gameplay camera views the world from the side. Characters and enemies move primarily along the horizontal play lane, with controlled vertical positioning for jumping, platforms or depth lanes where a map requires them.
- **Targeting: Hybrid.** The game automatically selects a suitable target, while the player can manually select or switch to another valid target. Manual selection takes priority until the target becomes invalid or the player returns to auto-target mode.
- **Character preview remains 3D** in Character and Equipment screens. Combat gameplay uses optimized 2D sprites/rigs and animation assets unless a future content mode explicitly introduces 3D gameplay.

These decisions apply to PvE and PvP, with mode-specific rules and balancing.

## 2. Combat experience and player controls

### 2.1 Default controls

The combat HUD should provide:
- Target information panel (name, level, HP bar, elite/boss indicator).
- Basic attack status (automatic; no repeated attack input required).
- Skill buttons for available active skills, with cooldown overlays and resource costs.
- Target switch/target lock control.
- Auto-combat toggle where the game mode permits it.
- Potion/consumable quick slots where permitted.
- Dodge, jump or movement controls only in modes/maps that support those actions.
- Party member status and boss mechanic warnings when relevant.

### 2.2 Auto Battle behavior

When auto-combat is enabled:
1. Validate that the character is alive, not crowd-controlled and allowed to act.
2. Find a valid target using the target-selection policy.
3. Move toward or maintain a valid attack position using navigation and lane constraints.
4. Perform basic attacks at the character's configured attack interval.
5. Evaluate active skills according to the skill priority/rotation policy.
6. Re-evaluate target, range, line of sight, status effects and combat state after each action.
7. Stop or change behavior when the target dies, becomes invalid, leaves the encounter, or the character enters a restricted state.

Auto Battle must not mean unlimited or instantaneous attacks. Every attack, skill, movement action and resource cost is validated by the game server.

### 2.3 Player agency

- Players may manually select any valid visible target allowed by the mode.
- A manually selected target is retained while alive, valid, in the encounter and reachable.
- If the selected target dies, despawns, becomes invalid or leaves the permitted range for a configured grace period, return to auto-target.
- Provide a clear target-lock indicator and a clear way to release the lock.
- In PvP, auto-target must obey the selected mode's target rules; it must not target spectators, protected players or invalid opponents.
- Boss mechanics may require manual target selection or interaction; auto-combat must not bypass encounter mechanics.

## 3. Target selection policy

### 3.1 Hybrid targeting priority

Default priority when no manual target is locked:
1. Valid enemy actively attacking the player or their party, if threat rules permit.
2. Valid enemy currently engaged by the player/party.
3. Nearest valid enemy within the acquisition radius.
4. If multiple targets are equally suitable, use stable tie-breakers such as distance, threat and server entity ID.

The exact priority order is configurable per game mode and encounter. Do not select targets through walls, outside the encounter, across forbidden lanes, or outside the server-defined acquisition radius.

### 3.2 Target validation

A target is valid only if all applicable conditions are true:
- Exists in the current world/instance and is alive.
- Is hostile and attackable by this player in the current mode.
- Is within acquisition/attack range and permitted lane/line of sight.
- Is not protected by spawn safety, sanctuary, stealth/invulnerability rules or encounter phase rules.
- Is not a spectator, disconnected entity or already removed from the encounter.
- PvP target is an eligible opponent under party, guild, team, duel or arena rules.

### 3.3 Suggested initial target parameters

These are tuning defaults, not hardcoded constants:
- Auto-acquisition radius: 8 in-game world units.
- Preferred attack distance: configured per weapon/skill archetype.
- Manual target retention grace period: 3 seconds outside valid range before releasing, unless the mode requires immediate release.
- Retarget evaluation: event-driven after target state changes, with a low-frequency safety recheck; avoid expensive per-frame server scans.
- Target list: only entities relevant to the player's Area of Interest (AOI).

## 4. Side-scrolling world and movement

- Use a 2D side-view camera with camera follow, bounds and encounter framing.
- Each map defines playable lanes, floor/platform geometry, collision boundaries and allowed movement regions.
- Movement uses server-validated velocity/position limits; clients may predict local movement but server state is authoritative.
- Melee characters must approach a valid melee position before attacking. Ranged characters maintain their configured range where navigation permits.
- Pathing must handle obstacles, platforms and lane transitions without moving through walls or restricted areas.
- Avoid camera shake, hit-stop or large visual effects that obscure critical combat information. Provide reduced-effects options.
- AOI determines which players, monsters, projectiles and effects are replicated to each client.

## 5. Character combat attributes

Use the existing character catalogue as the source of base stats. The following combat attributes are standardized:

| Attribute | Meaning |
|---|---|
| HP | Health; at zero the character is defeated |
| ATK | Base attack power |
| DEF | Reduces incoming damage |
| SPD | Movement/attack-speed contribution, with mode-specific caps |
| Crit Rate | Chance of a critical hit |
| Crit Damage | Damage multiplier for critical hits |
| Accuracy | Chance to hit where evasion applies |
| Evasion | Chance to avoid eligible attacks |
| Shield | Absorbs damage before HP, following shield rules |
| Element Power | Bonus for the character's element and eligible skills |
| Element Resistance | Reduces incoming elemental damage |
| Tenacity | Reduces eligible control-effect duration/strength |

- Keep base attributes and derived combat values separate.
- All derived stats are calculated using server-side versioned formulas.
- Apply hard caps or diminishing returns to speed, critical chance, evasion, resistance and control effects to prevent runaway scaling.
- HP, ATK, DEF and SPD remain visible core stats; advanced attributes may be shown in a detailed view.

## 6. Damage and mitigation model

Use a versioned, server-authoritative damage pipeline. Initial reference model:

1. Resolve base skill/basic-attack power from the attacker's stats and skill coefficient.
2. Apply permitted attacker bonuses (equipment, buffs, elemental power).
3. Apply hit, accuracy, evasion and critical checks where the mode uses them.
4. Apply target DEF and eligible damage reduction.
5. Apply elemental resistance and PvP/PvE mode modifiers.
6. Apply shields before HP damage.
7. Apply damage caps, encounter rules and rounding.
8. Record combat result and emit the replicated event.

Illustrative baseline formula (to be play-tested and tuned):
- rawDamage = (ATK * skillCoefficient) + flatBonus
- mitigatedDamage = rawDamage * 100 / (100 + effectiveDEF)
- finalDamage = mitigatedDamage * elementModifier * modeModifier * criticalModifier
- actualDamage = min(targetRemainingEffectiveHP, max(1, round(finalDamage)))

This formula is a starting point, not a final balance promise. Boss phases, shields, damage-over-time, true damage and scripted mechanics may use explicit, documented overrides. Never let the client submit final damage.

## 7. Elements and status effects

Initial elements:
- **Fire:** damage-over-time Burn.
- **Water:** control/slow or Freeze on eligible targets.
- **Wind:** mobility, attack speed or evasion bonuses.
- **Earth:** defense, stagger or limited stun.
- **Light:** healing, cleanse and protective effects.
- **Shadow:** debuffs, weakening and damage effects.

Element advantages should be modest and contextual. Avoid a simple permanent rock-paper-scissors system that makes a character unusable against one matchup. Admins can configure per-monster and per-mode modifiers.

Initial status-effect families:
- Burn: periodic damage.
- Slow: reduces movement/attack speed within caps.
- Freeze: brief control effect, subject to boss/PvP diminishing returns.
- Stun: prevents selected actions for a short duration.
- Shield: absorbs eligible damage.
- Heal-over-time: restores HP over time.
- Weaken: reduces selected outgoing stats.
- Cleanse: removes specified removable effects.

Every status effect defines duration, stacking/refresh policy, source attribution, immunity rules, PvP scaling and boss resistance. Bosses must not be permanently crowd-controlled.

## 8. Skills and auto-skill policy

Each character may have:
- Basic attack (automatic).
- Active skills (initial target: 3–4 slots, configurable by character design).
- Passive skills.
- Optional ultimate skill with a charge/energy condition.

Each skill record must define:
- Permanent skill ID, display name, description and icon.
- Skill type, element, target type and range.
- Cooldown, resource cost and cast/animation duration.
- Damage/healing coefficient, status effects and area shape.
- Valid targets, allowed modes, interruption rules and PvP scaling.
- Animation/VFX/SFX asset references and content version.

### Auto-skill behavior

- Admin/designers define a default skill priority per character.
- Players may choose from permitted presets such as Balanced, Burst, Survival or Manual Skills.
- Auto-use checks cooldown, resource availability, target validity, range and skill conditions.
- Defensive/healing skills may use configurable HP/shield thresholds.
- Ultimate skills may default to manual or use a player-selected auto policy.
- Auto-skill must never ignore boss telegraphs or mode restrictions.
- Skill priorities and thresholds are server-validated; clients send intent/settings, not combat outcomes.

## 9. PvE rules

PvE includes field monsters, elite monsters, dungeons, raids, survival and tower modes.

- Monsters use server-side state machines: idle, patrol, acquire, approach, attack, cast, stagger, phase transition, defeated and respawn.
- Monster threat/aggro is server-owned. Threat may consider damage, healing, proximity and scripted roles.
- Bosses have telegraphed attacks, phases, weak points or mechanics where appropriate.
- Auto Battle can execute ordinary combat but must not automatically solve every mechanic.
- Dungeon/raid rewards are issued once per validated clear and protected against duplicate claims.
- Drop tables, rates, level requirements and reward limits are configured server-side and versioned.
- Instance rules define party size, encounter reset, entry limits and disconnect/rejoin behavior.

## 10. PvP rules

PvP modes include friendly battle, ranked arena, tournament and guild war.

- Use server-authoritative hit validation, cooldowns, resources, status effects and match results.
- Apply mode-specific stat normalization or rating brackets to reduce pay-to-win and progression gaps.
- Auto Battle may perform basic attacks and configured skills, but target eligibility is restricted to opponents.
- Friendly fire, team targeting, spectator protection and spawn protection are explicit mode settings.
- Ranked results, rating changes and rewards are committed once per match with idempotent match IDs.
- Competitive modes may disable consumables, limit auto-skill presets or require manual ultimate activation.
- Disconnects, AFK behavior, surrender and match-abandon penalties are configured per mode.
- Never award a ranked win solely because a client reports a result.

## 11. Death, revival and recovery

- At zero HP, enter a server-defined defeated state and stop attack/skill execution.
- PvE recovery may allow a safe-hub respawn, party revival or eligible Revival Feather.
- PvP uses mode-specific respawn, round or match-end rules; paid revival must not create competitive advantage.
- Define temporary invulnerability after respawn and prevent spawn camping.
- Clear or preserve buffs/debuffs according to mode rules.
- Prevent duplicate death, revival or reward events using unique event IDs.

## 12. Network and authoritative server design

The real-time game server is authoritative for:
- Entity positions and legal movement.
- Target acquisition and target validity.
- Attack timing, skill cooldowns and resource costs.
- Hit validation, damage, healing and status effects.
- Monster AI, aggro, encounter phases and drops.
- PvP match state, scoring and results.

Unity client responsibilities:
- Render side-scrolling world, sprites, animations, VFX and UI.
- Send movement/target/skill intents and player settings.
- Predict responsive local presentation where safe, then reconcile with server snapshots/events.
- Never decide final damage, loot, currency, cooldown completion or match outcome.

Networking:
- Use authenticated persistent real-time transport (for example WebSocket initially; evaluate a lower-latency transport if load tests require it).
- Use sequence numbers, timestamps, entity IDs and idempotency keys for critical commands/events.
- Validate message size, rate, ownership, state transitions and replay protection.
- AOI-filter updates so each client receives only relevant nearby entities.
- Separate persistent account/economy APIs from real-time combat messages.
- Redis may support ephemeral coordination/state; MySQL/MariaDB stores durable progression and transactions.

## 13. Admin and content configuration

Admin Dashboard must configure without an APK update:
- Combat formula version and mode modifiers.
- Auto-acquisition radius, target priority and retention grace period.
- Character base stats and derived-stat caps.
- Basic attack interval and weapon range profiles.
- Skill data, priority presets, cooldowns and resource costs.
- Element modifiers, status effects, boss immunities and control diminishing returns.
- Monster AI profiles, aggro, phases and telegraphs.
- PvE/PvP normalization and consumable restrictions.
- Death/revival and respawn rules.
- Combat content version, staged rollout and rollback.

Publishing flow: Draft → Validate → Preview/Staging → Review → Publish. Every published configuration has a version, effective timestamp, author/reviewer and audit log. Server validates all configuration references before activation.

## 14. Analytics, anti-cheat and operational monitoring

Record structured combat events sufficient for debugging and balancing:
- Attack/skill use, hit/miss, damage/heal, status application/removal.
- Target changes and invalid target attempts.
- Movement validation failures and suspicious speed/position changes.
- Death/revival, monster phase changes, encounter completion and reward grants.
- PvP match outcomes and rating updates.

Monitor:
- Server tick time, message rate, latency and disconnects.
- Combat event processing delay and AOI fan-out.
- Skill/character pick rates, win rates and damage/healing distribution.
- Death rates, boss clear times and progression bottlenecks.
- Suspicious attack rates, impossible cooldowns and repeated invalid commands.

Use rate limits, anomaly detection and review workflows. Do not automatically punish based only on one noisy signal.

## 15. Accessibility and child-safety considerations

- Provide readable target/HP/skill indicators and optional larger UI scaling.
- Provide reduced screen shake, flash and VFX intensity.
- Use clear visual and audio cues for boss telegraphs; do not rely on color alone.
- Auto Battle should reduce repetitive input but should not require purchases to be effective.
- Chat/social safety is governed by separate moderation, reporting and blocking systems.
- Avoid monetization that sells combat wins or gives academic advantages in StudyGo education.

## 16. Initial implementation milestones

### Milestone A — Offline combat prototype
- Side-scrolling test map.
- One controllable character, two enemy archetypes.
- Auto basic attack and hybrid target selection.
- One active skill, HP bars, damage feedback and death state.

### Milestone B — Server-authoritative PvE
- Real-time server entity state.
- Movement/attack validation, skill cooldowns and monster AI.
- Target switching, AOI replication and reconnect handling.
- Server-issued drops and rewards.

### Milestone C — Character and content integration
- Character stats, equipment, elements and status effects.
- Admin-published combat/skill/monster configuration.
- Content manifest and asset versioning.

### Milestone D — PvP and scale testing
- Friendly arena before ranked PvP.
- Mode normalization, match state and result integrity.
- Load testing, latency testing, abuse testing and balance analytics.

## 17. Acceptance criteria for the first playable combat build

- Character automatically attacks a valid enemy without repeated attack taps.
- Auto-target chooses only valid enemies inside configured range and encounter boundaries.
- Player can manually select another valid enemy; the target lock is visibly indicated.
- Invalid/dead/despawned targets are released and auto-target resumes.
- Side-view movement and attack positioning respect collision and lane constraints.
- Skill cooldowns and resource costs are enforced by the server.
- Client cannot forge damage, drops, currency or match outcomes.
- Combat remains understandable with reduced VFX and readable UI.
- Education data, AI quotas and education purchases remain isolated from game combat and economy.
