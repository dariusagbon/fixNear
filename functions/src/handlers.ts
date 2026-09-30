// Trigger handlers: load what each rule needs, then deliver.

import { deliver, type DeliveryContext } from './deliver';
import {
  dailyActionFor,
  noticesForCancellation,
  noticesForJobUpdate,
  noticesForMessage,
  noticesForNewJob,
  noticesForQuotesNotSelected,
  noticesForQuoteWrite,
  noticesForReopenedJob,
  noticesForReschedule,
  type Notice,
  type ProviderCandidate,
} from './events';

type Data = Record<string, unknown>;

async function loadJob(ctx: DeliveryContext, requestId: string): Promise<Data | undefined> {
  const snapshot = await ctx.db.collection('serviceRequests').doc(requestId).get();
  return snapshot.data();
}

async function onlineProviders(ctx: DeliveryContext): Promise<ProviderCandidate[]> {
  // Davao-scale: read online providers and filter by distance here.
  const snapshot = await ctx.db.collection('providerProfiles').where('isAvailable', '==', true).get();
  return snapshot.docs.map((doc) => ({ uid: doc.id, data: doc.data() }));
}

export async function handleJobCreated(ctx: DeliveryContext, requestId: string, job: Data) {
  const providers = job.providerUid ? [] : await onlineProviders(ctx);
  return deliver(ctx, noticesForNewJob(requestId, job, providers));
}

const OPEN = ['requested', 'quoted'];

export async function handleJobUpdated(
  ctx: DeliveryContext,
  requestId: string,
  before: Data,
  after: Data,
) {
  const notices: Notice[] = [...noticesForJobUpdate(requestId, before, after)];
  const quotes = ctx.db.collection('serviceRequests').doc(requestId).collection('quotes');

  // Reopened: a direct job was declined, or the booked provider withdrew.
  if (before.providerUid && !after.providerUid && OPEN.includes(String(after.status))) {
    notices.push(...noticesForReopenedJob(requestId, before, after, await onlineProviders(ctx)));
  }

  // Booked: close the other quotes and tell those providers.
  if (OPEN.includes(String(before.status)) && after.status === 'accepted') {
    const open = await quotes.where('status', '==', 'sent').get();
    const losers = open.docs.filter((doc) => doc.id !== after.providerUid);
    await Promise.all(losers.map((doc) => doc.ref.update({ status: 'not_selected' })));
    notices.push(...noticesForQuotesNotSelected(requestId, after, losers.map((doc) => doc.id)));
  }

  // Cancelled by the customer.
  if (after.status === 'cancelled' && before.status !== 'cancelled') {
    const quoting = before.providerUid
      ? []
      : (await quotes.where('status', '==', 'sent').get()).docs.map((doc) => doc.id);
    notices.push(...noticesForCancellation(requestId, before, after, quoting));
  }

  notices.push(...noticesForReschedule(requestId, before, after));
  return deliver(ctx, notices);
}

export async function handleQuoteWritten(
  ctx: DeliveryContext,
  requestId: string,
  before: Data | undefined,
  after: Data | undefined,
) {
  const job = await loadJob(ctx, requestId);
  if (!job) return deliver(ctx, []);
  return deliver(ctx, noticesForQuoteWrite(requestId, job, before, after));
}

export async function handleMessageCreated(ctx: DeliveryContext, requestId: string, message: Data) {
  const job = await loadJob(ctx, requestId);
  if (!job) return deliver(ctx, []);
  return deliver(ctx, noticesForMessage(requestId, job, message));
}

/**
 * A login was deleted (from the app's Delete account, or the console).
 * Removes what the app can't reach and anonymises the person on jobs that
 * stay in the other side's history.
 */
export async function handleUserDeleted(ctx: DeliveryContext, uid: string) {
  const db = ctx.db;
  const user = db.collection('users').doc(uid);
  const tokens = await user.collection('tokens').get();
  await Promise.all(tokens.docs.map((doc) => doc.ref.delete()));
  await user.delete();
  await db.collection('providerProfiles').doc(uid).delete();

  // Quotes that could otherwise still be accepted.
  const quotes = await db.collectionGroup('quotes').where('providerUid', '==', uid).get();
  await Promise.all(
    quotes.docs
      .filter((doc) => doc.data().status === 'sent')
      .map((doc) => doc.ref.update({ status: 'withdrawn' })),
  );

  const requests = db.collection('serviceRequests');
  const asCustomer = await requests.where('customerUid', '==', uid).get();
  await Promise.all(
    asCustomer.docs.map((doc) => {
      const open = ['requested', 'quoted'].includes(String(doc.data().status));
      return doc.ref.update({
        customerName: 'Deleted user',
        ...(open
          ? {
              status: 'cancelled',
              cancelledBy: 'system',
              cancelReason: 'The customer deleted their account.',
            }
          : {}),
      });
    }),
  );
  const asProvider = await requests.where('providerUid', '==', uid).get();
  await Promise.all(asProvider.docs.map((doc) => doc.ref.update({ providerName: 'Deleted provider' })));

  return {
    tokens: tokens.size,
    quotesWithdrawn: quotes.docs.filter((doc) => doc.data().status === 'sent').length,
    jobsAnonymised: asCustomer.size + asProvider.size,
  };
}

/** The daily sweep: expire stale open jobs and send reminders. */
export async function handleDailySweep(ctx: DeliveryContext, now = Date.now()) {
  const statuses = ['requested', 'quoted', 'provider_completed', 'completed'];
  const snapshot = await ctx.db.collection('serviceRequests').where('status', 'in', statuses).get();
  const notices: Notice[] = [];
  let expired = 0;
  for (const doc of snapshot.docs) {
    const action = dailyActionFor(doc.id, doc.data(), now);
    if (!action) continue;
    if (action.expire) {
      await doc.ref.update({
        status: 'cancelled',
        cancelledBy: 'system',
        cancelReason: 'Closed because no provider was booked before the scheduled time.',
        updatedAt: new Date(now),
      });
      expired++;
    }
    if (action.notice) notices.push(action.notice);
  }
  const delivery = await deliver(ctx, notices);
  return { expired, reminders: notices.length - expired, ...delivery };
}
