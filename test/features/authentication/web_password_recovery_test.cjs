const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../../../docs/reset-password.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const requirements = 'Password must be at least 8 characters and include uppercase, lowercase, number, and special character.';

function page(hash = '#token_hash=test-recovery-hash&type=recovery', respond) {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      id, value: '', type: 'password', textContent: '', hidden: false, disabled: false,
      listeners: {}, attributes: {}, dataset: {},
      addEventListener(type, callback) { this.listeners[type] = callback; },
      setAttribute(name, value) { this.attributes[name] = value; },
    });
    return elements.get(id);
  }
  element('requirements').textContent = requirements;
  const eyes = ['password', 'confirmation'].map(id => {
    const eye = element(`eye-${id}`);
    eye.dataset.field = id;
    return eye;
  });
  const requests = [];
  const history = [];
  const context = {
    URLSearchParams, AbortController, setTimeout, clearTimeout,
    location: { hash, pathname: '/reset-password.html' },
    history: { replaceState: (_, __, url) => history.push(url) },
    document: { getElementById: element, querySelectorAll: () => eyes },
    window: { addEventListener() {} },
    async fetch(url, options) {
      const request = { url, ...options, body: options.body ? JSON.parse(options.body) : null };
      requests.push(request);
      const result = respond ? await respond(request) : { status: 200, data: url.endsWith('/verify')
        ? { access_token: 'synthetic-session', expires_in: 3600, user: { email: 'rider@example.test', identities: [{ provider: 'email' }] } } : {} };
      return { ok: result.status < 400, status: result.status, json: async () => result.data };
    },
  };
  vm.runInNewContext(script, context);
  return {
    element, requests, history, eyes,
    async verify() { await element('verify-link').listeners.click(); },
    async submit(value = 'Strong1!', repeated = value) {
      element('password').value = value;
      element('confirmation').value = repeated;
      await element('reset-form').listeners.submit({ preventDefault() {} });
    },
  };
}

test('recovery page accepts only recovery hash links and strips URL without network or storage', () => {
  for (const hash of ['', '#code=app-pkce-code', '#token_hash=signup-token&type=signup']) {
    const p = page(hash);
    assert.equal(p.element('reset-form').hidden, true);
    assert.match(p.element('status').textContent, /invalid or has expired/);
    assert.equal(p.requests.length, 0);
  }
  const p = page();
  assert.equal(p.element('reset-form').hidden, true);
  assert.equal(p.element('verify-link').hidden, false);
  assert.deepEqual(p.history, ['/reset-password.html']);
  assert.equal(p.requests.length, 0);
  assert.doesNotMatch(script, /localStorage|sessionStorage|console\./);
  const key = script.match(/const publicKey = '([^']+)'/)[1];
  if (!key.startsWith('sb_publishable_')) {
    assert.equal(JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role, 'anon');
  }
});

test('web password validation rejects weak and mismatched input before any submission', async () => {
  const p = page();
  await p.verify();
  for (const weak of ['', 'Aa1!', 'lowercase1!', 'UPPERCASE1!', 'NoNumbers!', 'NoSymbols1', 'Password1 ', 'Password1\u00e9']) {
    await p.submit(weak);
    assert.equal(p.requests.length, 1);
    assert.ok(p.element('status').textContent.length > 0);
  }
  await p.submit('Strong1!', 'Strong2!');
  assert.equal(p.element('status').textContent, 'Passwords do not match.');
  assert.equal(p.requests.length, 1);
});

test('cross-device recovery verifies token before updating password then clears session and fields', async () => {
  const p = page();
  await p.verify();
  assert.equal(p.element('reset-form').hidden, false);
  await p.submit();
  assert.deepEqual(p.requests.map(r => new URL(r.url).pathname), ['/auth/v1/verify', '/auth/v1/user', '/auth/v1/logout']);
  assert.deepEqual(p.requests[0].body, { token_hash: 'test-recovery-hash', type: 'recovery' });
  assert.equal(p.requests[0].headers.Authorization, undefined);
  assert.deepEqual(p.requests[1].body, { password: 'Strong1!' });
  assert.equal(p.requests[1].method, 'PUT');
  assert.equal(p.requests[1].headers.Authorization, 'Bearer synthetic-session');
  assert.equal(new URL(p.requests[2].url).searchParams.get('scope'), 'local');
  assert.equal(p.element('password').value, '');
  assert.equal(p.element('confirmation').value, '');
  assert.equal(p.element('reset-form').hidden, true);
  assert.match(p.element('status').textContent, /Password updated successfully/);
  await p.submit();
  assert.equal(p.requests.length, 3);
});

test('expired tokens never update a password or display raw server errors', async () => {
  const p = page(undefined, () => ({ status: 403, data: { message: 'PRIVATE SERVER TOKEN DETAILS' } }));
  await p.verify();
  assert.equal(p.requests.length, 1);
  assert.match(p.element('status').textContent, /invalid or has expired/);
  assert.doesNotMatch(p.element('status').textContent, /PRIVATE/);
  assert.equal(p.element('submit').disabled, false);
});

test('verified email equality is rejected and retry reuses only the verified recovery session', async () => {
  const p = page(undefined, r => ({ status: 200, data: r.url.endsWith('/verify')
    ? { access_token: 'synthetic-session', expires_in: 3600, user: { email: 'Rider1!@example.test', identities: [{ provider: 'email' }] } } : {} }));
  await p.verify();
  await p.submit('Rider1!@example.test');
  assert.equal(p.requests.length, 1);
  assert.match(p.element('status').textContent, /same as your email/);
  await p.submit('Different2!');
  assert.equal(p.requests.filter(r => r.url.endsWith('/verify')).length, 1);
  assert.equal(p.requests.filter(r => r.url.endsWith('/user')).length, 1);
});

test('eye controls toggle independently and Back abandons the link without app-only redirects', () => {
  const p = page();
  p.eyes[0].listeners.click();
  assert.equal(p.element('password').type, 'text');
  assert.equal(p.element('confirmation').type, 'password');
  p.eyes[1].listeners.click();
  assert.equal(p.element('confirmation').type, 'text');
  p.element('back').listeners.click();
  assert.equal(p.element('reset-form').hidden, true);
  assert.match(p.element('intro').textContent, /original device/);
  assert.equal(p.requests.length, 0);
  assert.doesNotMatch(html, /governmenttransit:\/\//);
});

test('busy guard prevents duplicate recovery requests', async () => {
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  const p = page(undefined, async r => {
    if (r.url.endsWith('/verify')) {
      await waiting;
      return { status: 200, data: { access_token: 'synthetic-session', expires_in: 3600, user: { email: 'rider@example.test', identities: [{ provider: 'email' }] } } };
    }
    return { status: 200, data: {} };
  });
  const first = p.verify();
  await p.verify();
  assert.equal(p.requests.length, 1);
  release();
  await first;
  await p.submit();
  assert.equal(p.requests.filter(r => r.url.endsWith('/verify')).length, 1);
  assert.equal(p.requests.filter(r => r.url.endsWith('/user')).length, 1);
});

for (const providers of [['email'], ['google', 'email'], ['google'], []]) {
  test(`recovery eligibility uses verified identities: ${providers.join('+') || 'missing'}`, async () => {
    const user = { id: 'same-user-id', email: 'rider@example.test',
      identities: providers.map(provider => ({ provider })),
      app_metadata: { provider: 'google' }, user_metadata: { provider: 'email' } };
    const p = page(undefined, r => ({ status: 200, data: r.url.endsWith('/verify')
      ? { access_token: 'synthetic-session', expires_in: 3600, user } : {} }));
    assert.equal(p.element('reset-form').hidden, true);
    await p.verify();
    const eligible = providers.includes('email');
    assert.equal(p.element('reset-form').hidden, !eligible);
    await p.submit();
    const updates = p.requests.filter(r => r.method === 'PUT');
    assert.equal(updates.length, eligible ? 1 : 0);
    if (eligible) {
      assert.deepEqual(updates[0].body, { password: 'Strong1!' });
      assert.equal(updates[0].headers.Authorization, 'Bearer synthetic-session');
    } else {
      assert.match(p.element('status').textContent, providers.length ? /uses Google Sign-In/ : /not available/);
    }
    assert.deepEqual(p.requests.map(r => new URL(r.url).pathname), eligible
      ? ['/auth/v1/verify', '/auth/v1/user', '/auth/v1/logout']
      : ['/auth/v1/verify', '/auth/v1/logout']);
    assert.equal(user.id, 'same-user-id');
    assert.deepEqual(user.identities.map(i => i.provider), providers);
  });
}
