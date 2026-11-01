# Guest-first StudyGo — Final Product Specification

## Product decision
StudyGo opens directly in Guest Mode. Account registration and login are optional, not the app's entry gate. Guest mode must not be presented as anonymous unlimited cloud access.

## Access modes

### Guest
- Create a random installation-scoped guest identity on first launch.
- Keep guest credential in Android secure storage; never use Android device ID as the credential.
- Allow onboarding, subject browsing, static learning content and local planner/notes without registration.
- AI Tutor and image solving may be offered with a server-enforced guest quota only after the backend guest-session endpoint and abuse controls are implemented.
- Keep guest data local until the user chooses to create/sign into an account.
- Clearly warn that uninstalling/clearing app data can remove local-only guest progress.

### Registered account
- Email/password registration and login remain available.
- Sync planner, notes, materials, notifications and progress to cloud.
- Account can use multiple devices and recover access.
- Existing email verification, password reset, refresh-token rotation and session revocation remain.

## Guest-to-account upgrade
- Guest identity is created server-side, not inferred from a client-supplied user ID.
- Guest session uses a random high-entropy bearer token stored hashed in the database.
- Guest-owned records must be transferred in a single database transaction after account authentication.
- Reject linking if guest data is already claimed or account policy disallows merge.
- Revoke guest tokens after successful claim; issue normal account tokens.
- Never merge wallet/purchases/paid entitlements without explicit server-side conflict rules and audit logging.

## Aetheria
- Guest can explore an offline/tutorial slice if the Unity client supports it.
- Online multiplayer, cloud character ownership, purchases, trading and leaderboard require an authenticated account unless a dedicated server-side guest identity and anti-abuse policy are implemented.
- GameServer validates all online actions server-side; client never decides damage, drops, balances or ownership.

## Backend work required before release
- Add guest session creation, expiry, rate limiting and revocation.
- Add guest identity columns/table and ownership mapping.
- Add a transactional claim/upgrade endpoint.
- Define guest AI quotas and abuse controls.
- Ensure every user-owned education endpoint scopes records to the authenticated principal.
- Add integration tests for guest isolation, expiry, claim, duplicate claim, quota enforcement and token revocation.

## Release gates
Guest-first UI is not complete merely by hiding the login page. Do not ship cloud AI or cross-device guest persistence until the server-issued guest identity and tests exist. Keep login/register reachable from Settings/Profile and from a save-progress prompt.
