// Smoke test: with the Functions and Firestore emulators running, writes
// that the app makes trigger the notification functions. Run with
// `npm run test:e2e`. FCM itself is not emulated; the functions log what
// they would deliver.
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const db = getFirestore(initializeApp({ projectId: 'demo-fixnear' }));

await db.doc('providerProfiles/near').set({
  name: 'Near Provider', serviceArea: 'Davao City', isAvailable: true,
  baseLatitude: 7.0996, baseLongitude: 125.6317, serviceRadiusKm: 10,
});
await db.doc('serviceRequests/e2e-job').set({
  customerUid: 'customer-1', customerName: 'Casey Customer', category: 'Plumbing',
  description: 'Fix a leaking faucet', serviceArea: 'Davao City',
  latitude: 7.0654, longitude: 125.6076, providerUid: null,
  status: 'requested', paymentStatus: 'unpaid',
});
await db.doc('serviceRequests/e2e-job/quotes/near').set({
  providerUid: 'near', providerName: 'Near Provider', price: 850, note: 'ok', status: 'sent',
});
await db.doc('serviceRequests/e2e-job').update({ status: 'accepted', providerUid: 'near', providerName: 'Near Provider' });
await db.doc('serviceRequests/e2e-job').update({ status: 'on_the_way' });
await db.collection('serviceRequests/e2e-job/messages').add({ senderUid: 'near', senderName: 'Near Provider', text: 'Almost there' });

// Give the emulator time to run the triggers.
await new Promise((resolve) => setTimeout(resolve, 8000));
process.exit(0);
