// FixNear push notifications. All functions run in asia-southeast1
// (Singapore), the closest region to Davao.
//
// Firestore triggers must run in the same region as the Firestore database.
// If the database is not in asia-southeast1, change REGION to match it.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from 'firebase-functions/v2/firestore';
import { defineString } from 'firebase-functions/params';
import type { DeliveryContext } from './deliver';
import {
  handleJobCreated,
  handleJobUpdated,
  handleMessageCreated,
  handleQuoteWritten,
} from './handlers';

export const REGION = 'asia-southeast1';

setGlobalOptions({ region: REGION, maxInstances: 10 });
initializeApp();

const appUrl = defineString('APP_URL', {
  default: 'https://fixnear-d5c1c.web.app',
  description: 'Public URL of the FixNear web app, used in web notification links.',
});

function context(): DeliveryContext {
  return { db: getFirestore(), messaging: getMessaging(), appUrl: appUrl.value() };
}

/** New job: the chosen provider, or online providers nearby. */
export const notifyJobPosted = onDocumentCreated('serviceRequests/{requestId}', async (event) => {
  const job = event.data?.data();
  if (job) await handleJobCreated(context(), event.params.requestId, job);
});

/** Status steps → customer. Cash payment recorded/confirmed → other side. */
export const notifyJobUpdated = onDocumentUpdated('serviceRequests/{requestId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (before && after) await handleJobUpdated(context(), event.params.requestId, before, after);
});

/** New or revised quote → customer. Quote accepted → provider. */
export const notifyQuoteWritten = onDocumentWritten(
  'serviceRequests/{requestId}/quotes/{providerId}',
  async (event) => {
    await handleQuoteWritten(
      context(),
      event.params.requestId,
      event.data?.before.data(),
      event.data?.after.data(),
    );
  },
);

/** New chat message → the other participant. */
export const notifyMessageSent = onDocumentCreated(
  'serviceRequests/{requestId}/messages/{messageId}',
  async (event) => {
    const message = event.data?.data();
    if (message) await handleMessageCreated(context(), event.params.requestId, message);
  },
);
