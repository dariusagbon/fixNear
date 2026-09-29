// FixNear keeps photos on Cloudinary, so the Storage bucket is locked.

import { after, before, describe, it } from 'node:test';
import { getBytes, ref, uploadString } from 'firebase/storage';
import { assertFails, createEnv } from './helpers.js';

let env;
before(async () => {
  env = await createEnv();
});
after(async () => {
  await env.cleanup();
});

describe('storage', () => {
  it('denies uploads and downloads, even for signed-in users', async () => {
    const storage = env.authenticatedContext('customer-1').storage();
    await assertFails(uploadString(ref(storage, 'avatars/customer-1.txt'), 'hi'));
    await assertFails(getBytes(ref(storage, 'avatars/customer-1.txt')));
  });
});
