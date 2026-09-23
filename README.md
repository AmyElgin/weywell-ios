# Weywell

Weywell is a community safety map for South Africa. It lets people view and submit short-lived local alerts about road disruptions, unsafe behaviour, crime reports and neighbourhood context. New community alerts are reviewed before they appear on the public map.

This is a student project and an active work in progress. It is not an emergency service, police case-reporting channel, or source of verified crime statistics. Do not use it to report an emergency. Reports can be wrong or out of date; use your judgement and official sources.

## Current status

- iOS app built with SwiftUI; minimum iOS version: 17.
- Supabase backs community notices, moderation, optional photos and saved alert watches.
- RevenueCat is integrated for the Plus subscription flow.
- Weywell is being developed for possible collaboration with local law enforcement. The app does not claim police endorsement or provide an official crime-reporting channel.
- Push delivery and production subscription credentials require separate setup. A successful simulator build does not mean the app is ready for public release.

## Build the iOS app

1. Install Xcode 16 or later.
2. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and add credentials for development Supabase and RevenueCat projects. This local file is ignored by Git.
3. Open `Weywell.xcodeproj`, select the Weywell target, choose your own Apple development team under Signing & Capabilities, then build for an iOS 17+ simulator or device.
4. Apply the SQL files in `supabase/` to a development Supabase project in this order: `schema.sql`, `moderation_schema.sql`, `photos_schema.sql`, then `push_schema.sql`. Read each setup guide before enabling the feature.

Without local credentials, the app still builds but shared backend and purchase features are not configured.

## Password reset page

The optional static reset page is in `password-reset-web/`. Copy `config.js.example` to `config.js`, fill in a development Supabase URL and publishable key, and host the directory over HTTPS. The configuration file is ignored by Git.

## Safety and moderation

The SQL schema puts submitted alerts into a pending moderation state and limits public reads to approved, unexpired notices. Moderation access is granted separately to designated accounts. Review the policies and configure the Supabase project before using real community data. Never put Supabase service-role keys, APNs private keys, or RevenueCat secret keys in the iOS app or this repository.

## Contributing

Issues and pull requests are welcome. Keep changes focused, explain user-facing safety effects, and never include real alert data, account credentials, private addresses, or production secrets in examples or screenshots.

## License

Released under the MIT License. See `LICENSE`.
