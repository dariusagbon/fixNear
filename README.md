# FixNear

FixNear is a home-services marketplace for Davao Region, built with Flutter and
Firebase (project `fixnear-d5c1c`). It runs on web, Android and iOS.

Customers post jobs, compare quotes, book, track, chat and pay cash. Providers
quote, move booked jobs forward and confirm payment.

Job status flow: `requested → quoted → accepted → on_the_way → arrived →
in_progress → provider_completed → completed`, then cash is recorded by the
customer and confirmed by the provider.

## Features

- **Customers**: search providers by category, with distance when location is
  allowed; post a job with a schedule, a map pin or current location (typed area
  and landmark as a fallback) and up to 5 photos; compare and accept quotes;
  reschedule, or cancel (with a reason) until the provider arrives; chat;
  confirm completion; record cash payment; edit profile and photo
  (Cloudinary).
- **Providers**: go online or offline; set a base location and a service radius
  (2–50 km) on the **Service** tab; see a job board with jobs sent to them
  first, then jobs in their trade within their radius nearest first ("2.3 km
  away"), with an "All services" option; quote, decline (a job sent directly
  to them then reopens to others), withdraw before arriving ("Can't make it"),
  move jobs forward, confirm cash, track earnings; edit their name, phone and
  photo (tap their name at the top), which customers see.
- **Accounts**: password reset, email verification, and account deletion
  (Edit profile → Delete account), which is refused while a job is active.
- **Automatic upkeep** (Cloud Functions): losing quotes are closed when one is
  accepted; every morning, open jobs more than a day past their date are
  closed, and customers and providers are reminded of confirmations waiting on
  them.
- **Push notifications** for new jobs, quotes, bookings, status changes,
  payments and chat. Tapping one opens the job's detail page.

## Project structure

```
lib/
  app.dart                 App shell and Firebase initialization gate
  core/
    models/                Firestore models (missing fields read with safe defaults)
    services/              Auth, marketplace repository, push, location, Cloudinary
    theme/                 App theme (see "Design rules")
    utils/                 Formatting, distance/geohash, job matching, feedback
    widgets/               Status chip, layout helpers, avatar
  features/
    auth/                  Sign-in / registration and role routing
    customer/              Customer marketplace
    provider/              Provider workspace and Service settings
    jobs/                  Job cards, shared actions and the job detail page
    notifications/         Notification tap handling and permission prompt
    location/              Map pin picker
    messaging/             Per-job chat
    profile/               Edit profile and photo upload
functions/                 Cloud Functions (TypeScript) for push notifications
rules-tests/               Security-rule and job-loop tests (Emulator Suite)
firestore.rules            Firestore security rules
storage.rules              Storage rules (locked; photos live on Cloudinary)
test/                      Flutter tests; widget_test.dart holds the fake repository
```

When you add a method to `MarketplaceRepository`, add it to the fake repository
in `test/widget_test.dart` too.

## Getting started

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
   Node.js 22.
2. In the Firebase console, enable **Email/Password** sign-in and **Cloud
   Firestore**.
3. From the repo root, deploy the rules:
   `npx firebase-tools deploy --only firestore:rules --project fixnear-d5c1c`.
   (`storage.rules` needs a Storage bucket to exist; leave it out until you use
   Storage.)
4. Run the app. Every `--dart-define` is optional; features without their
   settings turn themselves off:

   ```sh
   flutter pub get
   flutter run -d chrome \
     --dart-define=CLOUDINARY_CLOUD_NAME=your-cloud-name \
     --dart-define=CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset \
     --dart-define=FCM_VAPID_KEY=your-web-push-key \
     --dart-define=MAPS_ENABLED=true
   ```

   | Define | Used for | Without it |
   | --- | --- | --- |
   | `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_UPLOAD_PRESET` | Profile and job photos | Uploads disabled |
   | `CLOUDINARY_FOLDER` | Default Cloudinary folder (optional) | Profile photos go to `fixnear/avatars`, job photos to `fixnear/service-requests` |
   | `FCM_VAPID_KEY` | Web push | No push on web (Android/iOS still work) |
   | `MAPS_ENABLED=true` | Map pin picker | "Use my current location" and typed area only |

## Testing

```sh
flutter analyze
flutter test                          # widget, layout, geo and job-loop tests

cd rules-tests && npm install && npm test   # security rules + full job loop in the emulators
cd functions && npm install && npm test     # notification rules + delivery (Firestore emulator)
cd functions && npm run test:e2e            # optional: triggers firing in the Functions emulator
```

The emulator tests need Java 21+. They use the `demo-fixnear` project ID, so
they never touch the real project.

## Push notifications

The app saves each device's FCM token at `users/{uid}/tokens/{token}` and
removes it on sign-out. It asks for notification permission the first time a
customer posts a job or a provider goes online, never at launch.

Setup:

1. **Android**: nothing extra. The `job_updates` channel is created by
   `MainActivity`.
2. **iOS**: in the Apple Developer portal, create an APNs key and upload it in
   Firebase console → Project settings → Cloud Messaging. In Xcode, check that
   the Runner target has the Push Notifications capability (the entitlement file
   is already in `ios/Runner/Runner.entitlements`).
3. **Web**: Firebase console → Project settings → Cloud Messaging → Web Push
   certificates → **Generate key pair**. Pass the public key as
   `--dart-define=FCM_VAPID_KEY=...`. Web push needs HTTPS (or localhost).
   `web/firebase-messaging-sw.js` must use the same Firebase JS SDK version as
   `firebase_core_web` (currently 12.19.0).

Notification taps open the job detail page. On web, notifications link to
`<APP_URL>/?job=<id>`.

## Cloud Functions

`functions/` sends the notifications. All four functions run in
**asia-southeast1**:

| Function | Trigger | Notifies |
| --- | --- | --- |
| `notifyJobPosted` | job created | the chosen provider, or online providers whose radius covers the job (text-area match when either side has no coordinates) |
| `notifyQuoteWritten` | quote created / changed | customer (new or updated quote); provider (quote accepted) |
| `notifyJobUpdated` | job updated | customer on each provider step; provider when cash is recorded; customer when cash is confirmed |
| `notifyMessageSent` | chat message | the other participant |
| `notifyJobUpdated` (also) | declined direct job, provider withdrawal, quote accepted, cancellation, reschedule | customer and nearby providers when a job reopens; losing providers; booked or quoting providers on cancellation; booked provider on a new time |
| `cleanUpDeletedUser` | login deleted | removes tokens and listing, withdraws open quotes, anonymises names on past jobs |
| `dailyJobSweep` | every day 9:00 Asia/Manila | closes stale open jobs; reminds customers to confirm work and providers to confirm cash |

Deploying needs the **Blaze (pay-as-you-go)** plan (the daily sweep also uses
Cloud Scheduler). Deploy the Firestore index too:
`npx firebase-tools deploy --only firestore:indexes --project fixnear-d5c1c`. Firestore triggers must run
in the same region as your Firestore database. If the database isn't in
`asia-southeast1`, change `REGION` in `functions/src/index.ts`.

```sh
(cd functions && npm install)
npx firebase-tools deploy --only functions --project fixnear-d5c1c   # from the repo root
```

On first deploy you are asked for `APP_URL`, the public web app URL used in web
notification links (default `https://fixnear-d5c1c.web.app`).

## Maps and distance matching

Jobs store `latitude`, `longitude` and a 9-character `geohash`. Providers store
`baseLatitude`, `baseLongitude`, `baseGeohash` and `serviceRadiusKm` (default
10, 2–50). Jobs and providers without coordinates keep working through their
text service area.

The map pin picker needs a Google Maps key per platform. Keys never go in git:

1. In Google Cloud console (project `fixnear-d5c1c`), enable **Maps SDK for
   Android**, **Maps SDK for iOS** and **Maps JavaScript API**, and create keys
   restricted to your app IDs and web domain. Maps usage is billed beyond the
   free monthly allowance.
2. **Android**: add `MAPS_API_KEY=...` to `android/local.properties` (or set
   the `MAPS_API_KEY` environment variable in CI).
3. **iOS**: copy `ios/Flutter/Secrets.example.xcconfig` to
   `ios/Flutter/Secrets.xcconfig` and fill in `MAPS_API_KEY`.
4. **Web**: copy `web/maps-config.example.js` to `web/maps-config.js` and fill
   in `window.FIXNEAR_MAPS_API_KEY`.
5. Build with `--dart-define=MAPS_ENABLED=true`.

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

The app stores returned `https://res.cloudinary.com/...` URLs in `photoUrl`
(user profile and, for providers, their listing) and in a job's `photoUrls`
(at most 5). Firestore rules only accept Cloudinary URLs for profile photos.
If your preset fixes an asset folder, it overrides the folders above.

> Never put the Cloudinary **API secret** in the app or in `--dart-define`.

## Design rules

- Dark ink `#1D2B2E` for text and main buttons, grey-green `#EDF0EA`
  background, white panels with thin borders, no shadows.
- Yellow `#F5B700` only means "this needs you now" (the status chip's
  needs-you state).
- Tap targets are at least 48px. Layout tests run at 360px and 1280px and check
  Flutter's tap-target and text-contrast guidelines.
- Every list has a loading state, an empty state and a plain-language error
  state.
