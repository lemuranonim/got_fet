# GOT & FET

Standalone Flutter application for the GOT and FET workflow.

## Setup

1. Install Flutter and Android build tooling.
2. Create a local environment file:

   ```powershell
   Copy-Item .env.example .env
   ```

3. Fill in the Supabase values in `.env`.
4. Install dependencies:

   ```powershell
   flutter pub get
   ```

5. Run the app:

   ```powershell
   flutter run
   ```

## Environment

```dotenv
SUPABASE_URL=
SUPABASE_ANON_KEY=
```

## Build

Create a debug APK:

```powershell
flutter build apk --debug
```

The output is written to `build/app/outputs/flutter-apk/app-debug.apk`.
