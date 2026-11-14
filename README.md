# StreamBox (tvOS)

An Apple TV app that:

- browses movies and shows (metadata from TMDB);
- finds streams through **your own** Stremio-compatible addons (direct links only);
- plays live TV from **your own** Xtream Codes IPTV login.

The app ships with no content and no sources. Everything is supplied by the user in Settings and stored in the Keychain.

## Layout

```
project.yml                  XcodeGen spec (the .xcodeproj is generated on CI)
Sources/
  StreamBoxApp.swift         App entry + tab bar
  Core/                      Keychain, settings, helpers
  Services/                  TMDB, Stremio addon, Xtream, sports and TV guide search
  Player/                    AetherEngine holder + subtitle overlay
  Views/                     Home/Search, Detail + stream picker, Live TV, Settings, Player
.github/workflows/build.yml  CI: unsigned build (free) + optional TestFlight upload
```

## Requirements

- tvOS 18+ on the Apple TV
- Xcode 27 to build (AetherEngine needs it). GitHub's `xcode-27` runner is used in CI.

## Working without a Mac

1. Create a GitHub repo and push this folder to `main`.
   A **public** repo gets free macOS build minutes; private repos have a limited allowance.
2. The **Build** workflow runs on every push and compiles the app for tvOS.
   A green tick means the code compiles. You can't install it yet.
3. To install on your Apple TV you need a **paid Apple Developer account** (see below).

## Building with Codemagic (alternative to GitHub Actions)

1. Push this folder to a GitHub repo (public or private; the build doesn't use GitHub Actions).
2. Sign in at codemagic.io with GitHub and add the repo as an application.
3. Codemagic detects `codemagic.yaml`. Start the **tvOS unsigned IPA** workflow
   (or push to `main` once the webhook is set up).
4. Download `StreamBox-unsigned.ipa` from the build's Artifacts and sideload it
   with Sideloadly or atvloadly using your Apple ID.

## Turning on TestFlight (needs a paid account)

1. Join the Apple Developer Program.
2. In the developer portal, register the bundle ID `com.mauro.streambox` (or change it in `project.yml`).
3. In App Store Connect, create a new **tvOS** app with that bundle ID.
4. In App Store Connect → Users and Access → Integrations, create an **API key with Admin access**
   (Admin is needed so CI can create the distribution certificate).
5. In GitHub → Settings → Secrets and variables → Actions, add:
   - Secret `ASC_KEY_ID`: the key ID
   - Secret `ASC_ISSUER_ID`: the issuer ID
   - Secret `ASC_KEY_P8_BASE64`: run `base64 -w0 AuthKey_XXXX.p8` (or use PowerShell
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`)
   - Secret `APPLE_TEAM_ID`: your 10-character team ID
   - **Variable** `ENABLE_TESTFLIGHT` = `true`
6. Push again. The build uploads to TestFlight. Open the TestFlight app on the Apple TV,
   signed in with the same Apple ID, and install.

**Before the first upload:** App Store Connect rejects tvOS builds without the layered
app icon and top-shelf image assets. Add an `Assets.xcassets` with an
"App Icon & Top Shelf Image" brand asset, then set
`ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml`.

## First run on the TV

Settings → Connections:
- **TMDB:** free at themoviedb.org → Settings → API (the long "API Read Access Token").
- **IPTV:** server, username and password from your Xtream Codes provider, then **Test connection**.
- **Stremio addons:** Add addon → the manifest URL from the addon's configuration page. Only results with a direct link play; torrent-only results are hidden.

Tip: typing on the Apple TV is painful. Your iPhone shows a keyboard notification whenever a text field is focused.

## Roadmap

1. ~~Shell, TMDB rails, detail pages~~
2. ~~Xtream live TV + short EPG~~
3. ~~Stremio addon streams~~ (Real-Debrid removed; addons must return direct links)
4. ~~Player: AetherEngine for live TV, movies and series (MKV, HDR10/DV, Atmos passthrough, PGS/ASS subs, live retune)~~. Next: resume positions, track picker UI
5. ~~Movies & Series tabs (TMDB rows + genres), Live TV favourites, hidden categories, sorting, timeshift, user agent, expanded settings~~. Next: Xtream VOD + series, full XMLTV EPG grid
6. Continue watching / resume positions, Trakt sync
7. Stream ranking and auto-pick
8. Top shelf extension, profiles
