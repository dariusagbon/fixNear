# FixNear

FixNear is a local services marketplace built with Flutter and Firebase. Customers
find nearby providers (plumbing, electrical, cleaning, repairs, moving and more),
request a service, compare quotes, and track the job from booking to cash payment.
Providers receive open requests, send quotes, update job progress, and chat with
customers.

## Features

- **Customers**: browse and search available providers by category, request a
  service with a schedule and optional GPS pin, accept quotes, chat with the
  assigned provider, confirm completion, and record a cash payment.
- **Providers**: see open and targeted requests, send or decline quotes, move
  jobs through *On the way → Arrived → In progress → Complete*, confirm cash
  received, and track confirmed earnings.

## Project structure

```
lib/
  app.dart                 App shell and Firebase initialization gate
  core/
    models/                Firestore-backed data models
    services/              Auth and marketplace repositories
    theme/                 App-wide Material 3 theme
    utils/                 Formatting and error-message helpers
    widgets/               Shared widgets (status chips, layout helpers)
  features/
    auth/                  Sign-in / registration and role routing
    customer/              Customer marketplace
    provider/              Provider workspace
    messaging/             Per-job chat
firestore.rules            Firestore security rules
```

## Getting started

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Enable **Email/Password** sign-in and **Cloud Firestore** in the Firebase
   project configured in `lib/firebase_options.dart`.
3. Deploy the security rules: `firebase deploy --only firestore:rules`.
4. Run the app:

   ```sh
   flutter pub get
   flutter run -d chrome   # or any connected device
   ```

## Development

```sh
flutter analyze
flutter test
```
