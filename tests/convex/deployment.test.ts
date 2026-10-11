// @vitest-environment node
import { expect, test } from 'vitest';
import { assertCompatible, deploymentURL } from '../../scripts/e2e/verify-deployment.mjs';
import { backend } from './helpers';
import { api } from '../../convex/_generated/api';

test('the deploy check accepts the current health response and rejects mismatches', async () => {
  const health = await backend().query(api.health.check, {});
  expect(() => assertCompatible(health, health.api_contract)).not.toThrow();
  // A backend may run ahead of the app while it still accepts the app's contract.
  expect(() => assertCompatible({ ...health, api_contract: 6, min_client_contract: 5 }, 5)).not.toThrow();
  for (const [reported, expected] of [[{ ...health, api_contract: 4, min_client_contract: 4 }, 5],
    [{ ...health, api_contract: 6, min_client_contract: 6 }, 5], [{ ...health, ok: false }, 5], [undefined, 5]] as const) {
    expect(() => assertCompatible(reported, expected)).toThrow(/Backend API contract mismatch/);
  }
  // Contract 4 deployments had no min_client_contract.
  expect(() => assertCompatible({ ok: true, backend: 'convex', api_contract: 4 }, 4)).not.toThrow();
});

test('the deploy check targets production only with --prod, and CONVEX_AUDIT_URL only without it', () => {
  const debug = deploymentURL([], {});
  const prod = deploymentURL(['node', 'verify-deployment.mjs', '--prod'], { CONVEX_AUDIT_URL: 'https://audit.convex.cloud' });
  for (const url of [debug, prod]) expect(url).toMatch(/^https:\/\/[a-z0-9-]+\.[a-z0-9-]+\.convex\.cloud$/);
  expect(prod).not.toBe(debug);
  expect(deploymentURL([], { CONVEX_AUDIT_URL: 'https://audit.convex.cloud' })).toBe('https://audit.convex.cloud');
});
