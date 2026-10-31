# Character Admin & Asset Publishing

## Decision
All playable characters are managed through the Admin Dashboard. Character data and assets are delivered to the game client through authenticated APIs and asset storage/CDN. Adding or updating a character must not require a new Flutter or Unity app release.

## Admin workflow
1. **Draft** — admin creates a character record and uploads its assets.
2. **Review** — validate files, preview the model/sprites, check animation bindings, stats, skills, equipment compatibility and shop configuration.
3. **Published** — character appears in the player catalogue and can be previewed and purchased.
4. **Archived** — character is hidden from new purchases while existing owners retain access unless a separately reviewed policy says otherwise.

Only authorized admin roles can create, edit, review or publish characters. Record who made each change and when.

## Asset types
- 3D preview model: GLB/glTF (validate importer compatibility and extensions).
- 2D gameplay sprites: PNG or WebP, with defined sprite-sheet metadata.
- Character portrait and catalogue icon: PNG or WebP.
- Animations: preferably packaged with the model or referenced through versioned asset bundles.
- Optional VFX/audio assets: versioned and delivered through CDN/object storage.

Store files in private or controlled object storage; expose only approved, versioned public delivery URLs. Do not store large binary assets in MySQL or commit production assets to the application source repository.

## Character metadata
Each character should include a stable code/ID, localized name and description, element, role, rarity, base stats, level growth rules, active/passive skills, equipment compatibility, asset manifest/version, shop price/currency, publication status and timestamps.

Rarity values: Common, Rare, Epic, Legendary, Mythic. Rarity is a collection tier and must not by itself make lower-rarity characters unusable.

## API responsibilities
- Admin endpoints: create/update draft, upload asset, validate asset, submit for review, approve, publish, archive.
- Player endpoints: list published catalogue, fetch character details, fetch preview manifest, inspect owned characters, purchase through a server-authoritative transaction.
- Never trust client-submitted price, stats, ownership, currency balance or purchase result.
- Verify store receipts server-side for real-money purchases.

## Upload security
Allowlist file formats and MIME types; verify actual file signatures; impose size and dimension limits; generate storage keys server-side; scan uploads; reject executable/script files; prevent path traversal; use short-lived upload credentials; and keep admin actions in an audit log.

## Player experience
Players can browse the character catalogue and inspect a 3D preview before purchase. The game requires at least one owned character before entering gameplay. StudyGo education features remain accessible regardless of character purchases.

## Initial admin screens
1. Character list with search, filters and status.
2. Character editor for metadata, stats, skills and equipment.
3. Asset manager with upload progress and validation feedback.
4. 3D/2D preview and animation checks.
5. Shop pricing and availability.
6. Review queue, publish/archive actions and audit history.

## Delivery strategy
The API returns metadata and versioned asset references. The Unity client downloads and caches assets; it does not contain a hardcoded catalogue. Use CDN/object storage for production assets and retain previous asset versions to support rollback.
