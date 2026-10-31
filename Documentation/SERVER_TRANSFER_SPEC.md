# Server Lock & Server Transfer

## Product rule
A game account is bound to its selected home server. Players cannot freely switch servers. To move, the player must obtain and consume a dedicated **Server Transfer Ticket** sold in the in-game Game Store.

## Server selection and binding
- Show server status, region, population and maintenance state before the first selection.
- Confirm the choice clearly; after binding, the selected server becomes the account's home server.
- Do not silently move players between servers. Any exceptional operational migration must be announced and logged by administrators.
- Character catalogue browsing and education features remain available independently of the selected game server.

## Transfer ticket
- Product code suggestion: `server_transfer_ticket`.
- Sell as a direct, clearly priced item (Gold or Gems policy must be configured deliberately; do not make it a random reward).
- Ticket is consumed only after the server validates the transfer request and reserves capacity on the destination.
- Display destination, included data, exclusions, cooldown and irreversible-operation warning before final confirmation.
- A ticket is not a guarantee that every destination is eligible or has capacity.

## Recommended initial eligibility rules
1. Destination must be online, accepting transfers and in the same region.
2. Destination must have sufficient character/account capacity.
3. Player must be logged out of active gameplay and in a safe state.
4. No active dungeon/raid, PvP match, party activity or combat.
5. No pending marketplace listings, trades, mail claims, store deliveries or unsettled purchases.
6. Guild membership/leadership and guild applications must be resolved before transfer; guild membership does not automatically migrate in the first version.
7. No active account restriction, fraud review or transfer lock.
8. Apply an initial cooldown of 30 days after a successful transfer. This is a proposed starting value and should be configurable by admins.

## Data migration policy
Transfer the player's game profile and eligible progression as one controlled operation:
- Characters, levels, EXP, skills and character progression.
- Equipment, inventory, resource materials and eligible currencies.
- Quest progress, achievements and eligible account progression.

Do not automatically migrate server-specific rankings, active matches, pending market orders, guild state, server event placements or unclaimed deliveries. Define and show exclusions before confirmation. Education data and StudyGo AI account records are never part of game-server migration.

## Transaction safety
- Server is authoritative; clients cannot set the destination or mark a ticket as consumed.
- Create a transfer request with an idempotency key and a durable audit record.
- Lock the source account during migration; reserve destination capacity.
- Use a transactional/queued migration workflow with validation, checksums and retry/reconciliation handling.
- Consume the ticket only when the transfer reaches the committed state; on failure, release locks/reservations and restore ticket availability.
- Prevent simultaneous login on source and destination during migration.
- Log actor, source, destination, ticket transaction, timestamps, result and failure reason.

## Admin controls
Admin Dashboard should provide server status/capacity, transfer enable/disable, allowed source/destination pairs, cooldown, eligibility policy, transfer queue, failed jobs, audit history and manual support review. Admin-initiated migration must be separately permissioned and audited.

## Player flow
1. Open Game Store and acquire Server Transfer Ticket.
2. Open Server Transfer screen and review eligible destination servers.
3. See a checklist of conditions and exact data that will/won't move.
4. Confirm the irreversible transfer.
5. Game locks the account, migrates data, consumes the ticket after success and reconnects the player to the destination.

## Rollout
Start with same-region transfers only. Test with staging servers, simulated failures, duplicate requests and full destinations before enabling in production. Keep the ticket price and cooldown configurable rather than hardcoding them.
