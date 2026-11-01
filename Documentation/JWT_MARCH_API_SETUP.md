# JWT and March API Setup

The GameServer exposes player march routes only when JWT validation is configured. The access token must be issued by the trusted StudyGo account backend after normal StudyGo login. Never generate a trusted token in Flutter or Unity.

## Configuration

Set these values in the GameServer environment or secret manager (not in Git):

- `ConnectionStrings__GameDatabase`: MySQL/MariaDB connection string.
- `GameAuth__JwtSecret`: random HS256 secret, at least 32 UTF-8 bytes.
- `GameAuth__Issuer`: exact token issuer configured by StudyGo.
- `GameAuth__Audience`: exact audience configured for this GameServer.

Use HTTPS only. Do not place the JWT secret in Unity, Flutter, a public config file, or a committed appsettings file.

## Required JWT claims

The StudyGo backend must issue a signed HS256 access token with:
- `sub`: numeric StudyGo user ID.
- `server_id`: server selected by the account, after server-membership validation.
- `iss`: configured issuer.
- `aud`: configured audience.
- `iat`, `nbf`, `exp`: issued-at, not-before and expiry timestamps.

The GameServer validates signature, algorithm, issuer, audience and lifetime. It resolves `sub` to the internal game player ID through `game_players.studygo_user_id`. Player ID and server ID are never accepted from the request body.

Important: the account backend must verify that the user is entitled to the claimed server before issuing the token. If server selection changes, issue a new token. For higher assurance, also compare the claim with the authoritative active-server binding in the account database before processing game actions.

## Routes

All routes require `Authorization: Bearer <StudyGo access token>`.

- `POST /api/game/marches`: send troops. JSON fields: `requestId`, `destinationObjectId`, `missionType` (gather/hunt/scout), `troops` array of `troopCode` and `quantity`.
- `GET /api/game/marches?includeReturned=false`: list the authenticated player's marches on the token server.
- `POST /api/game/marches/{marchId}/recall`: recall an owned traveling or arrived march.
- `GET /api/game/marches/{marchId}/scout-report`: read an owned, unexpired scout report.

Attack remains unavailable until authoritative PvP resolution is implemented.

## Example request

```http
POST /api/game/marches
Authorization: Bearer <access-token>
Content-Type: application/json
```

```json
{
  "requestId": "march-client-unique-001",
  "destinationObjectId": "resource-node-001",
  "missionType": "gather",
  "troops": [
    { "troopCode": "guard_infantry", "quantity": 20 }
  ]
}
```

## Before production

1. Confirm the real StudyGo JWT issuer, audience, signing algorithm and claim names.
2. Ensure the StudyGo backend issues the same HS256 secret only to trusted server environments.
3. Add server membership/active-server binding validation.
4. Configure HTTPS, rate limits, request size limits and structured error handling.
5. Add automated tests for invalid/expired tokens, cross-player access, cross-server access, duplicate request IDs, concurrent troop reservations and recall races.
6. Run migrations 001–005 in order and verify the database schema against the deployed MySQL/MariaDB version.
7. Build and run integration tests in a .NET 8 environment before deployment.

The API is disabled unless database and JWT configuration are present. Never enable it with placeholder secrets.
