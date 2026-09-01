# Building Sello for private testing

App name: **Sello**  
Version: **1.0.0+1**  
Android application ID / iOS bundle ID: `com.ayraudhaya.sello`

This document covers local development and the first private-testing builds. It does not cover Play Store, App Store, TestFlight, staging/production flavors, or in-app updates.

## Prerequisites

- Flutter SDK (stable), Dart `^3.12.2`
- A local `.env` copied from `.env.example` with your existing Supabase project values
- For Android APKs: Android SDK / Android Studio
- For iOS: macOS, Xcode, CocoaPods, and an Apple Developer team (not configured in this repo yet)
- For Web: a browser; Vercel (or any static host) later for deployment

Do not commit `.env`, keystores, or `key.properties`.

## Supabase configuration (dart-define)

Release builds do **not** bundle `.env` as a Flutter asset. The app reads public client config at compile time:

| Define | Required |
| --- | --- |
| `SUPABASE_URL` | Yes |
| `SUPABASE_ANON_KEY` | Yes (preferred) |
| `SUPABASE_PUBLISHABLE_KEY` | Accepted if `SUPABASE_ANON_KEY` is omitted |

Never pass a Supabase **service-role** key into the Flutter app.

### Development

Use the full `.env` (Supabase + optional `DX_*` debug accounts):

```bash
flutter run --dart-define-from-file=.env
```

Cursor / VS Code: use the **Sello (debug)** launch configuration (same flag).

Equivalent explicit defines:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

DX auto-login and the debug toolbar are compiled out of **release** mode. Do not put `DX_*` values into a release dart-define file.

### Release / private testing

Create a local file that contains **only** the two public Supabase values (for example `.env.release`, gitignored):

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

Then pass that file to every release build command below.

## Development run

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

## Flutter Web release

```bash
flutter build web --release --dart-define-from-file=.env.release
```

Output: `build/web/`

Path-based URLs are enabled (`/sello/...`, `/hub/...`). `vercel.json` rewrites unknown paths to `index.html` so a refresh on a nested route does not 404. Deploy is not part of this step.

If the app will be served from a subpath, add `--base-href=/your-subpath/`.

## Android release APK

The first private-testing APK still uses the Flutter **debug signing config** so `flutter build apk` works without a keystore in the repo. Replace this with a real upload keystore before any store or wider distribution. Keep the keystore and passwords off the repository.

Build **two** APKs. Each must set `SELLO_RELEASE_APP` so in-app updates read the matching entry in `sello_app_release.payload` (`apps.sales_rep` vs `apps.owner_manager`). Host the files at:

- Sales Rep: `https://cashro.pro/sello-updates/sales-rep/sello-sales-rep.apk`
- Owner/Manager: `https://cashro.pro/sello-updates/owner-manager/sello-owner-manager.apk`

Or build both in one go (copies named APKs into `dist/`):

```powershell
.\scripts\build_android_apks.ps1
```

To build them one at a time:

```bash
flutter build apk --release --dart-define-from-file=.env.release --dart-define=SELLO_RELEASE_APP=sales_rep
```

Copy `build/app/outputs/flutter-apk/app-release.apk` to `sello-sales-rep.apk` **before** the next build (that folder is overwritten).

```bash
flutter build apk --release --dart-define-from-file=.env.release --dart-define=SELLO_RELEASE_APP=owner_manager
```

Copy `build/app/outputs/flutter-apk/app-release.apk` to `sello-owner-manager.apk`.

On Windows, if Kotlin fails with `this and base files have different roots` (project on `D:` and pub-cache on `C:`), `android/gradle.properties` already sets `kotlin.incremental=false`. Stop leftover Gradle daemons with `android\gradlew.bat --stop`, then rebuild.

An app bundle (not required for this private test) would be:

```bash
flutter build appbundle --release --dart-define-from-file=.env.release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

## iOS (not fully configured yet)

An iOS simulator/device build on a Mac:

```bash
flutter build ios --release --dart-define-from-file=.env.release
```

Still required before a real device / TestFlight binary:

- Open `ios/Runner.xcworkspace` in Xcode on macOS
- Select a **Development Team** (signing)
- Run `pod install` in `ios/` if CocoaPods has not been generated yet
- Archive / TestFlight setup comes later — not part of this step

This Windows environment cannot produce an iOS IPA.

## Signing considerations

- Do not put keystore files, `key.properties`, or passwords in git.
- Debug-signed Android release APKs are fine for a small private tester group only.
- iOS signing requires an Apple team in Xcode; this repo does not embed a team ID.
- Anon / publishable keys are public client credentials (RLS still protects data). They are not service-role keys.

## Checks

```bash
flutter analyze
flutter test
```

## Automated release

Build, stamp manifests, update Supabase, and optionally upload to 20i — all in one command:

```powershell
.\scripts\release_android.ps1 1.0.4+5 -Notes "Bug fixes"
```

Options:

| Flag | Effect |
|------|--------|
| `-Notes "…"` | Set release notes for both apps |
| `-Apps sales_rep` | Only release one app |
| `-SkipBuild` | Skip APK build (use existing dist/) |
| `-SkipSupabase` | Skip Supabase row update |
| `-Upload` | Upload APKs to 20i via FTP |
| `-DryRun` | Show what would happen without doing it |

**Environment variables** (set in your shell, never commit):

| Variable | Purpose |
|----------|---------|
| `SUPABASE_PROJECT_REF` | Project ref (e.g. `pohfozsptcrnitbxgaep`) |
| `SUPABASE_SERVICE_ROLE` | Service-role key for updating the release row |
| `SELLO_FTP_HOST` | 20i FTP hostname |
| `SELLO_FTP_USER` | 20i FTP username |
| `SELLO_FTP_PASS` | 20i FTP password |

If credentials are missing, the script prints the manual SQL and skips the upload step.

## Release metadata (update checking)

The installed app version is `pubspec.yaml` (for example `1.0.2+3` → version `1.0.2`, build `3`). Do not duplicate it in Dart, and do not bump it only to change the release JSON schema.

The **latest** version is **not** compiled into the app. Edit the public JSON (`schema_version` 2):

- Source of truth: `releases/sello-release.json`
- Copied for Flutter web: `web/sello-release.json` (keep these in sync)

Bump `apps.sales_rep.latest` and/or `apps.owner_manager.latest`, add notes, and keep Android `destination_url` pointing at the 20i APKs. Leave `minimum.enforced` as `false` until you intentionally require an update for that app.

Native builds first try `SELLO_RELEASE_MANIFEST_URL` or `SELLO_PUBLIC_URL/sello-release.json`. If those are unset (typical APK), the app reads the public `sello_app_release` row in Supabase instead — apply migrations **041** then **042**. Web can also use `/sello-release.json` on the current origin.

When you ship a new version, update `releases/sello-release.json`, `web/sello-release.json`, **and** the `sello_app_release.payload` row so installed apps see the same latest version.
