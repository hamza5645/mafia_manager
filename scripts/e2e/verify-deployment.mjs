import { ConvexHttpClient } from 'convex/browser';
import { readFileSync } from 'node:fs';

export function assertCompatible(health, expected) {
  if (!health?.ok || health.backend !== 'convex' || health.api_contract !== expected) {
    throw new Error(`Backend API contract mismatch: app requires ${expected}, deployment reports ${health?.api_contract ?? 'missing'}. Deploy the matching backend before rollout.`);
  }
}

const config = readFileSync(new URL('../../Core/Backend/ConvexConfig.swift', import.meta.url), 'utf8');
const expected = Number(config.match(/apiContractVersion = (\d+)/)?.[1]);
const host = readFileSync(new URL('../../Configuration/Debug.xcconfig', import.meta.url), 'utf8').match(/^MAFIA_CONVEX_HOST = (\S+)/m)?.[1];
const url = process.env.CONVEX_AUDIT_URL ?? (host && `https://${host}`);
if (!url || !Number.isInteger(expected)) throw new Error('Could not read app deployment/contract configuration');
const health = await new ConvexHttpClient(url).query('health:check', {});
assertCompatible(health, expected);
console.log(`PASS deployment API contract ${expected}`);
