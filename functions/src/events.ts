// Who gets notified about what. Pure functions, so every rule is unit-tested
// without Firebase. The trigger handlers load data and call these.

import { distanceKm, readLatLng, serviceAreasMatch, serviceRadiusKm } from './geo';

export type NoticeType =
  | 'new_job'
  | 'direct_job'
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
  return providers
    .filter(
      ({ uid, data }) =>
        data.isAvailable === true && uid !== job.customerUid && isNearby(job, data),
    )
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
