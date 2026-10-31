# Aetheria — Game Economy, Item & Equipment Standard

## 1. Core progression limits (launch baseline)

| System | Launch cap |
|---|---:|
| Character level | 100 |
| Equipment enhancement | +20 |
| Active skill level | 10 |
| Passive skill level | 10 |
| Character evolution | 5 stages |
| Equipment rarity | Common, Rare, Epic, Legendary, Mythic |
| Character rarity | Common, Rare, Epic, Legendary, Mythic |

- Level 100 is the initial maximum character level.
- Excess EXP is retained as overflow EXP and does not raise the level beyond the active cap.
- Admins may release a new progression content version that raises the cap, for example from 100 to 120. A cap increase must be announced and must not silently invalidate existing character or item data.
- Skill level and equipment enhancement are separate from character level.
- Rarity is a collection and item identity tier, not an automatic guarantee that a character is unbeatable. Lower-rarity characters must remain viable.
- Character evolution has five stages: Awakened, Ascendant, Exalted, Transcendent, and Eternal.

## 2. Naming and ID conventions

Use short, memorable fantasy names that are easy to pronounce in Indonesian and recognizable in the Aetheria setting.

- Display names may be localized or revised by admins.
- Every item, equipment, resource, character and bundle must have a permanent machine ID, for example res_aether_shard or eq_weapon_bara_edge.
- Never use a display name as a database primary key.
- Do not reuse retired IDs. If an item is reintroduced, restore its original ID only when it is the same item; otherwise create a new ID.
- Each content release must have a version, release date, changelog and rollback reference.
- Admin uploads should support draft → validation → review → publish. Published content is immutable; edits create a new version.
- Assets (sprites, icons, 3D models, textures, animations) are uploaded separately and linked to item IDs. Replacing an asset creates a new asset version while preserving item identity.

## 3. Equipment slots

Every character uses seven equipment slots: Weapon, Helmet, Armor, Gloves, Boots, Ring and Amulet.

### Starter equipment catalogue

| Slot | Equipment name | Permanent ID |
|---|---|---|
| Weapon | Bara Edge | eq_weapon_bara_edge |
| Weapon | Nila Bow | eq_weapon_nila_bow |
| Weapon | Guntur Maul | eq_weapon_guntur_maul |
| Weapon | Arunika Staff | eq_weapon_arunika_staff |
| Weapon | Rimba Daggers | eq_weapon_rimba_daggers |
| Helmet | Aegis Crown | eq_helmet_aegis_crown |
| Armor | Niskala Guard | eq_armor_niskala_guard |
| Gloves | Bara Grip | eq_gloves_bara_grip |
| Boots | Bayu Striders | eq_boots_bayu_striders |
| Ring | Aether Loop | eq_ring_aether_loop |
| Amulet | Sagara Heart | eq_amulet_sagara_heart |

Weapon types are archetypes; class/character compatibility is configured per item. Not every character can equip every weapon.

## 4. Upgrade and crafting resources

| Name | Permanent ID | Main use |
|---|---|---|
| Aether Shard | res_aether_shard | General equipment enhancement |
| Bara Core | res_bara_core | ATK enhancement |
| Niskala Plate | res_niskala_plate | DEF enhancement |
| Tirta Heart | res_tirta_heart | HP enhancement |
| Bayu Feather | res_bayu_feather | SPD enhancement |
| Aegis Fragment | res_aegis_fragment | Shield enhancement |
| Skill Rune | res_skill_rune | Skill level-up |
| Awaken Stone | res_awaken_stone | Character evolution |
| Mythic Seal | res_mythic_seal | High-rarity evolution/crafting |
| Star Dust | res_star_dust | Special crafting and event recipes |

Resources are obtained from monster drops, exploration, quests, dungeons, raids, events, crafting and (where appropriate) direct store purchases. Admins configure drop rates and purchase limits. Essential progression materials should not be exclusively purchasable.

## 5. Consumable items

Initial consumable families:
- Vita Potion — restores HP.
- Aegis Potion — temporary shield.
- Ember Tonic — temporary ATK boost.
- Gale Tonic — temporary SPD boost.
- Return Sigil — returns the player to a designated safe hub when permitted.
- Revival Feather — revive in eligible PvE content only; disabled where competitive fairness requires it.

Each consumable requires a permanent ID, stack limit, duration/effect, eligible modes, cooldown and acquisition sources. Consumables must not create unfair advantages in ranked PvP.

## 6. Currency

Keep the game economy separate from StudyGo education features and academic records.

- Gold: normal gameplay currency for common crafting, upgrades and selected store items.
- Gems: premium game currency, purchased through verified in-app purchases and any explicitly configured rewards.
- Event Token: limited to a named event and its reward shop.
- EXP: progression value, not spendable currency.
- Materials: inventory items, not currency balances.

No game currency or item may be used to buy AI questions, grades, school services or academic advantages.

## 7. Game Store catalogue categories

1. Characters
2. Resources
3. Equipment
4. Bundles (character + resources + equipment)
5. Cosmetics (skins, weapon appearances, effects and animations)
6. Convenience (for example, extra character slots, subject to balance review)
7. Server Transfer Ticket (product ID: server_transfer_ticket)

Store products must have stable product IDs, clear prices, regional availability, purchase limits, start/end dates and receipt verification. Avoid paid random loot boxes, especially for a young audience.

## 8. Admin content upload and versioning

Admin Dashboard must let authorized staff add or update content without requiring a new Android app release.

Manageable content:
- Characters and character stats/skills/evolution
- Equipment and slot compatibility
- Resources and crafting recipes
- Consumables and effects
- Monster drops and loot tables
- Upgrade costs and success rules
- Store products and bundles
- Currency configuration and event tokens
- Icons, 2D sprites, portraits, 3D GLB/GLTF models, textures and animations
- Level cap and progression curves

Publishing workflow:
1. Upload a content package with a semantic version (for example 1.1.0).
2. Validate file types, sizes, hashes, IDs, references and required metadata.
3. Preview assets and stats in a staging environment.
4. Review and approve using a separate permission.
5. Publish with a changelog and effective timestamp.
6. Keep the previous version available for rollback.

Clients fetch a signed/validated content manifest and download assets from CDN. Server gameplay logic remains authoritative for stats, drops, prices, upgrade outcomes and inventory transactions. Never trust client-supplied item stats or purchase results.

## 9. Required data fields

Each catalogue item should include:
- Permanent ID, display name, description, category and rarity
- Content version and status (draft/review/published/archived)
- Icon and optional sprite/model/animation asset references
- Level requirement and eligible character/class restrictions
- Stats/effects, stack limit, sell/trade rules and acquisition sources
- Store price and purchase limits (when sold)
- Effective date, creator/reviewer and audit history

Equipment additionally needs slot, base stats, enhancement cap, optional set ID and compatible character tags. Resources additionally need usage recipes and source/drop configuration. Consumables additionally need effect duration, cooldown and allowed game modes.

## 10. Balance and safety rules

- Use PvP normalization or mode-specific balancing where necessary.
- No paid item should be an unconditional win button.
- All inventory, currency, drops, crafting and purchases are server-authoritative and transaction-safe.
- Use purchase verification, rate limits, audit logs and anti-duplication controls.
- Keep game purchases, wallets, progression and inventory completely separate from StudyGo education data.
