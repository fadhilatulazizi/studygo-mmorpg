# AdMob SSV and Admin Ads Configuration

## Google SSV endpoint
Set the rewarded ad unit's server-side verification callback URL to:
https://YOUR_API_HOST/internal/ads/admob-ssv

Google calls this endpoint with a GET query string. The backend verifies the exact original query bytes with the ECDSA public key selected by key_id, fetched from Google's AdMob verifier-key endpoint. Keys are cached for 23 hours and refreshed when an unknown key ID is received.

Required callback fields: ad_unit, reward_amount, reward_item, timestamp, transaction_id, and user_id. Configure the Flutter rewarded ad with the authenticated StudyGo user ID as its SSV user identifier. Never treat a client-side reward callback as proof of reward.

## Admin setup
1. Apply migration 008_admob_admin.sql.
2. Add the owner/admin account after creating its StudyGo account:
   INSERT INTO studygo_admin_users(user_id,admin_role) VALUES (YOUR_USER_ID,'owner');
3. Configure Android/iOS AdMob App IDs and Banner, Rewarded, Interstitial Ad Unit IDs in studygo_admin_settings.
4. Set ads.admob_ssv_enabled=1 only after the callback URL and rewarded unit are configured.

The settings table is the persistence layer for the education admin dashboard. The browser admin API/UI still needs to be wired before admins can edit these fields in a dashboard. Do not expose this table or database credentials to Flutter.

## Security
- ECDSA/SHA-256 verification uses OpenSSL and the original signed query bytes.
- Google recommends caching keys for no longer than 24 hours.
- transaction_id has a unique constraint to prevent replay.
- Keep the internal HMAC callback only for trusted server-to-server integrations; it is not proof of AdMob origin.
- Enable PHP cURL and OpenSSL and require HTTPS.
