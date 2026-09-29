// The full job loop, with security rules enforced, each step performed by
// the user who does it in the app:
// post → quote → book → on_the_way → arrived → in_progress →
// provider_completed → completed → cash recorded → cash confirmed.

import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  addDoc,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import {
  CUSTOMER,
  OTHER_PROVIDER,
  PROVIDER,
  acceptUpdate,
  assertSucceeds,
  baseUsers,
  confirmCashUpdate,
  createEnv,
  dbAs,
  messageDoc,
  newRequest,
  quoteDoc,
  recordCashUpdate,
  seed,
  statusUpdate,
} from './helpers.js';

let env;
before(async () => {
  env = await createEnv();
  await env.clearFirestore();
  await seed(env, baseUsers());
});
after(async () => {
  await env.cleanup();
});

describe('full job loop', () => {
  const REQ = 'serviceRequests/loop-1';
  // One Firestore instance per user, so batches and references match.
  const dbs = {};
  const as = (uid) => (dbs[uid] ??= dbAs(env, uid));
  const customer = () => as(CUSTOMER);
  const provider = () => as(PROVIDER);

  async function current() {
    return (await getDoc(doc(customer(), REQ))).data();
  }

  it('runs from posting to cash confirmed', async () => {
    // 1. Customer posts a job with a pinned location.
    await assertSucceeds(setDoc(doc(customer(), REQ), newRequest()));
    assert.equal((await current()).status, 'requested');

    // 2. The job shows on the provider board; two providers quote.
    const board = await getDocs(query(
      collection(provider(), 'serviceRequests'),
      where('status', 'in', ['requested', 'quoted']),
      where('providerUid', '==', null),
    ));
    assert.deepEqual(board.docs.map((d) => d.id), ['loop-1']);

    for (const [uid, price] of [[PROVIDER, 850], [OTHER_PROVIDER, 990]]) {
      const db = as(uid);
      const batch = writeBatch(db);
      batch.set(doc(db, `${REQ}/quotes/${uid}`), quoteDoc({ providerUid: uid, price }));
      batch.update(doc(db, REQ), statusUpdate('quoted'));
      await assertSucceeds(batch.commit());
    }
    assert.equal((await current()).status, 'quoted');

    // 3. Customer compares quotes and books the cheaper one.
    const quotes = await getDocs(query(
      collection(customer(), `${REQ}/quotes`),
      where('status', '==', 'sent'),
    ));
    assert.equal(quotes.size, 2);
    const book = writeBatch(customer());
    book.update(doc(customer(), REQ), acceptUpdate({ price: 850 }));
    book.update(doc(customer(), `${REQ}/quotes/${PROVIDER}`), { status: 'accepted' });
    await assertSucceeds(book.commit());
    let job = await current();
    assert.equal(job.status, 'accepted');
    assert.equal(job.providerUid, PROVIDER);
    assert.equal(job.quotedPrice, 850);

    // Both sides can now chat.
    await assertSucceeds(addDoc(collection(customer(), `${REQ}/messages`), messageDoc(CUSTOMER, 'Gate code is 1234')));
    await assertSucceeds(addDoc(collection(provider(), `${REQ}/messages`), messageDoc(PROVIDER)));

    // 4. Provider moves through every status step.
    for (const status of ['on_the_way', 'arrived', 'in_progress', 'provider_completed']) {
      await assertSucceeds(updateDoc(doc(provider(), REQ), statusUpdate(status)));
      assert.equal((await current()).status, status);
    }

    // 5. Customer confirms the work is done.
    await assertSucceeds(updateDoc(doc(customer(), REQ), statusUpdate('completed')));
    assert.equal((await current()).status, 'completed');

    // 6. Customer records cash; provider confirms receipt.
    await assertSucceeds(updateDoc(doc(customer(), REQ), recordCashUpdate()));
    assert.equal((await current()).paymentStatus, 'pending_provider_confirmation');
    await assertSucceeds(updateDoc(doc(provider(), REQ), confirmCashUpdate()));
    job = await current();
    assert.equal(job.paymentStatus, 'paid');
    assert.ok(job.paidAt);

    // The paid job appears in the provider's jobs.
    const mine = await getDocs(query(
      collection(provider(), 'serviceRequests'),
      where('providerUid', '==', PROVIDER),
    ));
    assert.deepEqual(mine.docs.map((d) => d.data().paymentStatus), ['paid']);
  });
});
