# Architecture

## Product boundary
StudyGo AI education and Aetheria gameplay are separate product domains. Game purchases, currency, character ownership and progression must never grant academic advantages or block access to education tools.

## Client
Flutter owns the StudyGo shell, login and education modules. Unity owns game rendering, 2D movement/combat presentation and 3D character/equipment preview. Evaluate Unity as a Library versus a separate game app with Android lifecycle, memory and package-size tests before committing to one integration.

## Backend domains
PHP API owns account linking, game profile, character catalogue, owned characters, inventory, wallet, purchase verification, trading, moderation and admin operations. Keep all privileged operations server-side.

## Realtime
A dedicated authoritative server owns movement validation, combat resolution, instance state and PvP outcomes. Clients send intents; they do not decide authoritative damage, drops or rewards. WebSocket is a candidate transport.

## Scaling
Use multiple world instances/shards rather than one enormous simulation process. Apply Area of Interest (AOI) filtering so clients receive nearby entities only. Initial capacity targets must be load-tested: town 100–200, field 50–100, dungeon 4–10, raid 10–40 concurrent players.

## Data
MySQL/MariaDB stores persistent accounts, characters, inventory and transactions. Redis is for ephemeral presence, cache, queues and coordination. Store large game assets in object storage/CDN.

## Character commerce
Players must obtain a character before entering gameplay. Allow catalogue browsing and 3D preview before purchase. Verify Google Play purchases server-side. Use atomic ownership changes and audit logs for transfers and marketplace operations.

## Safety
Provide report, block, chat moderation and age-appropriate social defaults. Avoid paid random loot boxes and pay-to-win sales. Add parental purchase controls where appropriate.
