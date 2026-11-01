# StudyGo Backend — cPanel Deployment

Target API: https://api.studygo.turaja.id
Document root: the uploaded `Backend/public` directory (recommended)
Runtime: PHP 8.1+; PHP 8.3 recommended

## 1. Confirm hosting capabilities

In cPanel open **Software → MultiPHP Manager** and select PHP 8.3 for the API subdomain if available. In **Select PHP Version / Extensions**, enable:
- pdo_mysql
- curl
- mbstring
- openssl
- fileinfo
- json
- sodium (recommended, if available)

If PHP 8.3 is unavailable, use the newest supported version >= 8.1 and run CI/smoke tests before production.

## 2. Create the subdomain

Create `api.studygo.turaja.id` in **Domains → Create A New Domain** (or Subdomains on older cPanel). Set its document root to a dedicated directory, e.g. `/home/CPANEL_USER/api.studygo.turaja.id`.

Recommended layout:
```
/home/CPANEL_USER/
  studygo-backend/             # full Backend/ folder; outside the web root
    src/
    config/
    database/
    bin/
    var/private-uploads/
    public/                    # set this as the subdomain document root
      .htaccess
      index.php
      health.php
```
Do not expose `src`, `config`, `database`, `bin`, or private uploads through the web.

## 3. Upload backend

Download the repository ZIP from GitHub and extract it locally. Upload the entire `Backend/` folder as `/home/CPANEL_USER/studygo-backend/`. In cPanel **Domains**, set the document root of `api.studygo.turaja.id` to:

```
/home/CPANEL_USER/studygo-backend/public
```

This layout is intentional: the web server exposes only `public/`, while `src/`, `config/`, `database/`, `bin/`, and private uploads remain outside the document root. Keep the existing `public/index.php` unchanged; its `../src/bootstrap.php` path will resolve correctly. If cPanel does not allow changing the document root to this location, stop and share the current document-root path before uploading; do not copy private source files into a public directory.

Copy `studygo-backend/config/config.example.php` to `studygo-backend/config/config.php`. Edit the PHP array values directly; do not upload production secrets to GitHub.

## 4. Create MySQL database and user

In **MySQL Database Wizard**:
1. Create database (example: `studygo`).
2. Create a database user with a strong unique password.
3. Grant only required privileges to this database (during migration: CREATE, ALTER, INDEX, INSERT, UPDATE, DELETE, SELECT; after migration, privileges can be reduced if your deployment process supports it).
4. Record the cPanel-prefixed database name and username exactly.

Set the config values:
- DSN: `mysql:host=localhost;dbname=CPANELPREFIX_studygo;charset=utf8mb4`
- username: `CPANELPREFIX_dbuser`
- password: the database password

Use the host name shown by cPanel if it is not `localhost`.

## 5. Apply database migrations

Use phpMyAdmin and select the newly created empty database. Import in this exact order:
1. `Backend/database/migrations/001_world_map.sql`
2. `Backend/database/schema.sql`
3. `Backend/database/migrations/000_studygo_auth.sql`
4. `002_player_castles.sql`
5. `003_resource_monster_spawns.sql`
6. `004_march_system.sql`
7. `005_march_settlement_recall.sql`
8. `006_studygo_education.sql`
9. `007_auth_security.sql`
10. `008_admob_admin.sql`
11. `009_education_platform.sql`

Important: use a fresh database. Migrations 007 and 009 contain ALTER TABLE statements and are not safe to import twice. If an import fails, stop and inspect the database before retrying; do not blindly re-import from the beginning.

## 6. Configure secrets and services

In private `config/config.php`, set:
- app.env = production; app.debug = false
- database.dsn / username / password
- ai.provider = gemini (or openai), ai.model and the matching API key
- mail.from_address, mail.from_name and mail.action_url
- uploads.directory to a private writable path outside document root
- game_jwt.secret to a random secret of at least 32 bytes; issuer = `https://api.studygo.turaja.id`; audience = `studygo-mmorpg`
- ads.callback_secret to a long random value

Generate random secrets locally, for example with PHP:
```php
echo bin2hex(random_bytes(32)), PHP_EOL;
```
Never paste secrets into chat or commit them. Ensure the upload directory exists and is writable by the PHP account (normally 0750/0755 depending on host).

## 7. HTTPS and health check

Enable AutoSSL/Let's Encrypt for `api.studygo.turaja.id`. Force HTTPS in cPanel or the public .htaccess after the certificate is active.

Check:
- `https://api.studygo.turaja.id/health`
- `https://api.studygo.turaja.id/api/v1/auth/me` should return HTTP 401 without a token (expected).
- Unknown routes should return JSON 404.

Do not expose phpinfo() publicly. Remove temporary installer/test files.

## 8. Cron job

Create a cPanel Cron Job to run every minute:
```bash
/usr/local/bin/php /home/CPANEL_USER/studygo-backend/bin/process_reminders.php
```
Use the PHP binary path shown by your hosting provider and replace CPANEL_USER with the actual cPanel username.

## 9. Final smoke tests

Before production traffic:
- confirm HTTPS and health endpoint
- register a test account and verify email delivery
- login, refresh, logout and password reset
- test AI quota and one AI question
- create task, upload/download a test material, create reminder and verify notification
- check PHP error log and MySQL slow/error logs
- test backup and restore on a separate database

## cPanel limitations

Shared hosting is suitable for the PHP REST API and MySQL. It is not a suitable place to host the always-on .NET MMORPG realtime server or Redis unless the provider explicitly supports persistent .NET processes, WebSockets and Redis. Keep GameServer on a VPS or managed service.

## Deployment checklist

- [ ] PHP version and extensions confirmed
- [ ] API subdomain points to hosting and document root is isolated
- [ ] Database and least-privilege user created
- [ ] Migrations imported once in order
- [ ] Private config and AI/mail/game secrets configured
- [ ] Private upload directory writable and outside web root
- [ ] HTTPS active
- [ ] Cron configured
- [ ] Health and API smoke tests passed
- [ ] Backup/restore tested
