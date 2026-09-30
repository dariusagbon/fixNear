// Background push for the web app.
//
// Firebase Cloud Messaging loads this worker to show notifications while
// FixNear isn't the focused tab. Notifications from the Cloud Functions
// include a link (…/?job=<id>) that opens the job when clicked.
//
// Keep the SDK version in step with firebase_core_web's
// supportedFirebaseJsSdkVersion. These config values are public web app
// identifiers (they are also in lib/firebase_options.dart), not secrets.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA2kg2rWZv0akDSAyu6xj80_Q9va2DeGEo',
  appId: '1:36315507942:web:04d8772d80457b740d9f27',
  messagingSenderId: '36315507942',
  projectId: 'fixnear-d5c1c',
  authDomain: 'fixnear-d5c1c.firebaseapp.com',
  storageBucket: 'fixnear-d5c1c.firebasestorage.app',
});

// Notification payloads are displayed by the SDK automatically, and clicks
// open webpush.fcmOptions.link. Registering the handler keeps the worker
// ready for data-only messages too.
firebase.messaging().onBackgroundMessage(() => {});
