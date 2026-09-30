import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  formatWhen,
  noticesForCancellation,
  noticesForJobUpdate,
  noticesForMessage,
  noticesForNewJob,
  noticesForQuotesNotSelected,
  noticesForQuoteWrite,
  noticesForReopenedJob,
  noticesForReschedule,
} from '../src/events';

const DOWNTOWN = { latitude: 7.0654, longitude: 125.6076 }; // San Pedro Cathedral
const LANANG = { latitude: 7.0996, longitude: 125.6317 }; // ~4.6 km away
const TORIL = { latitude: 7.0187, longitude: 125.4966 }; // ~13 km away

const job = (overrides: Record<string, unknown> = {}) => ({
  customerUid: 'customer-1',
  customerName: 'Casey Customer',
  category: 'Plumbing',
  description: 'Fix a leaking kitchen faucet',
  serviceArea: 'Davao City',
  latitude: DOWNTOWN.latitude,
  longitude: DOWNTOWN.longitude,
  providerUid: null,
  providerName: null,
  status: 'requested',
  paymentStatus: 'unpaid',
  ...overrides,
});

const provider = (uid: string, data: Record<string, unknown>) => ({
  uid,
  data: { isAvailable: true, category: 'Plumbing', serviceArea: 'Davao City', ...data },
});

describe('new jobs', () => {
  const providers = [
    provider('near', { baseLatitude: LANANG.latitude, baseLongitude: LANANG.longitude }),
    provider('far', { baseLatitude: TORIL.latitude, baseLongitude: TORIL.longitude }),
    provider('far-wide', {
      baseLatitude: TORIL.latitude,
      baseLongitude: TORIL.longitude,
      serviceRadiusKm: 20,
    }),
    provider('near-narrow', {
      baseLatitude: LANANG.latitude,
      baseLongitude: LANANG.longitude,
      serviceRadiusKm: 2,
    }),
    provider('offline', {
      isAvailable: false,
      baseLatitude: LANANG.latitude,
      baseLongitude: LANANG.longitude,
    }),
    provider('no-base-same-city', {}),
    provider('no-base-other-city', { serviceArea: 'Tagum City' }),
  ];

  it('notifies online providers whose radius covers the job', () => {
    const notices = noticesForNewJob('r1', job(), providers);
    assert.deepEqual(
      notices.map((n) => n.uid).sort(),
      ['far-wide', 'near', 'no-base-same-city'],
    );
    assert.equal(notices[0].type, 'new_job');
    assert.match(notices[0].title, /New plumbing job near you/);
  });

  it('falls back to the text area for jobs without coordinates', () => {
    const notices = noticesForNewJob(
      'r1',
      job({ latitude: null, longitude: null, serviceArea: 'Buhangin, Davao City' }),
      providers,
    );
    // Every online provider whose area text matches, regardless of distance.
    assert.deepEqual(
      notices.map((n) => n.uid).sort(),
      ['far', 'far-wide', 'near', 'near-narrow', 'no-base-same-city'],
    );
  });

  it('skips providers in other trades and ones who declined', () => {
    const notices = noticesForNewJob(
      'r1',
      job({ declinedProviderUids: ['near'] }),
      [
        ...providers,
        provider('electrician', {
          category: 'Electrical',
          baseLatitude: LANANG.latitude,
          baseLongitude: LANANG.longitude,
        }),
      ],
    );
    assert.deepEqual(notices.map((n) => n.uid).sort(), ['far-wide', 'no-base-same-city']);
  });

  it('sends a direct job only to the chosen provider', () => {
    const notices = noticesForNewJob('r1', job({ providerUid: 'near', providerName: 'N' }), providers);
    assert.equal(notices.length, 1);
    assert.equal(notices[0].uid, 'near');
    assert.equal(notices[0].type, 'direct_job');
    assert.match(notices[0].title, /Casey Customer sent you a job/);
  });
});

describe('quotes', () => {
  const quote = { providerUid: 'p1', providerName: 'Pat Provider', price: 850, note: 'Parts included', status: 'sent' };

  it('tells the customer about a new quote', () => {
    const [notice, ...rest] = noticesForQuoteWrite('r1', job(), undefined, quote);
    assert.equal(rest.length, 0);
    assert.equal(notice.uid, 'customer-1');
    assert.equal(notice.type, 'new_quote');
    assert.equal(notice.title, 'New quote: ₱850 from Pat Provider');
  });

  it('tells the customer when a quote changes', () => {
    const [notice] = noticesForQuoteWrite('r1', job(), quote, { ...quote, price: 1200 });
    assert.equal(notice.type, 'updated_quote');
    assert.equal(notice.title, 'Pat Provider updated their quote to ₱1,200');
  });

  it('stays quiet when a quote is rewritten unchanged', () => {
    assert.deepEqual(noticesForQuoteWrite('r1', job(), quote, { ...quote }), []);
  });

  it('tells the provider when their quote is accepted', () => {
    const [notice] = noticesForQuoteWrite('r1', job(), quote, { ...quote, status: 'accepted' });
    assert.equal(notice.uid, 'p1');
    assert.equal(notice.type, 'quote_accepted');
    assert.match(notice.body, /Casey Customer booked you for Plumbing · Davao City at ₱850/);
  });
});

describe('job updates', () => {
  const booked = job({ status: 'accepted', providerUid: 'p1', providerName: 'Pat Provider', quotedPrice: 850 });

  for (const [status, title] of [
    ['on_the_way', 'Pat Provider is on the way'],
    ['arrived', 'Pat Provider has arrived'],
    ['in_progress', 'Pat Provider started the work'],
    ['provider_completed', 'Pat Provider finished the job'],
  ]) {
    it(`tells the customer: ${status}`, () => {
      const [notice, ...rest] = noticesForJobUpdate('r1', booked, { ...booked, status });
      assert.equal(rest.length, 0);
      assert.equal(notice.uid, 'customer-1');
      assert.equal(notice.title, title);
    });
  }

  it('does not notify for the customer’s own steps or unchanged status', () => {
    assert.deepEqual(noticesForJobUpdate('r1', job(), { ...job(), status: 'cancelled' }), []);
    assert.deepEqual(noticesForJobUpdate('r1', booked, { ...booked, status: 'accepted' }), []);
    assert.deepEqual(
      noticesForJobUpdate('r1', { ...booked, status: 'provider_completed' }, { ...booked, status: 'completed' }),
      [],
    );
  });

  it('tells the provider when cash is recorded, and the customer when confirmed', () => {
    const done = { ...booked, status: 'completed' };
    const recorded = { ...done, paymentStatus: 'pending_provider_confirmation' };
    const [toProvider] = noticesForJobUpdate('r1', done, recorded);
    assert.equal(toProvider.uid, 'p1');
    assert.equal(toProvider.type, 'payment');
    assert.equal(toProvider.title, 'Casey Customer paid ₱850 in cash');

    const [toCustomer] = noticesForJobUpdate('r1', recorded, { ...recorded, paymentStatus: 'paid' });
    assert.equal(toCustomer.uid, 'customer-1');
    assert.equal(toCustomer.body, 'Pat Provider confirmed receiving ₱850.');
  });
});

describe('messages', () => {
  const booked = job({ status: 'accepted', providerUid: 'p1' });

  it('notifies the other participant', () => {
    const [toProvider] = noticesForMessage('r1', booked, { senderUid: 'customer-1', senderName: 'Casey', text: 'Gate code 1234' });
    assert.equal(toProvider.uid, 'p1');
    assert.equal(toProvider.title, 'Casey');
    assert.equal(toProvider.body, 'Gate code 1234');
    const [toCustomer] = noticesForMessage('r1', booked, { senderUid: 'p1', senderName: 'Pat', text: 'On my way' });
    assert.equal(toCustomer.uid, 'customer-1');
  });

  it('truncates long messages and ignores strangers', () => {
    const [notice] = noticesForMessage('r1', booked, { senderUid: 'p1', text: 'x'.repeat(500) });
    assert.equal(notice.body.length, 140);
    assert.deepEqual(noticesForMessage('r1', booked, { senderUid: 'someone', text: 'hi' }), []);
  });
});

describe('reopened jobs', () => {
  const direct = job({ providerUid: 'near', providerName: 'Near Provider' });
  const nearby = [
    provider('near', { baseLatitude: LANANG.latitude, baseLongitude: LANANG.longitude }),
    provider('other', { baseLatitude: LANANG.latitude, baseLongitude: LANANG.longitude }),
  ];

  it('a declined direct job goes to the customer and other nearby providers', () => {
    const after = { ...direct, providerUid: null, providerName: null, declinedProviderUids: ['near'] };
    const notices = noticesForReopenedJob('r1', direct, after, nearby);
    assert.deepEqual(notices.map((n) => [n.uid, n.type]), [
      ['customer-1', 'job_reopened'],
      ['other', 'new_job'],
    ]);
    assert.equal(notices[0].title, "Near Provider can't take this job");
  });

  it('a withdrawal says the provider cannot make it, with their reason', () => {
    const booked = { ...direct, status: 'on_the_way' };
    const after = {
      ...booked,
      status: 'requested',
      providerUid: null,
      providerName: null,
      withdrawReason: 'Car broke down',
      declinedProviderUids: ['near'],
    };
    const [toCustomer] = noticesForReopenedJob('r1', booked, after, nearby);
    assert.equal(toCustomer.title, "Near Provider can't make it");
    assert.match(toCustomer.body, /^Car broke down\. Your plumbing request is open/);
  });

  it('ignores jobs that were never assigned', () => {
    assert.deepEqual(noticesForReopenedJob('r1', job(), job(), nearby), []);
  });
});

describe('quotes not selected, cancellations and rescheduling', () => {
  it('tells providers whose quotes lost', () => {
    const notices = noticesForQuotesNotSelected('r1', job(), ['p2', 'p3']);
    assert.deepEqual(notices.map((n) => n.uid), ['p2', 'p3']);
    assert.equal(notices[0].title, 'Another provider was booked');
  });

  it('tells the booked provider when the customer cancels, with the reason', () => {
    const booked = job({ status: 'accepted', providerUid: 'p1' });
    const [notice, ...rest] = noticesForCancellation(
      'r1',
      booked,
      { ...booked, status: 'cancelled', cancelledBy: 'customer', cancelReason: 'Fixed it myself' },
      ['p2'],
    );
    assert.equal(rest.length, 0);
    assert.equal(notice.uid, 'p1');
    assert.equal(notice.body, 'Plumbing · Davao City: Fixed it myself');
  });

  it('tells quoting providers when an open job is cancelled, but not for system closures', () => {
    const notices = noticesForCancellation('r1', job(), { ...job(), status: 'cancelled' }, ['p2', 'p3']);
    assert.deepEqual(notices.map((n) => n.uid), ['p2', 'p3']);
    assert.deepEqual(
      noticesForCancellation('r1', job(), { ...job(), status: 'cancelled', cancelledBy: 'system' }, ['p2']),
      [],
    );
  });

  it('tells the booked provider about a new time, in Philippine time', () => {
    const booked = job({ status: 'accepted', providerUid: 'p1', scheduledAt: new Date('2026-10-02T01:00:00Z') });
    const moved = { ...booked, scheduledAt: new Date('2026-10-03T01:30:00Z') };
    const [notice] = noticesForReschedule('r1', booked, moved);
    assert.equal(notice.uid, 'p1');
    assert.equal(notice.title, 'New time: Sat, Oct 3, 9:30 AM');
    assert.deepEqual(noticesForReschedule('r1', booked, { ...booked }), []);
    assert.equal(formatWhen(null), 'a new time');
  });
});
