// Who gets notified about what. Pure functions, so every rule is unit-tested
// without Firebase. The trigger handlers load data and call these.

import { distanceKm, readLatLng, serviceAreasMatch, serviceRadiusKm } from './geo';

export type NoticeType =
  | 'new_job'
  | 'direct_job'
  | 'job_reopened'
  | 'quote_not_selected'
  | 'cancelled'
  | 'rescheduled'
  | 'reminder'
  | 'new_quote'
  | 'updated_quote'
  | 'quote_accepted'
  | 'status'
  | 'payment'
  | 'message';

/** One notification for one user about one job. */
export interface Notice {
  uid: string;
  type: NoticeType;
  requestId: string;
  title: string;
  body: string;
}

type Data = Record<string, unknown>;

const str = (value: unknown, fallback = ''): string =>
  typeof value === 'string' && value.trim() ? value.trim() : fallback;

const peso = (value: unknown): string =>
  typeof value === 'number' ? `₱${Math.round(value).toLocaleString('en-US')}` : '';

const truncate = (text: string, max: number): string =>
  text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;

/** Short description used in bodies, e.g. "Plumbing · Davao City". */
function jobSummary(job: Data): string {
  return [str(job.category, 'Service'), str(job.serviceArea)].filter(Boolean).join(' · ');
}

export interface ProviderCandidate {
  uid: string;
  data: Data;
}

/**
 * Whether an online provider should hear about a new broadcast job: within
 * their service radius when both sides have coordinates, otherwise when the
 * text service areas match.
 */
export function isNearby(job: Data, provider: Data): boolean {
  const jobPoint = readLatLng(job.latitude, job.longitude);
  const base = readLatLng(provider.baseLatitude, provider.baseLongitude);
  if (jobPoint && base) {
    return distanceKm(jobPoint, base) <= serviceRadiusKm(provider.serviceRadiusKm);
  }
  return serviceAreasMatch(job.serviceArea, provider.serviceArea);
}

const sameCategory = (a: unknown, b: unknown) =>
  typeof a === 'string' && typeof b === 'string' && a.trim().toLowerCase() === b.trim().toLowerCase();

const declined = (job: Data): string[] =>
  Array.isArray(job.declinedProviderUids)
    ? job.declinedProviderUids.filter((uid): uid is string => typeof uid === 'string')
    : [];

/** Online providers in the job's trade, nearby, who haven't declined it. */
function nearbyProviders(job: Data, providers: ProviderCandidate[]): ProviderCandidate[] {
  const skip = new Set(declined(job));
  return providers.filter(
    ({ uid, data }) =>
      data.isAvailable === true &&
      uid !== job.customerUid &&
      !skip.has(uid) &&
      sameCategory(job.category, data.category) &&
      isNearby(job, data),
  );
}

/** "Thu, Oct 2, 9:30 AM" in Philippine time. */
export function formatWhen(value: unknown): string {
  const date =
    value && typeof (value as { toDate?: () => Date }).toDate === 'function'
      ? (value as { toDate: () => Date }).toDate()
      : value instanceof Date
        ? value
        : null;
  if (!date) return 'a new time';
  return date.toLocaleString('en-US', {
    timeZone: 'Asia/Manila',
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/** A job was posted: tell the chosen provider, or online providers nearby. */
export function noticesForNewJob(
  requestId: string,
  job: Data,
  providers: ProviderCandidate[],
): Notice[] {
  if (job.status !== 'requested') return [];
  const summary = jobSummary(job);
  const direct = str(job.providerUid);
  if (direct) {
    return [
      {
        uid: direct,
        type: 'direct_job',
        requestId,
        title: `${str(job.customerName, 'A customer')} sent you a job`,
        body: `${summary}. Send a quote.`,
      },
    ];
  }
  return nearbyProviders(job, providers)
    .map(({ uid }) => ({
      uid,
      type: 'new_job' as const,
      requestId,
      title: `New ${str(job.category, 'service').toLowerCase()} job near you`,
      body: truncate(`${summary}: ${str(job.description)}`, 140),
    }));
}

/** A quote document was created or changed. */
export function noticesForQuoteWrite(
  requestId: string,
  job: Data,
  before: Data | undefined,
  after: Data | undefined,
): Notice[] {
  if (!after) return [];
  const providerName = str(after.providerName, 'A provider');
  const customerUid = str(job.customerUid);

  if (after.status === 'sent' && customerUid) {
    if (!before) {
      return [
        {
          uid: customerUid,
          type: 'new_quote',
          requestId,
          title: `New quote: ${peso(after.price)} from ${providerName}`,
          body: `${jobSummary(job)}. Compare quotes and book.`,
        },
      ];
    }
    if (before.status === 'sent' && (before.price !== after.price || before.note !== after.note)) {
      return [
        {
          uid: customerUid,
          type: 'updated_quote',
          requestId,
          title: `${providerName} updated their quote to ${peso(after.price)}`,
          body: `${jobSummary(job)}. Compare quotes and book.`,
        },
      ];
    }
  }

  if (before?.status === 'sent' && after.status === 'accepted') {
    const providerUid = str(after.providerUid);
    if (!providerUid) return [];
    return [
      {
        uid: providerUid,
        type: 'quote_accepted',
        requestId,
        title: 'Your quote was accepted',
        body: `${str(job.customerName, 'The customer')} booked you for ${jobSummary(job)} at ${peso(after.price)}.`,
      },
    ];
  }
  return [];
}

const STATUS_MESSAGES: Record<string, (provider: string) => [string, string]> = {
  on_the_way: (p) => [`${p} is on the way`, 'Track the job in FixNear.'],
  arrived: (p) => [`${p} has arrived`, 'Your provider is at the location.'],
  in_progress: (p) => [`${p} started the work`, 'The job is in progress.'],
  provider_completed: (p) => [
    `${p} finished the job`,
    'Check the work and confirm it is complete.',
  ],
};

/** A job document changed: status steps and cash payment. */
export function noticesForJobUpdate(requestId: string, before: Data, after: Data): Notice[] {
  const notices: Notice[] = [];
  const customerUid = str(after.customerUid);
  const providerUid = str(after.providerUid);
  const providerName = str(after.providerName, 'Your provider');
  const customerName = str(after.customerName, 'The customer');

  // Status steps the provider makes; tell the customer. ("quoted" is covered
  // by the quote notification; "accepted" and "completed" are the customer's
  // own actions.)
  const status = str(after.status);
  if (status !== before.status && STATUS_MESSAGES[status] && customerUid) {
    const [title, body] = STATUS_MESSAGES[status](providerName);
    notices.push({ uid: customerUid, type: 'status', requestId, title, body });
  }

  // Payments: tell the other side what happened.
  if (after.paymentStatus !== before.paymentStatus) {
    const amount = peso(after.quotedPrice);
    if (after.paymentStatus === 'pending_provider_confirmation' && providerUid) {
      notices.push({
        uid: providerUid,
        type: 'payment',
        requestId,
        title: amount ? `${customerName} paid ${amount} in cash` : `${customerName} paid in cash`,
        body: 'Confirm in FixNear once you have received it.',
      });
    }
    if (after.paymentStatus === 'paid' && customerUid) {
      notices.push({
        uid: customerUid,
        type: 'payment',
        requestId,
        title: 'Payment confirmed',
        body: `${providerName} confirmed receiving ${amount || 'your cash payment'}.`,
      });
    }
  }
  return notices;
}

/**
 * A job went back to being open: a provider declined a job sent to them,
 * or the booked provider withdrew. Tell the customer, and offer the job to
 * nearby providers.
 */
export function noticesForReopenedJob(
  requestId: string,
  before: Data,
  after: Data,
  providers: ProviderCandidate[],
): Notice[] {
  const wasAssigned = str(before.providerUid);
  const open = after.status === 'requested' || after.status === 'quoted';
  if (!wasAssigned || str(after.providerUid) || !open) return [];

  const provider = str(before.providerName, 'The provider');
  const withdrew = before.status !== 'requested' && before.status !== 'quoted';
  const reason = str(after.withdrawReason);
  const notices: Notice[] = [];
  const customerUid = str(after.customerUid);
  if (customerUid) {
    notices.push({
      uid: customerUid,
      type: 'job_reopened',
      requestId,
      title: withdrew ? `${provider} can't make it` : `${provider} can't take this job`,
      body: truncate(
        `${reason ? `${reason}. ` : ''}Your ${str(after.category, 'job').toLowerCase()} request is open to other providers near you.`,
        160,
      ),
    });
  }
  for (const { uid } of nearbyProviders(after, providers)) {
    notices.push({
      uid,
      type: 'new_job',
      requestId,
      title: `New ${str(after.category, 'service').toLowerCase()} job near you`,
      body: truncate(`${jobSummary(after)}: ${str(after.description)}`, 140),
    });
  }
  return notices;
}

/**
 * The customer accepted one quote: tell the other providers who quoted.
 * [losers] are the providerUids of quotes still marked "sent".
 */
export function noticesForQuotesNotSelected(requestId: string, job: Data, losers: string[]): Notice[] {
  return losers.map((uid) => ({
    uid,
    type: 'quote_not_selected' as const,
    requestId,
    title: 'Another provider was booked',
    body: `${str(job.customerName, 'The customer')} chose a different quote for ${jobSummary(job)}.`,
  }));
}

/**
 * The customer cancelled. Tell the booked provider, or, for an open job,
 * the providers who had quoted.
 */
export function noticesForCancellation(
  requestId: string,
  before: Data,
  after: Data,
  quotingProviders: string[],
): Notice[] {
  if (after.status !== 'cancelled' || before.status === 'cancelled') return [];
  if (after.cancelledBy === 'system') return [];
  const reason = str(after.cancelReason);
  const recipients = str(before.providerUid)
    ? [str(before.providerUid)]
    : quotingProviders;
  return [...new Set(recipients)].map((uid) => ({
    uid,
    type: 'cancelled' as const,
    requestId,
    title: `${str(after.customerName, 'The customer')} cancelled the job`,
    body: truncate(`${jobSummary(after)}${reason ? `: ${reason}` : '.'}`, 160),
  }));
}

/** The customer moved a booked job: tell the provider the new time. */
export function noticesForReschedule(requestId: string, before: Data, after: Data): Notice[] {
  const providerUid = str(after.providerUid);
  const moved =
    JSON.stringify(before.scheduledAt ?? null) !== JSON.stringify(after.scheduledAt ?? null);
  if (!moved || !providerUid || after.status !== 'accepted') return [];
  return [
    {
      uid: providerUid,
      type: 'rescheduled',
      requestId,
      title: `New time: ${formatWhen(after.scheduledAt)}`,
      body: `${str(after.customerName, 'The customer')} moved ${jobSummary(after)}.`,
    },
  ];
}

/** A chat message was sent: tell the other participant. */
export function noticesForMessage(requestId: string, job: Data, message: Data): Notice[] {
  const sender = str(message.senderUid);
  const customerUid = str(job.customerUid);
  const providerUid = str(job.providerUid);
  const recipient = sender === customerUid ? providerUid : sender === providerUid ? customerUid : '';
  if (!recipient) return [];
  return [
    {
      uid: recipient,
      type: 'message',
      requestId,
      title: str(message.senderName, 'New message'),
      body: truncate(str(message.text), 140),
    },
  ];
}

const DAY_MS = 24 * 60 * 60 * 1000;

const millis = (value: unknown): number | null => {
  if (value && typeof (value as { toMillis?: () => number }).toMillis === 'function') {
    return (value as { toMillis: () => number }).toMillis();
  }
  return value instanceof Date ? value.getTime() : null;
};

export interface DailyAction {
  requestId: string;
  /** Close the job as expired (system cancellation). */
  expire: boolean;
  notice: Notice | null;
}

/**
 * The daily sweep. For each job:
 * - open more than a day past its scheduled time: close it and tell the
 *   customer;
 * - marked done by the provider over 2 days ago: remind the customer;
 * - cash recorded over 2 days ago: remind the provider.
 */
export function dailyActionFor(requestId: string, job: Data, now: number): DailyAction | null {
  const status = str(job.status);
  const scheduled = millis(job.scheduledAt);
  const updated = millis(job.updatedAt);
  const customerUid = str(job.customerUid);
  const providerUid = str(job.providerUid);

  if ((status === 'requested' || status === 'quoted') && scheduled !== null && now - scheduled > DAY_MS) {
    return {
      requestId,
      expire: true,
      notice: customerUid
        ? {
            uid: customerUid,
            type: 'cancelled',
            requestId,
            title: `Your ${str(job.category, 'service').toLowerCase()} request expired`,
            body: 'No provider was booked before the scheduled time. Post it again with a new date.',
          }
        : null,
    };
  }
  if (status === 'provider_completed' && updated !== null && now - updated > 2 * DAY_MS && customerUid) {
    return {
      requestId,
      expire: false,
      notice: {
        uid: customerUid,
        type: 'reminder',
        requestId,
        title: 'Please confirm your job is complete',
        body: `${str(job.providerName, 'Your provider')} marked ${jobSummary(job)} as done.`,
      },
    };
  }
  if (
    status === 'completed' &&
    job.paymentStatus === 'pending_provider_confirmation' &&
    updated !== null &&
    now - updated > 2 * DAY_MS &&
    providerUid
  ) {
    return {
      requestId,
      expire: false,
      notice: {
        uid: providerUid,
        type: 'reminder',
        requestId,
        title: 'Confirm the cash payment',
        body: `${str(job.customerName, 'The customer')} recorded paying ${peso(job.quotedPrice) || 'cash'} for ${jobSummary(job)}.`,
      },
    };
  }
  return null;
}
