# FixNear

FixNear is a local services marketplace built with Flutter and Firebase. Customers
find nearby providers (plumbing, electrical, cleaning, repairs, moving and more),
request a service, compare quotes, and track the job from booking to cash payment.
Providers receive open requests, send quotes, update job progress, and chat with
customers.

## Features

- **Customers**: browse and search available providers by category, request a
  service with a schedule and optional GPS pin, accept quotes, chat with the
  assigned provider, confirm completion, and record a cash payment. Customers
  can edit their name and phone number and upload a profile picture (stored on
  Cloudinary).
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
    profile/               Edit profile and profile picture upload
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
4. Set up Cloudinary for profile pictures (see below).
5. Run the app:

   ```sh
   flutter pub get
   flutter run -d chrome \
     --dart-define=CLOUDINARY_CLOUD_NAME=your-cloud-name \
     --dart-define=CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset
   ```

   Pass the same `--dart-define` flags to `flutter build`. Without them the app
   still runs, but photo uploads are disabled.

## Cloudinary setup (profile pictures)

Profile pictures are uploaded straight from the app to Cloudinary using an
**unsigned upload preset**, so no API secret is ever shipped in the app.

1. Sign in to the [Cloudinary console](https://console.cloudinary.com/) and
   copy your **cloud name** from the dashboard.
2. Go to **Settings → Upload → Upload presets → Add upload preset**.
3. Set **Signing mode** to **Unsigned** and save. Recommended restrictions:
   - **Folder**: `fixnear/avatars`
   - **Allowed formats**: `jpg, png, webp, heic`
   - **Max file size**: 5 MB
   - **Incoming transformation**: `c_limit,w_1024,h_1024`
4. Use the preset name as `CLOUDINARY_UPLOAD_PRESET`.

The app stores the returned `https://res.cloudinary.com/...` URL in the user's
`photoUrl` field. Firestore rules only accept Cloudinary URLs there. Avatars are
displayed through a face-cropped, auto-format Cloudinary transformation.

> Never put the Cloudinary **API secret** in the app or in `--dart-define`.

## Development

```sh
flutter analyze
flutter test
```
