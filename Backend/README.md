# StudyGo AI Backend (PHP Native)

Initial backend foundation for shared StudyGo accounts and MMORPG authentication. This is a starting API, not yet the complete education platform.

## Requirements
- PHP 8.1+ (PHP 8.3 recommended), PDO MySQL, OpenSSL, JSON, mbstring
- MySQL 8 or a compatible MariaDB release
- HTTPS in production

## Setup
1. Create a database and a dedicated database user with least-privilege permissions.
2. Import migrations in order:
   - `database/migrations/001_world_map.sql`
   - `database/schema.sql` (creates `game_players`)
   - `database/migrations/000_studygo_auth.sql` (creates StudyGo accounts and server membership)
   - `database/migrations/006_studygo_education.sql`
   - `database/migrations/007_auth_security.sql` (login throttling and token metadata)\n   - `database/migrations/008_admob_admin.sql` (AdMob settings, admin roles, SSV event ledger)
   - Remaining game migrations in numeric order.
3. Copy `config/config.example.php` to `config/config.php`; set DB and JWT secrets through server environment variables. Do not commit `config.php`.
4. Point the web document root to `Backend/public`. If cPanel cannot set a document root, use a public front-controller directory and keep config/src/database outside public_html.
5. Set `GAME_JWT_SECRET` to a cryptographically random secret of at least 32 bytes. Use the same value in GameServer as `GameAuth__JwtSecret`. Set matching issuer/audience.

## Initial endpoints
- `GET /health`
- `POST /api/v1/auth/register` JSON: `email,password,displayName`
- `POST /api/v1/auth/login` JSON: `email,password` (5 failed attempts per email/IP pair triggers a 15-minute lock)
- `POST /api/v1/auth/refresh` JSON: `refreshToken` (rotates refresh token and issues a new access token)
- `POST /api/v1/auth/logout` JSON: `refreshToken`, plus current access token in Authorization header
- `GET /api/v1/auth/me` Authorization: Bearer access token
- `POST /api/v1/game/token` Authorization: Bearer access token, JSON: `serverId`

Registration creates a StudyGo account and a linked MMORPG player identity in one database transaction; it does not automatically create a game character or server membership. MMORPG token issuance is denied until a server membership exists. The game token is short-lived HS256 and is issued only after membership and server status are checked.

## Education API endpoints
All endpoints below except the internal reward callback require `Authorization: Bearer <accessToken>`.

- `GET /api/v1/subjects`
- `GET|POST /api/v1/planner/tasks`
- `PATCH|DELETE /api/v1/planner/tasks/{id}`
- `GET|POST /api/v1/notes`
- `PATCH|DELETE /api/v1/notes/{id}`
- `GET /api/v1/ai/quota`
- `POST /api/v1/ai/tutor` JSON: `question,requestId` (UUID)
- `POST /internal/ads/reward-callback` is an internal server-to-server HMAC adapter; it is not Google AdMob verification.\n- `GET /internal/ads/admob-ssv` verifies Google's ECDSA/SHA-256 signature using the public key selected by `key_id`.\n- `GET|PUT /api/v1/admin/ads` manages AdMob App IDs, Banner/Rewarded/Interstitial unit IDs, reward settings, and SSV enablement for admin accounts.

AI quota: 5 questions/day + 3 per verified reward callback, maximum 3 rewarded ads/day (14 questions total). Daily reset uses Asia/Jakarta. AI provider keys remain server-side. The reward callback is a signed internal adapter; Google AdMob SSV must be enabled only after migration 008, admin configuration, and the callback URL are in place.

## Important limitations before production
- Add global/IP rate limiting beyond login throttling, email verification, password reset, session listing/revocation UI, and abuse monitoring. Admin AdMob settings UI is at `admin/ads.html` and requires an admin bearer token; seed the first owner in `studygo_admin_users` as documented in `Documentation/ADMOB_SSV_ADMIN_SETUP.md`. Refresh-token rotation and logout endpoints are implemented, but need integration tests.
- Configure CORS with exact app/web origins. Native Flutter clients do not need permissive wildcard CORS.
- Add server onboarding/membership workflow and admin tools.
- Implement remaining education modules: materials and secure uploads, image-question recognition, reminders/notifications, verified AdMob SSV adapter, and admin dashboard.
- Review login token storage and threat model before release. Opaque random bearer tokens are stored as SHA-256 hashes; access tokens last 15 minutes and refresh tokens rotate on use. This is not a full OAuth/OIDC implementation.
- Do not return provider API keys to the Flutter client.
