# StudyGo AI Backend + Flutter Education Client

PHP Native API for StudyGo education and shared account identity. MMORPG economy and academic data remain separate.

## Requirements
- PHP 8.1+ (8.3 recommended): PDO MySQL, cURL, OpenSSL, mbstring, fileinfo
- MySQL 8 / compatible MariaDB
- HTTPS in production; private writable upload directory outside the web root
- Flutter stable (Dart 3.3+) for the sample client

## Database setup
Apply in this order:
1. \`database/migrations/001_world_map.sql\`
2. \`database/schema.sql\` (creates \`game_players\`)
3. \`database/migrations/000_studygo_auth.sql\`
4. Game migrations \`002\` through \`005\` in numeric order.
5. Education/auth migrations \`006_studygo_education.sql\`, \`007_auth_security.sql\`, \`008_admob_admin.sql\`, \`009_education_platform.sql\`.

Run migrations once using a controlled deployment process. Migration 007 and 009 contain ALTER TABLE statements and are not repeatable on an already-migrated database.

Copy \`config/config.example.php\` to \`config/config.php\`; configure DB settings, AI keys, mail, and upload storage. Never commit production config or API keys. Point the web document root to \`Backend/public\`; keep \`src\`, \`config\`, migrations and uploads outside public web root.

Environment:
- \`DB_DSN\`, \`DB_USERNAME\`, \`DB_PASSWORD\`
- \`AI_PROVIDER=gemini|openai\`, \`AI_MODEL\`, \`GEMINI_API_KEY\` or \`OPENAI_API_KEY\`
- \`MAIL_FROM_ADDRESS\`, \`MAIL_FROM_NAME\`, \`MAIL_ACTION_URL\`
- \`AUTH_REQUIRE_EMAIL_VERIFICATION=1\` to block login until email verified (default off until mail delivery is configured)
- \`STUDYGO_UPLOAD_DIR\` private directory, \`STUDYGO_UPLOAD_MAX_BYTES\` is currently fixed in config at 50 MiB
- \`AD_REWARD_CALLBACK_SECRET\` for internal HMAC adapter
- \`GAME_JWT_SECRET\`, issuer/audience for MMORPG token issuance

The native PHP mail adapter uses \`mail()\`; the hosting account must have a working outbound mail transport. Configure an HTTPS frontend action URL that handles \`/verify-email?token=...\` and \`/reset-password?token=...\`. Never return raw verification/reset tokens from production APIs.

## API overview
All user routes require \`Authorization: Bearer <accessToken>\` unless explicitly marked public.

### Authentication
- \`POST /api/v1/auth/register\` — \`email,password,displayName\`; sends verification email when mail is configured.
- \`POST /api/v1/auth/login\` — \`email,password\`; returns access and refresh tokens.
- \`POST /api/v1/auth/refresh\` — \`refreshToken\`; rotates refresh token and preserves device session ID.
- \`POST /api/v1/auth/logout\` — refresh token in JSON and access token in Authorization header.
- \`GET /api/v1/auth/me\`
- \`POST /api/v1/auth/email/resend\` — \`email\`
- \`POST /api/v1/auth/email/verify\` — \`token\`
- \`POST /api/v1/auth/password/forgot\` — \`email\`; generic response avoids account enumeration.
- \`POST /api/v1/auth/password/reset\` — \`token,password\`; revokes all sessions.
- \`GET /api/v1/auth/sessions\`
- \`DELETE /api/v1/auth/sessions/{sessionId}\`

Login throttling: five failed attempts in the configured identity window causes a 15-minute lock. Email verification enforcement is configurable and defaults off until mail is configured.

### Education
- \`GET /api/v1/subjects\`
- \`GET|POST /api/v1/planner/tasks\`
- \`PATCH|DELETE /api/v1/planner/tasks/{id}\`
- \`GET|POST /api/v1/notes\`
- \`PATCH|DELETE /api/v1/notes/{id}\`
- \`GET|POST /api/v1/materials\` — multipart upload field \`file\`, optional \`title\` and \`subjectId\`. Supports PDF, DOCX, PPTX, MP4, WebM, JPEG, PNG, WebP. Files are stored outside the public web root.
- \`GET /api/v1/materials/{id}/download\` — owner-only authenticated download.
- \`GET|POST /api/v1/reminders\`
- \`GET /api/v1/notifications\`
- \`POST /api/v1/notifications/{id}/read\`
- \`GET /api/v1/ai/quota\`
- \`POST /api/v1/ai/tutor\` — \`question,requestId\` UUID.
- \`POST /api/v1/ai/solve-image\` — \`imageBase64,mimeType,question,requestId\` UUID; JPEG/PNG/WebP, max 8 MiB.
- AI quota: 5 free questions/day + 3 per verified reward ad, max 3 rewarded ads/day (14 questions/day).

### Reminder processing
Run \`php Backend/bin/process_reminders.php\` every minute using cPanel Cron Jobs. Due reminders become in-app notifications. Push notifications (FCM/APNs) are not yet wired; Flutter currently polls the authenticated notification endpoint.

### AdMob and admin
- \`GET /internal/ads/admob-ssv\` verifies Google's ECDSA/SHA-256 callback signature.
- \`GET|PUT /api/v1/admin/ads\` admin-only AdMob placement settings.
- \`GET /api/v1/admin/education/dashboard\` admin-only education overview.
- \`Backend/admin/ads.html\` and \`Backend/admin/education.html\` are starter admin pages; enter API URL and an admin bearer token.
- Add the first owner manually after account registration: \`INSERT INTO studygo_admin_users(user_id,admin_role) VALUES (USER_ID,'owner');\`.

AdMob callback URL: \`https://YOUR_API_HOST/internal/ads/admob-ssv\`. Configure Rewarded SSV in AdMob and ensure unit IDs/reward settings match admin values. Internal HMAC reward callback is not a substitute for Google's SSV.

## Flutter client
A starter Flutter application is in \`FlutterApp/\`.
1. Install Flutter stable.
2. \`cd FlutterApp && flutter pub get\`
3. Run: \`flutter run --dart-define=STUDYGO_API_URL=https://YOUR_API_HOST\`
4. Build: \`flutter build apk --dart-define=STUDYGO_API_URL=https://YOUR_API_HOST\`

The client includes secure token storage, session resume, refresh on 401, login, AI tutor, image question upload, planner tasks, study material upload and notification polling. It does not contain provider secrets. Configure Android network permissions and iOS transport settings if your platform templates require them; production must use HTTPS.

## Integration tests and CI
- \`Backend/tests/integration.php\` checks required MySQL tables and basic insert/foreign-key paths in a rollback transaction.
- GitHub Actions runs PHP syntax checks, .NET build, migration application against MySQL 8, and DB integration smoke tests.
- Flutter client has not yet been run on an Android emulator/device in this repository workflow. Run \`flutter analyze\`, \`flutter test\`, and an end-to-end login/API test before release.

## Production hardening still required
- Configure SMTP or a reliable cPanel mail transport and test email delivery; native \`mail()\` is a basic adapter, not authenticated SMTP.
- Add FCM/APNs device token registration and push delivery.
- Add admin CRUD for subjects/material moderation, roles UI, analytics and audit screens; current education dashboard is a summary.
- Add virus scanning, upload quotas, retention/deletion controls and PDF/DOCX/PPTX preview/transcoding.
- Add OCR/vision abuse controls, request limits, consent and image retention policy.
- Add global/IP rate limiting, monitoring, backups, restore drills and security review.
- Validate AdMob SSV with real AdMob test callbacks and review Google policy requirements.
- Do not treat GitHub Actions syntax/database smoke tests as proof of production deployment or Flutter device compatibility.
