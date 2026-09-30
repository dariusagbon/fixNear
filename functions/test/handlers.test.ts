// Handler tests against the Firestore emulator, with FCM replaced by a fake
// that records what would be sent. Run with `npm test`.

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import type { BatchResponse, MulticastMessage } from 'firebase-admin/messaging';
import type { DeliveryContext, MessagingLike } from '../src/deliver';
import {
  handleJobCreated,
  handleJobUpdated,
  handleMessageCreated,
  handleQuoteWritten,
  handleUserDeleted,
} from '../src/handlers';

class FakeMessaging implements MessagingLike {
  sent: MulticastMessage[] = [];
  deadTokens = new Set<string>();

  async sendEachForMulticast(message: MulticastMessage): Promise<BatchResponse> {
    this.sent.push(message);
    const responses = message.tokens.map((token) =>
      this.deadTokens.has(token)
        ? {
            success: false,
            error: { code: 'messaging/registration-token-not-registered' },
          }
        : { success: true, messageId: `m-${token}` },
    );
    const successCount = responses.filter((r) => r.success).length;
    return {
      responses,
      successCount,
      failureCount: responses.length - successCount,
    } as BatchResponse;
  }

  /** Tokens each message went to, in order. */
  tokens() {
    return this.sent.map((m) => [...m.tokens].sort());
  }
}

let app: App;
let db: Firestore;
let messaging: FakeMessaging;
let ctx: DeliveryContext;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Run via `npm test` (Firestore emulator).');
  app = initializeApp({ projectId: 'demo-fixnear' }, 'handlers-test');
  db = getFirestore(app);
});
after(async () => {
  await deleteApp(app);
});

async function clear() {
  const res = await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-fixnear/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.ok(res.ok);
}

async function addToken(uid: string, token: string) {
  await db.doc(`users/${uid}/tokens/${token}`).set({ token, platform: 'android' });
}

beforeEach(async () => {
  await clear();
  messaging = new FakeMessaging();
  ctx = { db, messaging, appUrl: 'https://fixnear.example/' };
  await db.doc('providerProfiles/near').set({
    name: 'Near Provider',
    category: 'Plumbing',
    serviceArea: 'Davao City',
    isAvailable: true,
    baseLatitude: 7.0996,
    baseLongitude: 125.6317,
    serviceRadiusKm: 10,
  });
  await db.doc('providerProfiles/far').set({
    name: 'Far Provider',
    category: 'Plumbing',
    serviceArea: 'Davao City',
    isAvailable: true,
    baseLatitude: 7.0187,
    baseLongitude: 125.4966,
    serviceRadiusKm: 5,
  });
  await db.doc('providerProfiles/offline').set({
    name: 'Offline Provider',
    category: 'Plumbing',
    serviceArea: 'Davao City',
    isAvailable: false,
    baseLatitude: 7.0996,
    baseLongitude: 125.6317,
  });
  await addToken('near', 'near-phone');
  await addToken('near', 'near-laptop');
  await addToken('far', 'far-phone');
  await addToken('offline', 'offline-phone');
  await addToken('customer-1', 'customer-phone');
});

const JOB = {
  customerUid: 'customer-1',
  customerName: 'Casey Customer',
  category: 'Plumbing',
  description: 'Fix a leaking faucet',
  serviceArea: 'Davao City',
  latitude: 7.0654,
  longitude: 125.6076,
  providerUid: null,
  status: 'requested',
  paymentStatus: 'unpaid',
};

describe('handlers', () => {
  it('sends a new job to every device of nearby online providers only', async () => {
    const result = await handleJobCreated(ctx, 'job-1', JOB);
    assert.deepEqual(messaging.tokens(), [['near-laptop', 'near-phone']]);
    assert.equal(result.sent, 2);

    const [message] = messaging.sent;
    assert.deepEqual(message.data, { requestId: 'job-1', type: 'new_job' });
    assert.equal(message.android?.notification?.channelId, 'job_updates');
    assert.equal(message.webpush?.fcmOptions?.link, 'https://fixnear.example/?job=job-1');
  });

  it('sends a direct job only to that provider', async () => {
    await handleJobCreated(ctx, 'job-2', { ...JOB, providerUid: 'far', providerName: 'Far Provider' });
    assert.deepEqual(messaging.tokens(), [['far-phone']]);
  });

  it('removes tokens FCM says are no longer registered', async () => {
    messaging.deadTokens.add('near-laptop');
    const result = await handleJobCreated(ctx, 'job-3', JOB);
    assert.equal(result.removedTokens, 1);
    const remaining = await db.collection('users/near/tokens').get();
    assert.deepEqual(remaining.docs.map((d) => d.id), ['near-phone']);
  });

  it('skips users with no registered devices', async () => {
    await db.doc('serviceRequests/job-4').set(JOB);
    const result = await handleQuoteWritten(ctx, 'job-4', undefined, {
      providerUid: 'no-device',
      providerName: 'Quiet',
      price: 500,
      note: 'x',
      status: 'sent',
    });
    assert.deepEqual(messaging.tokens(), [['customer-phone']]);
    assert.equal(result.sent, 1);
    // Accepting tells the provider, who has no devices: nothing is sent.
    messaging.sent = [];
    await handleQuoteWritten(
      ctx,
      'job-4',
      { providerUid: 'no-device', status: 'sent', price: 500 },
      { providerUid: 'no-device', status: 'accepted', price: 500 },
    );
    assert.deepEqual(messaging.sent, []);
  });

  it('tells the customer about status steps and chat from the provider', async () => {
    const booked = { ...JOB, status: 'accepted', providerUid: 'near', providerName: 'Near Provider' };
    await db.doc('serviceRequests/job-5').set(booked);
    await handleJobUpdated(ctx, 'job-5', booked, { ...booked, status: 'on_the_way' });
    await handleMessageCreated(ctx, 'job-5', { senderUid: 'near', senderName: 'Near Provider', text: 'Almost there' });
    await handleMessageCreated(ctx, 'job-5', { senderUid: 'customer-1', senderName: 'Casey', text: 'Thanks' });
    assert.deepEqual(messaging.tokens(), [
      ['customer-phone'],
      ['customer-phone'],
      ['near-laptop', 'near-phone'],
    ]);
    assert.equal(messaging.sent[0].notification?.title, 'Near Provider is on the way');
    assert.equal(messaging.sent[2].android?.notification?.tag, 'job-5-chat');
  });

  it('closes losing quotes when one is accepted and tells those providers', async () => {
    const quoted = { ...JOB, status: 'quoted' };
    await db.doc('serviceRequests/job-6').set(quoted);
    for (const uid of ['near', 'far']) {
      await db.doc(`serviceRequests/job-6/quotes/${uid}`).set({ providerUid: uid, price: 800, status: 'sent' });
    }
    const booked = { ...quoted, status: 'accepted', providerUid: 'near', providerName: 'Near Provider' };
    await db.doc('serviceRequests/job-6/quotes/near').update({ status: 'accepted' });
    await handleJobUpdated(ctx, 'job-6', quoted, booked);

    const far = (await db.doc('serviceRequests/job-6/quotes/far').get()).data();
    const near = (await db.doc('serviceRequests/job-6/quotes/near').get()).data();
    assert.equal(far?.status, 'not_selected');
    assert.equal(near?.status, 'accepted');
    assert.deepEqual(messaging.tokens(), [['far-phone']]);
    assert.equal(messaging.sent[0].data?.type, 'quote_not_selected');
  });

  it('reopens a declined direct job to the customer and nearby providers', async () => {
    const direct = { ...JOB, providerUid: 'far', providerName: 'Far Provider' };
    const reopened = { ...direct, providerUid: null, providerName: null, declinedProviderUids: ['far'] };
    await handleJobUpdated(ctx, 'job-7', direct, reopened);
    assert.deepEqual(messaging.tokens(), [['customer-phone'], ['near-laptop', 'near-phone']]);
    assert.deepEqual(messaging.sent.map((m) => m.data?.type), ['job_reopened', 'new_job']);
  });

  it('tells quoting providers when an open job is cancelled', async () => {
    const quoted = { ...JOB, status: 'quoted' };
    await db.doc('serviceRequests/job-8/quotes/far').set({ providerUid: 'far', price: 800, status: 'sent' });
    await handleJobUpdated(ctx, 'job-8', quoted, { ...quoted, status: 'cancelled', cancelledBy: 'customer' });
    assert.deepEqual(messaging.tokens(), [['far-phone']]);
  });

  it('cleans up after a deleted account', async () => {
    // "near" deletes their account: they have a listing, tokens, an open
    // quote, and a finished job.
    await db.doc('users/near').set({ name: 'Near Provider', role: 'provider' });
    await db.doc('serviceRequests/open-1').set({ ...JOB, status: 'quoted' });
    await db.doc('serviceRequests/open-1/quotes/near').set({ providerUid: 'near', price: 900, status: 'sent' });
    await db.doc('serviceRequests/done-1').set({
      ...JOB, status: 'completed', providerUid: 'near', providerName: 'Near Provider',
    });

    const result = await handleUserDeleted(ctx, 'near');
    assert.equal(result.tokens, 2);
    assert.equal(result.quotesWithdrawn, 1);
    assert.equal((await db.doc('users/near').get()).exists, false);
    assert.equal((await db.doc('providerProfiles/near').get()).exists, false);
    assert.equal((await db.collection('users/near/tokens').get()).size, 0);
    assert.equal((await db.doc('serviceRequests/open-1/quotes/near').get()).data()?.status, 'withdrawn');
    assert.equal((await db.doc('serviceRequests/done-1').get()).data()?.providerName, 'Deleted provider');
  });

  it('cancels a deleted customer’s open jobs and keeps finished ones', async () => {
    await db.doc('serviceRequests/c-open').set({ ...JOB, status: 'requested' });
    await db.doc('serviceRequests/c-done').set({ ...JOB, status: 'completed', providerUid: 'near' });
    await handleUserDeleted(ctx, 'customer-1');
    const open = (await db.doc('serviceRequests/c-open').get()).data();
    const done = (await db.doc('serviceRequests/c-done').get()).data();
    assert.equal(open?.status, 'cancelled');
    assert.equal(open?.cancelledBy, 'system');
    assert.equal(open?.customerName, 'Deleted user');
    assert.equal(done?.status, 'completed');
    assert.equal(done?.customerName, 'Deleted user');
  });

  it('does nothing for a quote on a job that no longer exists', async () => {
    const result = await handleQuoteWritten(ctx, 'missing', undefined, { status: 'sent', providerUid: 'near' });
    assert.equal(result.sent, 0);
    assert.deepEqual(messaging.sent, []);
  });
});

describe('deployment settings', () => {
  it('deploys every function to asia-southeast1', async () => {
    process.env.GCLOUD_PROJECT ??= 'demo-fixnear';
    const fns = (await import('../src/index')) as Record<string, unknown>;
    const exported = Object.entries(fns).filter(
      ([, value]) => typeof value === 'function' && '__endpoint' in (value as object),
    );
    assert.deepEqual(
      exported.map(([name]) => name).sort(),
      ['cleanUpDeletedUser', 'notifyJobPosted', 'notifyJobUpdated', 'notifyMessageSent', 'notifyQuoteWritten'],
    );
    for (const [name, fn] of exported) {
      const endpoint = (fn as { __endpoint: { region?: string[] } }).__endpoint;
      assert.deepEqual(endpoint.region, ['asia-southeast1'], name);
    }
  });
});
