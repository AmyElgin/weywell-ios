# Background push setup

The iOS app, private database tables, and `push-notice` function source are
prepared. Anonymous Supabase sign-in is enabled and the private tables have
been applied. Remote delivery is not live until the following one-time setup
is completed and tested.

## Apple and RevenueCat credentials

1. In the Apple Developer account that owns `com.weywell.app`, enable Push
   Notifications for the App ID and create an APNs Auth Key. Keep the `.p8`
   private key private. Record its Key ID and the Apple Team ID.
2. Create a RevenueCat secret API key with subscriber read access. Never use
   the public iOS SDK key for server verification.
3. Deploy `functions/push-notice` using the Supabase CLI from this directory.
   The included `config.toml` disables Supabase JWT validation because the
   database webhook authenticates with its own secret header instead.
4. Set these Edge Function secrets in Supabase:
   - `WEYWELL_WEBHOOK_SECRET`: a new random value, at least 32 bytes.
   - `REVENUECAT_SECRET_KEY`: the RevenueCat secret API key.
   - `APNS_PRIVATE_KEY`: the full `.p8` PEM contents.
   - `APNS_KEY_ID`: the APNs Auth Key ID.
   - `APPLE_TEAM_ID`: the Apple Developer Team ID.
   - `APPLE_BUNDLE_ID`: `com.weywell.app`.
   Supabase provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to the
   deployed function automatically; do not add either to the iOS app.
5. Create a Supabase Database Webhook for `public.safety_notices` UPDATE
   events, targeting the deployed `push-notice` function. Add the header
   `x-weywell-webhook-secret` with the same `WEYWELL_WEBHOOK_SECRET` value.
6. Sign the app with the Apple team and run on a physical iPhone. Grant push
   permission, create an active Plus entitlement and a saved watch, then
   approve an in-range test notice. Verify one alert while the app is closed,
   no alert for an out-of-range notice, and no duplicate on a second webhook.
7. After that test succeeds, set `PushDeliveryReady` to `true` in `Info.plist`
   to remove the in-app setup message and stop the local-notification fallback.

The current debug build requests the APNs sandbox; the release build requests
the production APNs environment. The matching device-token environment is
stored with each device and selects the corresponding Apple endpoint.
