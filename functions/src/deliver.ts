// Sends notices to every registered device of each recipient, and removes
// tokens FCM reports as dead.

import type { Firestore } from 'firebase-admin/firestore';
import type { BatchResponse, MulticastMessage } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import type { Notice } from './events';

/** The part of firebase-admin's Messaging we use (a fake in tests). */
export interface MessagingLike {
  sendEachForMulticast(message: MulticastMessage): Promise<BatchResponse>;
}

export interface DeliveryContext {
  db: Firestore;
  messaging: MessagingLike;
  /** Public URL of the web app, used for web notification links. */
  appUrl: string;
}

const FCM_BATCH_LIMIT = 500;

const DEAD_TOKEN_ERRORS = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

export function buildMessage(notice: Notice, tokens: string[], appUrl: string): MulticastMessage {
  const base = appUrl.replace(/\/+$/, '');
  return {
    tokens,
    notification: { title: notice.title, body: notice.body },
    data: { requestId: notice.requestId, type: notice.type },
    android: {
      priority: 'high',
      notification: {
        channelId: 'job_updates',
        // Newer updates about the same job replace older ones; chat
        // messages stack separately.
        tag: notice.type === 'message' ? `${notice.requestId}-chat` : notice.requestId,
      },
    },
    apns: {
      payload: { aps: { sound: 'default', threadId: notice.requestId } },
    },
    webpush: {
      notification: { icon: `${base}/icons/Icon-192.png`, tag: notice.requestId },
      fcmOptions: { link: `${base}/?job=${encodeURIComponent(notice.requestId)}` },
    },
  };
}

export interface DeliveryResult {
  sent: number;
  failed: number;
  removedTokens: number;
}

export async function deliver(ctx: DeliveryContext, notices: Notice[]): Promise<DeliveryResult> {
  const result: DeliveryResult = { sent: 0, failed: 0, removedTokens: 0 };
  for (const notice of notices) {
    const tokensRef = ctx.db.collection('users').doc(notice.uid).collection('tokens');
    const snapshot = await tokensRef.get();
    const tokens = snapshot.docs.map((doc) => doc.id);
    for (let start = 0; start < tokens.length; start += FCM_BATCH_LIMIT) {
      const batch = tokens.slice(start, start + FCM_BATCH_LIMIT);
      const response = await ctx.messaging.sendEachForMulticast(
        buildMessage(notice, batch, ctx.appUrl),
      );
      result.sent += response.successCount;
      result.failed += response.failureCount;
      const dead = response.responses
        .map((r, i) => (!r.success && r.error && DEAD_TOKEN_ERRORS.has(r.error.code) ? batch[i] : null))
        .filter((token): token is string => token !== null);
      await Promise.all(dead.map((token) => tokensRef.doc(token).delete()));
      result.removedTokens += dead.length;
    }
  }
  if (notices.length > 0) {
    logger.info('Delivered notifications', {
      notices: notices.map((n) => ({ uid: n.uid, type: n.type, requestId: n.requestId })),
      ...result,
    });
  }
  return result;
}
