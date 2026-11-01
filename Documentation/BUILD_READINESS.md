# Build Readiness and Deployment Guide

This repository contains a **backend/game-server foundation**, not yet a complete playable Unity MMORPG client.

## Automated validation

GitHub Actions runs on pushes and pull requests to `main`:

- .NET 8 restore and Release build for `GameServer/StudyGo.GameServer.csproj`
- PHP 8.3 syntax checks for files under `Backend/`
- Basic migration file/order/content checks

A green workflow proves compilation and syntax checks only. It does not prove database migrations, gameplay balance, load capacity, security review, or Android packaging.

## Required server configuration

Set these values in the deployment environment (never commit secrets):

- `ConnectionStrings__GameDatabase`: MySQL/MariaDB connection string
- `GameAuth__JwtSecret`: random secret with at least 32 bytes
- `GameAuth__Issuer`: exact issuer configured by StudyGo PHP backend
- `GameAuth__Audience`: exact audience configured by StudyGo PHP backend

Use HTTPS, a private database user with least privilege, network restrictions, backups, and centralized logs.

## Migration order

Run numbered SQL migrations in ascending order against a fresh staging database first. Confirm the base identity schema exists before applying migrations that reference `game_players(id)`. In particular, the StudyGo account mapping must provide the expected `studygo_user_id` column used by the GameServer identity repository. Do not assume this mapping exists until checked against the actual StudyGo backend schema.

Do not run migrations against production until a backup and rollback plan have been tested. MySQL and MariaDB versions differ in CHECK constraint and JSON behavior; test against the exact production engine/version.

## JWT issuer integration

`Backend/src/Security/GameJwtIssuer.php` is a reusable issuer, not an HTTP endpoint and not yet wired into an existing StudyGo login controller. The caller must:

1. Authenticate the StudyGo user using the existing login mechanism.
2. Verify that the user is allowed to enter the selected game server using authoritative server membership data.
3. Issue a short-lived token with the configured issuer/audience and `server_id`.
4. Return only the token and expiry to the authenticated client.

Never accept `studyGoUserId` or an authorized server ID supplied by the client as proof of identity. The GameServer must additionally verify server membership against its own authoritative data before allowing gameplay actions; a signed claim alone does not prove current membership or account status.

## Current implementation limits

- The WebSocket endpoint is a connectivity echo prototype, not an authenticated authoritative realtime game protocol.
- World-map reads still use demo/in-memory data; SQL spawn records are not yet connected to map reads.
- March APIs cover initial dispatch/list/recall/scout-report flows only. Combat resolution, PvP, rally, guild, trading, marketplace, and complete base-building APIs remain future work.
- The repository does not yet contain a complete Unity project or Flutter-to-Unity integration. Therefore this workflow does not produce an APK/AAB.
- Database integration, migrations, workers, and JWT flows require staging integration tests with the exact database schema and server configuration.

## Build locally

Install the .NET 8 SDK, then run:

```bash
dotnet restore GameServer/StudyGo.GameServer.csproj
dotnet build GameServer/StudyGo.GameServer.csproj --configuration Release
```

For PHP syntax checks:

```bash
find Backend -type f -name '*.php' -print0 | xargs -0 -n1 php -l
```

## Release gate

Do not label a release production-ready until CI is green and the team has completed database integration tests, authenticated account/server membership tests, API authorization tests, worker idempotency tests, load tests, security review, Unity Android build, and end-to-end Flutter/Unity/GameServer tests.
