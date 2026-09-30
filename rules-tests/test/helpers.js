// Shared setup for the security-rule tests.
//
// The payload builders below mirror, field for field, the writes made by
// lib/core/services/auth_service.dart and
// lib/core/services/marketplace_service.dart. When the Dart code changes the
// shape of a write, update the matching builder here.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  arrayUnion,
  doc,
  serverTimestamp,
  setDoc,
} from 'firebase/firestore';

export { assertFails, assertSucceeds };

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

function hostPort(envName, fallbackPort) {
  const value = process.env[envName];
  if (!value) return { host: '127.0.0.1', port: fallbackPort };
  const [host, port] = value.split(':');
  return { host, port: Number(port) };
}

export async function createEnv() {
  return initializeTestEnvironment({
    projectId: 'demo-fixnear',
    firestore: {
      rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8'),
      ...hostPort('FIRESTORE_EMULATOR_HOST', 8080),
    },
    storage: {
      rules: readFileSync(resolve(root, 'storage.rules'), 'utf8'),
      ...hostPort('FIREBASE_STORAGE_EMULATOR_HOST', 9199),
    },
  });
}

/** Firestore for a signed-in user. */
export function dbAs(env, uid) {
  return env.authenticatedContext(uid).firestore();
}

/** Writes documents with security rules bypassed. */
export async function seed(env, docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [path, data] of Object.entries(docs)) {
      await setDoc(doc(db, path), data);
    }
  });
}

// ---- users & providerProfiles (auth_service.dart) ----

/** AppUser.toMap() as written at registration. */
export function userDoc({ email, name, role }) {
  return {
    email,
    name,
    role,
    phone: null,
    photoUrl: null,
    createdAt: Timestamp.now(),
  };
}

/** Provider profile written in the registration batch. */
export function providerProfileDoc({ name, category = 'Plumbing' }) {
  return {
    name,
    category,
    serviceArea: 'Davao City',
    startingPrice: 500,
    isAvailable: true,
    createdAt: serverTimestamp(),
  };
}

export const CUSTOMER = 'customer-1';
export const OTHER_CUSTOMER = 'customer-2';
export const PROVIDER = 'provider-1';
export const OTHER_PROVIDER = 'provider-2';

/** Registered users used by most tests. */
export function baseUsers() {
  return {
    [`users/${CUSTOMER}`]: userDoc({
      email: 'casey@example.com',
      name: 'Casey Customer',
      role: 'customer',
    }),
    [`users/${OTHER_CUSTOMER}`]: userDoc({
      email: 'olive@example.com',
      name: 'Olive Other',
      role: 'customer',
    }),
    [`users/${PROVIDER}`]: userDoc({
      email: 'pat@example.com',
      name: 'Pat Provider',
      role: 'provider',
    }),
    [`users/${OTHER_PROVIDER}`]: userDoc({
      email: 'quinn@example.com',
      name: 'Quinn Provider',
      role: 'provider',
    }),
    [`providerProfiles/${PROVIDER}`]: {
      ...providerProfileDoc({ name: 'Pat Provider' }),
      createdAt: Timestamp.now(),
    },
    [`providerProfiles/${OTHER_PROVIDER}`]: {
      ...providerProfileDoc({ name: 'Quinn Provider' }),
      createdAt: Timestamp.now(),
    },
  };
}

// ---- serviceRequests (marketplace_service.dart) ----

/** createRequest(). */
export function newRequest({
  customerUid = CUSTOMER,
  providerUid = null,
  providerName = null,
  latitude = 7.0731,
  longitude = 125.6128,
  geohash = latitude == null ? null : 'wc324rs7y',
  locationLabel = 'Home',
} = {}) {
  return {
    customerUid,
    customerName: 'Casey Customer',
    category: 'Plumbing',
    description: 'Fix a leaking kitchen faucet',
    serviceArea: 'Davao City',
    locationLabel,
    latitude,
    longitude,
    geohash,
    providerUid,
    providerName,
    status: 'requested',
    scheduledAt: Timestamp.fromDate(new Date(Date.now() + 86400000)),
    photoUrls: [],
    declinedProviderUids: [],
    paymentStatus: 'unpaid',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

/** updateProviderServiceSettings(). */
export const serviceSettingsUpdate = (overrides = {}) => ({
  category: 'Plumbing',
  serviceArea: 'Lanang, Davao City',
  startingPrice: 600,
  baseLatitude: 7.0996,
  baseLongitude: 125.6317,
  baseGeohash: 'wc326u6nn',
  serviceRadiusKm: 10,
  ...overrides,
});

/** A stored request (server timestamps resolved) in a given state. */
export function storedRequest(overrides = {}) {
  return {
    ...newRequest(),
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

/** sendQuote(): the quote document. */
export function quoteDoc({ providerUid = PROVIDER, price = 850 } = {}) {
  return {
    providerUid,
    providerName: providerUid === PROVIDER ? 'Pat Provider' : 'Quinn Provider',
    price,
    note: 'Parts and labor included',
    status: 'sent',
    createdAt: serverTimestamp(),
  };
}

export const statusUpdate = (status) => ({
  status,
  updatedAt: serverTimestamp(),
});

/** declineRequest(). */
export const declineUpdate = (providerUid) => ({
  declinedProviderUids: arrayUnion(providerUid),
  updatedAt: serverTimestamp(),
});

/** acceptQuote(): the request update. */
export const acceptUpdate = ({ providerUid = PROVIDER, price = 850 } = {}) => ({
  providerUid,
  providerName: providerUid === PROVIDER ? 'Pat Provider' : 'Quinn Provider',
  quotedPrice: price,
  quoteNote: 'Parts and labor included',
  status: 'accepted',
  updatedAt: serverTimestamp(),
});

/** recordCashPayment(). */
export const recordCashUpdate = () => ({
  paymentMethod: 'cash',
  paymentStatus: 'pending_provider_confirmation',
  updatedAt: serverTimestamp(),
});

/** confirmCashPayment(). */
export const confirmCashUpdate = () => ({
  paymentStatus: 'paid',
  paidAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

/** sendMessage(). */
export const messageDoc = (senderUid, text = 'On my way!') => ({
  senderUid,
  senderName: senderUid === CUSTOMER ? 'Casey Customer' : 'Pat Provider',
  text,
  createdAt: serverTimestamp(),
});
