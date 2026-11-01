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
   - Remaining game migrations in numeric order.
3. Copy `config/config.example.php` to `config/config.php`; set DB and JWT secrets through server environment variables. Do not commit `config.php`.
4. Point the web document root to `Backend/public`. If cPanel cannot set a document root, use a public front-controller directory and keep config/src/database outside public_html.
5. Set `GAME_JWT_SECRET` to a cryptographically random secret of at least 32 bytes. Use the same value in GameServer as `GameAuth__JwtSecret`. Set matching issuer/audience.

## Initial endpoints
- `GET /health`
- `POST /api/v1/auth/register` JSON: `email,password,displayName`
- `POST /api/v1/auth/login` JSON: `email,password`
- `GET /api/v1/auth/me` Authorization: Bearer access token
- `POST /api/v1/game/token` Authorization: Bearer access token, JSON: `serverId`

Registration currently creates an account only; it does not automatically create a game character or server membership. MMORPG token issuance is denied until a server membership exists. The game token is short-lived HS256 and is issued only after membership and server status are checked.

## Important limitations before production
- Add rate limiting, email verification, password reset, refresh-token rotation/revocation endpoint, device/session management and abuse monitoring.
- Configure CORS with exact app/web origins. Native Flutter clients do not need permissive wildcard CORS.
- Add server onboarding/membership workflow and admin tools.
- Implement education APIs, AI provider proxy, quotas, planner, subjects, materials, notes, reminders, AdMob reward verification and admin dashboard.
- Review login token storage and threat model before release. This initial API uses opaque random bearer tokens stored hashed in the refresh-token table; it is not a full OAuth implementation.
- Do not return provider API keys to the Flutter client.
