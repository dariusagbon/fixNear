// Security-rule tests: one block per write the app makes, each with the
// valid write and the invalid variants the rules must reject.

import { after, before, beforeEach, describe, it } from 'node:test';
import {
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  addDoc,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore';
import {
  CUSTOMER,
  OTHER_CUSTOMER,
  OTHER_PROVIDER,
  PROVIDER,
  acceptUpdate,
  assertFails,
  assertSucceeds,
  baseUsers,
  confirmCashUpdate,
  createEnv,
  dbAs,
  declineUpdate,
  messageDoc,
  newRequest,
  providerProfileDoc,
  quoteDoc,
  serviceSettingsUpdate,
  recordCashUpdate,
  seed,
  statusUpdate,
  storedRequest,
  userDoc,
} from './helpers.js';

let env;
before(async () => {
  env = await createEnv();
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed(env, baseUsers());
});

const REQ = 'serviceRequests/request-1';

describe('users (registration and profile)', () => {
  it('lets a new customer create their own profile', async () => {
    const db = dbAs(env, 'new-user');
    await assertSucceeds(
      setDoc(doc(db, 'users/new-user'), userDoc({
        email: 'n@example.com', name: 'New', role: 'customer',
      })),
    );
  });

  it('lets a new provider create their user and provider profile together', async () => {
    const db = dbAs(env, 'new-pro');
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/new-pro'), userDoc({
      email: 'p@example.com', name: 'New Pro', role: 'provider',
    }));
    batch.set(doc(db, 'providerProfiles/new-pro'), providerProfileDoc({ name: 'New Pro' }));
    await assertSucceeds(batch.commit());
  });

  it('rejects creating a profile for someone else', async () => {
    const db = dbAs(env, 'new-user');
    await assertFails(
      setDoc(doc(db, 'users/someone-else'), userDoc({
        email: 'n@example.com', name: 'New', role: 'customer',
      })),
    );
  });

  it('rejects an unknown role or extra fields', async () => {
    const db = dbAs(env, 'new-user');
    await assertFails(
      setDoc(doc(db, 'users/new-user'), userDoc({
        email: 'n@example.com', name: 'New', role: 'admin',
      })),
    );
    await assertFails(
      setDoc(doc(db, 'users/new-user'), {
        ...userDoc({ email: 'n@example.com', name: 'New', role: 'customer' }),
        isAdmin: true,
      }),
    );
  });

  it('rejects a customer creating a provider profile', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertFails(
      setDoc(doc(db, `providerProfiles/${CUSTOMER}`), providerProfileDoc({ name: 'Casey' })),
    );
  });

  it('lets a user update their name, phone and Cloudinary photo', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(updateDoc(doc(db, `users/${CUSTOMER}`), {
      name: 'Casey C.',
      phone: '+63 912 345 6789',
      photoUrl: 'https://res.cloudinary.com/gp7e9yws/image/upload/v1/a.jpg',
    }));
    await assertSucceeds(updateDoc(doc(db, `users/${CUSTOMER}`), { photoUrl: null }));
  });

  it('rejects role changes, bad photos and edits to other users', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertFails(updateDoc(doc(db, `users/${CUSTOMER}`), { role: 'provider' }));
    await assertFails(updateDoc(doc(db, `users/${CUSTOMER}`), {
      photoUrl: 'https://evil.example/a.jpg',
    }));
    await assertFails(updateDoc(doc(db, `users/${CUSTOMER}`), { name: '' }));
    await assertFails(updateDoc(doc(db, `users/${OTHER_CUSTOMER}`), { name: 'Hacked' }));
  });

  it('only lets users read their own profile', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(getDoc(doc(db, `users/${CUSTOMER}`)));
    await assertFails(getDoc(doc(db, `users/${PROVIDER}`)));
  });
});

describe('push tokens', () => {
  const token = 'fcm-token-abc123';
  const tokenDoc = () => ({
    token,
    platform: 'android',
    updatedAt: serverTimestamp(),
  });

  it('lets a user save, refresh and remove their own device token', async () => {
    const ref = doc(dbAs(env, CUSTOMER), `users/${CUSTOMER}/tokens/${token}`);
    await assertSucceeds(setDoc(ref, tokenDoc()));
    await assertSucceeds(setDoc(ref, tokenDoc()));
    await assertSucceeds(deleteDoc(ref));
  });

  it('rejects tokens for other users, mismatched IDs and extra fields', async () => {
    await assertFails(setDoc(
      doc(dbAs(env, PROVIDER), `users/${CUSTOMER}/tokens/${token}`),
      tokenDoc(),
    ));
    await assertFails(setDoc(
      doc(dbAs(env, CUSTOMER), `users/${CUSTOMER}/tokens/other-token`),
      tokenDoc(),
    ));
    await assertFails(setDoc(
      doc(dbAs(env, CUSTOMER), `users/${CUSTOMER}/tokens/${token}`),
      { ...tokenDoc(), platform: 'fax' },
    ));
    await assertFails(setDoc(
      doc(dbAs(env, CUSTOMER), `users/${CUSTOMER}/tokens/${token}`),
      { ...tokenDoc(), uid: PROVIDER },
    ));
  });

  it('rejects reading tokens, even your own', async () => {
    await seed(env, { [`users/${CUSTOMER}/tokens/${token}`]: { token, platform: 'web', updatedAt: Timestamp.now() } });
    await assertFails(getDoc(doc(dbAs(env, CUSTOMER), `users/${CUSTOMER}/tokens/${token}`)));
    await assertFails(deleteDoc(doc(dbAs(env, PROVIDER), `users/${CUSTOMER}/tokens/${token}`)));
  });
});

describe('providerProfiles', () => {
  it('lets a provider update their own listing', async () => {
    const db = dbAs(env, PROVIDER);
    await assertSucceeds(updateDoc(doc(db, `providerProfiles/${PROVIDER}`), {
      isAvailable: false,
    }));
  });

  it('lets a provider save their base location and service radius', async () => {
    const ref = doc(dbAs(env, PROVIDER), `providerProfiles/${PROVIDER}`);
    await assertSucceeds(updateDoc(ref, serviceSettingsUpdate()));
    await assertSucceeds(updateDoc(ref, serviceSettingsUpdate({ serviceRadiusKm: 2 })));
    await assertSucceeds(updateDoc(ref, serviceSettingsUpdate({ serviceRadiusKm: 50 })));
    // Clearing the base location is allowed.
    await assertSucceeds(updateDoc(ref, serviceSettingsUpdate({
      baseLatitude: null, baseLongitude: null, baseGeohash: null,
    })));
  });

  it('rejects a radius outside 2–50 km or a broken location', async () => {
    const ref = doc(dbAs(env, PROVIDER), `providerProfiles/${PROVIDER}`);
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ serviceRadiusKm: 1 })));
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ serviceRadiusKm: 51 })));
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ serviceRadiusKm: '10' })));
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ baseLongitude: null })));
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ baseLatitude: 91 })));
    await assertFails(updateDoc(ref, serviceSettingsUpdate({ baseGeohash: 'x'.repeat(40) })));
  });

  it('lets a provider set a Cloudinary photo and name on their listing', async () => {
    const ref = doc(dbAs(env, PROVIDER), `providerProfiles/${PROVIDER}`);
    await assertSucceeds(updateDoc(ref, {
      name: 'Pat Plumbing',
      photoUrl: 'https://res.cloudinary.com/gp7e9yws/image/upload/v1/p.jpg',
    }));
    await assertSucceeds(updateDoc(ref, { photoUrl: null }));
    await assertFails(updateDoc(ref, { photoUrl: 'https://evil.example/p.jpg' }));
    await assertFails(updateDoc(ref, { photoUrl: 42 }));
  });

  it('rejects edits by other providers or customers', async () => {
    await assertFails(updateDoc(
      doc(dbAs(env, OTHER_PROVIDER), `providerProfiles/${PROVIDER}`),
      { isAvailable: false },
    ));
    await assertFails(updateDoc(
      doc(dbAs(env, CUSTOMER), `providerProfiles/${PROVIDER}`),
      { startingPrice: 1 },
    ));
  });

  it('lets signed-in users list available providers', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(getDocs(query(
      collection(db, 'providerProfiles'),
      where('isAvailable', '==', true),
    )));
  });
});

describe('serviceRequests: posting a job', () => {
  it('lets a customer post a job with a pinned location', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(setDoc(doc(db, REQ), newRequest()));
  });

  it('allows up to five job photos', async () => {
    const db = dbAs(env, CUSTOMER);
    const photos = (n) => Array.from({ length: n },
      (_, i) => `https://res.cloudinary.com/demo/image/upload/v1/job-${i}.jpg`);
    await assertSucceeds(setDoc(doc(db, REQ), { ...newRequest(), photoUrls: photos(5) }));
    await assertFails(setDoc(doc(db, 'serviceRequests/request-2'), { ...newRequest(), photoUrls: photos(6) }));
  });

  it('rejects an oversized geohash', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertFails(setDoc(doc(db, REQ), newRequest({ geohash: 'x'.repeat(40) })));
  });

  it('lets a customer post a job without coordinates', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(setDoc(doc(db, REQ), newRequest({
      latitude: null, longitude: null,
    })));
  });

  it('lets a customer send a job directly to an available provider', async () => {
    const db = dbAs(env, CUSTOMER);
    await assertSucceeds(setDoc(doc(db, REQ), newRequest({
      providerUid: PROVIDER, providerName: 'Pat Provider',
    })));
  });

  it('rejects invalid jobs', async () => {
    const db = dbAs(env, CUSTOMER);
    // Posted for someone else.
    await assertFails(setDoc(doc(db, REQ), newRequest({ customerUid: OTHER_CUSTOMER })));
    // Skipping straight to accepted.
    await assertFails(setDoc(doc(db, REQ), { ...newRequest(), status: 'accepted' }));
    // Half a coordinate, or an impossible one.
    await assertFails(setDoc(doc(db, REQ), newRequest({ longitude: null })));
    await assertFails(setDoc(doc(db, REQ), newRequest({ latitude: 200 })));
    // Unknown field.
    await assertFails(setDoc(doc(db, REQ), { ...newRequest(), priority: 'high' }));
  });

  it('rejects providers posting jobs', async () => {
    const db = dbAs(env, PROVIDER);
    await assertFails(setDoc(doc(db, REQ), newRequest({ customerUid: PROVIDER })));
  });

  it('rejects sending a job to an unavailable provider', async () => {
    await seed(env, {
      [`providerProfiles/${PROVIDER}`]: {
        ...baseUsers()[`providerProfiles/${PROVIDER}`],
        isAvailable: false,
      },
    });
    const db = dbAs(env, CUSTOMER);
    await assertFails(setDoc(doc(db, REQ), newRequest({
      providerUid: PROVIDER, providerName: 'Pat Provider',
    })));
  });
});

describe('serviceRequests: cancel and decline', () => {
  it('lets the customer cancel an open job', async () => {
    await seed(env, { [REQ]: storedRequest() });
    await assertSucceeds(updateDoc(doc(dbAs(env, CUSTOMER), REQ), statusUpdate('cancelled')));
  });

  it('rejects cancelling a booked job or someone else’s job', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'accepted', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, CUSTOMER), REQ), statusUpdate('cancelled')));
    await seed(env, { [REQ]: storedRequest() });
    await assertFails(updateDoc(doc(dbAs(env, OTHER_CUSTOMER), REQ), statusUpdate('cancelled')));
  });

  it('lets a provider decline an open job for themselves only', async () => {
    await seed(env, { [REQ]: storedRequest() });
    await assertSucceeds(updateDoc(doc(dbAs(env, PROVIDER), REQ), declineUpdate(PROVIDER)));
    await assertFails(updateDoc(doc(dbAs(env, PROVIDER), REQ), declineUpdate(OTHER_PROVIDER)));
  });
});

describe('quotes', () => {
  async function sendQuote(uid, price = 850) {
    const db = dbAs(env, uid);
    const batch = writeBatch(db);
    batch.set(doc(db, `${REQ}/quotes/${uid}`), quoteDoc({ providerUid: uid, price }));
    batch.update(doc(db, REQ), statusUpdate('quoted'));
    return batch.commit();
  }

  it('lets a provider quote an open job and then revise it', async () => {
    await seed(env, { [REQ]: storedRequest() });
    await assertSucceeds(sendQuote(PROVIDER, 850));
    await assertSucceeds(sendQuote(PROVIDER, 800));
    await assertSucceeds(sendQuote(OTHER_PROVIDER, 900));
  });

  it('rejects quotes on jobs sent to another provider', async () => {
    await seed(env, { [REQ]: storedRequest({ providerUid: PROVIDER, providerName: 'Pat' }) });
    await assertFails(sendQuote(OTHER_PROVIDER));
  });

  it('rejects quotes after the provider declined', async () => {
    await seed(env, { [REQ]: storedRequest({ declinedProviderUids: [PROVIDER] }) });
    await assertFails(sendQuote(PROVIDER));
  });

  it('rejects a zero price, customer quotes and quoting for someone else', async () => {
    await seed(env, { [REQ]: storedRequest() });
    await assertFails(sendQuote(PROVIDER, 0));
    const db = dbAs(env, CUSTOMER);
    await assertFails(setDoc(doc(db, `${REQ}/quotes/${CUSTOMER}`), quoteDoc({ providerUid: CUSTOMER })));
    await assertFails(setDoc(
      doc(dbAs(env, PROVIDER), `${REQ}/quotes/${OTHER_PROVIDER}`),
      quoteDoc({ providerUid: OTHER_PROVIDER }),
    ));
  });

  it('rejects revising a quote once the job is booked', async () => {
    await seed(env, {
      [REQ]: storedRequest({ status: 'accepted', providerUid: PROVIDER, quotedPrice: 850 }),
      [`${REQ}/quotes/${PROVIDER}`]: { ...quoteDoc(), status: 'accepted', createdAt: Timestamp.now() },
    });
    await assertFails(setDoc(doc(dbAs(env, PROVIDER), `${REQ}/quotes/${PROVIDER}`), quoteDoc({ price: 5000 })));
  });

  it('only lets the customer and the quoting provider read a quote', async () => {
    await seed(env, {
      [REQ]: storedRequest({ status: 'quoted' }),
      [`${REQ}/quotes/${PROVIDER}`]: { ...quoteDoc(), createdAt: Timestamp.now() },
    });
    await assertSucceeds(getDocs(query(
      collection(dbAs(env, CUSTOMER), `${REQ}/quotes`),
      where('status', '==', 'sent'),
    )));
    await assertSucceeds(getDoc(doc(dbAs(env, PROVIDER), `${REQ}/quotes/${PROVIDER}`)));
    await assertFails(getDoc(doc(dbAs(env, OTHER_PROVIDER), `${REQ}/quotes/${PROVIDER}`)));
  });
});

describe('accepting a quote', () => {
  beforeEach(async () => {
    await seed(env, {
      [REQ]: storedRequest({ status: 'quoted' }),
      [`${REQ}/quotes/${PROVIDER}`]: { ...quoteDoc({ price: 850 }), createdAt: Timestamp.now() },
    });
  });

  function accept(uid, price = 850) {
    const db = dbAs(env, uid);
    const batch = writeBatch(db);
    batch.update(doc(db, REQ), acceptUpdate({ price }));
    batch.update(doc(db, `${REQ}/quotes/${PROVIDER}`), { status: 'accepted' });
    return batch.commit();
  }

  it('lets the customer accept at the quoted price', async () => {
    await assertSucceeds(accept(CUSTOMER));
  });

  it('rejects accepting at a different price', async () => {
    await assertFails(accept(CUSTOMER, 1));
  });

  it('rejects other users accepting', async () => {
    await assertFails(accept(OTHER_CUSTOMER));
    await assertFails(accept(PROVIDER));
  });
});

describe('job progress', () => {
  const steps = [
    ['accepted', 'on_the_way'],
    ['on_the_way', 'arrived'],
    ['arrived', 'in_progress'],
    ['in_progress', 'provider_completed'],
  ];

  for (const [from, to] of steps) {
    it(`lets the assigned provider move ${from} → ${to}`, async () => {
      await seed(env, { [REQ]: storedRequest({ status: from, providerUid: PROVIDER }) });
      await assertSucceeds(updateDoc(doc(dbAs(env, PROVIDER), REQ), statusUpdate(to)));
    });
  }

  it('rejects skipping a status step', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'accepted', providerUid: PROVIDER }) });
    const db = dbAs(env, PROVIDER);
    await assertFails(updateDoc(doc(db, REQ), statusUpdate('arrived')));
    await assertFails(updateDoc(doc(db, REQ), statusUpdate('provider_completed')));
    await assertFails(updateDoc(doc(db, REQ), statusUpdate('completed')));
  });

  it('rejects moving backwards', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'in_progress', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, PROVIDER), REQ), statusUpdate('arrived')));
  });

  it('rejects other providers and the customer advancing the job', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'accepted', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, OTHER_PROVIDER), REQ), statusUpdate('on_the_way')));
    await assertFails(updateDoc(doc(dbAs(env, CUSTOMER), REQ), statusUpdate('on_the_way')));
  });

  it('lets only the customer confirm completion', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'provider_completed', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, PROVIDER), REQ), statusUpdate('completed')));
    await assertSucceeds(updateDoc(doc(dbAs(env, CUSTOMER), REQ), statusUpdate('completed')));
  });

  it('rejects confirming before the provider marks the job done', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'in_progress', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, CUSTOMER), REQ), statusUpdate('completed')));
  });
});

describe('cash payment', () => {
  it('lets the customer record cash once the job is completed', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'completed', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, PROVIDER), REQ), recordCashUpdate()));
    await assertSucceeds(updateDoc(doc(dbAs(env, CUSTOMER), REQ), recordCashUpdate()));
  });

  it('rejects recording cash before completion', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'provider_completed', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, CUSTOMER), REQ), recordCashUpdate()));
  });

  it('lets only the provider confirm cash received', async () => {
    await seed(env, {
      [REQ]: storedRequest({
        status: 'completed',
        providerUid: PROVIDER,
        paymentMethod: 'cash',
        paymentStatus: 'pending_provider_confirmation',
      }),
    });
    await assertFails(updateDoc(doc(dbAs(env, CUSTOMER), REQ), confirmCashUpdate()));
    await assertFails(updateDoc(doc(dbAs(env, OTHER_PROVIDER), REQ), confirmCashUpdate()));
    await assertSucceeds(updateDoc(doc(dbAs(env, PROVIDER), REQ), confirmCashUpdate()));
  });

  it('rejects marking paid before the customer records payment', async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'completed', providerUid: PROVIDER }) });
    await assertFails(updateDoc(doc(dbAs(env, PROVIDER), REQ), confirmCashUpdate()));
  });
});

describe('chat messages', () => {
  beforeEach(async () => {
    await seed(env, { [REQ]: storedRequest({ status: 'accepted', providerUid: PROVIDER }) });
  });

  it('lets both participants send and read messages', async () => {
    await assertSucceeds(addDoc(collection(dbAs(env, CUSTOMER), `${REQ}/messages`), messageDoc(CUSTOMER)));
    await assertSucceeds(addDoc(collection(dbAs(env, PROVIDER), `${REQ}/messages`), messageDoc(PROVIDER)));
    await assertSucceeds(getDocs(collection(dbAs(env, PROVIDER), `${REQ}/messages`)));
  });

  it('rejects outsiders, spoofed senders and bad lengths', async () => {
    await assertFails(addDoc(collection(dbAs(env, OTHER_PROVIDER), `${REQ}/messages`), messageDoc(OTHER_PROVIDER)));
    await assertFails(getDocs(collection(dbAs(env, OTHER_CUSTOMER), `${REQ}/messages`)));
    await assertFails(addDoc(collection(dbAs(env, CUSTOMER), `${REQ}/messages`), messageDoc(PROVIDER)));
    await assertFails(addDoc(collection(dbAs(env, CUSTOMER), `${REQ}/messages`), messageDoc(CUSTOMER, '')));
    await assertFails(addDoc(collection(dbAs(env, CUSTOMER), `${REQ}/messages`), messageDoc(CUSTOMER, 'x'.repeat(1001))));
  });
});

describe('queries the app runs', () => {
  it('customer: my requests', async () => {
    await seed(env, { [REQ]: storedRequest() });
    await assertSucceeds(getDocs(query(
      collection(dbAs(env, CUSTOMER), 'serviceRequests'),
      where('customerUid', '==', CUSTOMER),
    )));
    await assertFails(getDocs(query(
      collection(dbAs(env, OTHER_CUSTOMER), 'serviceRequests'),
      where('customerUid', '==', CUSTOMER),
    )));
  });

  it('provider: open jobs and my jobs', async () => {
    await seed(env, { [REQ]: storedRequest() });
    const db = dbAs(env, PROVIDER);
    await assertSucceeds(getDocs(query(
      collection(db, 'serviceRequests'),
      where('status', 'in', ['requested', 'quoted']),
      where('providerUid', '==', null),
    )));
    await assertSucceeds(getDocs(query(
      collection(db, 'serviceRequests'),
      where('status', 'in', ['requested', 'quoted']),
      where('providerUid', '==', PROVIDER),
    )));
    await assertSucceeds(getDocs(query(
      collection(db, 'serviceRequests'),
      where('providerUid', '==', PROVIDER),
    )));
  });

  it('customers cannot browse the open job board', async () => {
    await assertFails(getDocs(query(
      collection(dbAs(env, CUSTOMER), 'serviceRequests'),
      where('status', 'in', ['requested', 'quoted']),
      where('providerUid', '==', null),
    )));
  });
});

describe('anything else', () => {
  it('is denied by default', async () => {
    await assertFails(setDoc(doc(dbAs(env, CUSTOMER), 'admin/config'), { open: true }));
    await assertFails(getDoc(doc(dbAs(env, CUSTOMER), 'admin/config')));
  });
});
