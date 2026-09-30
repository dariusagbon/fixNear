// Trigger handlers: load what each rule needs, then deliver.

import { deliver, type DeliveryContext } from './deliver';
import {
  noticesForJobUpdate,
  noticesForMessage,
  noticesForNewJob,
  noticesForQuoteWrite,
  type ProviderCandidate,
} from './events';

type Data = Record<string, unknown>;

async function loadJob(ctx: DeliveryContext, requestId: string): Promise<Data | undefined> {
  const snapshot = await ctx.db.collection('serviceRequests').doc(requestId).get();
  return snapshot.data();
}

export async function handleJobCreated(ctx: DeliveryContext, requestId: string, job: Data) {
  let providers: ProviderCandidate[] = [];
  if (!job.providerUid) {
    // Davao-scale: read online providers and filter by distance here.
    const snapshot = await ctx.db
      .collection('providerProfiles')
      .where('isAvailable', '==', true)
      .get();
    providers = snapshot.docs.map((doc) => ({ uid: doc.id, data: doc.data() }));
  }
  return deliver(ctx, noticesForNewJob(requestId, job, providers));
}

export async function handleJobUpdated(
  ctx: DeliveryContext,
  requestId: string,
  before: Data,
  after: Data,
) {
  return deliver(ctx, noticesForJobUpdate(requestId, before, after));
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
