# Mission Settlement & Recall

This phase adds transactional mission resolution and automatic return for `gather`, `hunt`, and `scout`. PvP `attack` remains disabled.

## Migration

Apply after migrations 001–004:

```sh
mysql -u USER -p DATABASE < Backend/database/migrations/005_march_settlement_recall.sql
```

Adds settlement fields to `player_marches`, plus:
- `march_settlements`: one settlement record per march (unique march ID).
- `march_scout_reports`: target snapshot visible to the owning player through a future authenticated API.

## Mission behavior

- Gather: capacity is the sum of assigned troop quantities × each troop's `carry_capacity`. Gather amount is limited by both carry capacity and remaining node capacity. The resource code is read from spawn template/object JSON `resourceCode`; default is `wood`. When capacity reaches zero, the node becomes depleted and uses its configured respawn timer.
- Hunt: provisional combat power uses troop-type coefficients (infantry 10, archer 12, cavalry 14, mage 16, support 5, siege 18 per troop). It reduces monster HP stored in `world_map_objects.remaining_capacity`. If HP reaches zero, configured `drops` from JSON are granted and the monster is scheduled to respawn. This is a basic placeholder, not the final character/troop combat formula.
- Scout: saves a 24-hour report snapshot in `march_scout_reports`.
- Return: after settlement, the march becomes `returning`. The return duration currently equals the outbound travel duration. Once due, reserved troops are released and the march becomes `returned`.
- Recall: owner may recall a `traveling` or `arrived` march. A traveling march returns using elapsed outbound time as a symmetric approximation; an arrived march uses the full outbound duration. Recall does not grant mission rewards.

## Spawn content JSON examples

Resource template/object data:
```json
{"resourceCode":"wood"}
```

Monster template/object data:
```json
{"drops":[{"resourceCode":"monster_core","min":1,"max":3},{"resourceCode":"gold_ore","min":2,"max":5}]}
```

## Operational safeguards

- Settlement and resource grants run in one database transaction.
- Unique `march_settlements.march_id` prevents duplicate settlement records.
- March state is locked before settlement; only `arrived` can be settled.
- Recall is scoped to owner + server and only allowed for `traveling` or `arrived`.
- Troop reservation is released only after the return timer completes.
- Content JSON is validated before granting resource codes.
- Do not expose these repository methods through public endpoints until StudyGo authentication middleware resolves the player ID and server assignment from trusted session claims.

## Remaining work

- Authenticated endpoints for march list/detail, recall, and scout report access.
- Actual PvE battle engine, troop/character stats, casualties, healing and battle reports.
- Admin-managed drop tables, carry capacity, combat coefficients and resource catalogue.
- True position-based recall travel, march speed modifiers, march slots and safe-zone rules.
- Integration/concurrency tests against target MySQL/MariaDB version.
- Add expiry cleanup for scout reports and operational monitoring.
