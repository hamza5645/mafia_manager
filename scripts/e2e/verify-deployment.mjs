import { ConvexHttpClient } from 'convex/browser';
import { anyApi } from 'convex/server';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/**
 * Compatible when the deployment speaks at least the app's contract and still
 * accepts it (min_client_contract), so a backend may roll out ahead of the app.
 * @param {any} health the deployment's health:check result
 * @param {number} expected the app's ConvexConfig.apiContractVersion
 */
export function assertCompatible(health, expected) {
  const minimum = health?.min_client_contract ?? health?.api_contract;
  if (!health?.ok || health.backend !== 'convex' || !(health.api_contract >= expected) || !(minimum <= expected)) {
    throw new Error(`Backend API contract mismatch: app speaks ${expected}, deployment reports ${health?.api_contract ?? 'missing'} (minimum client ${minimum ?? 'missing'}). Deploy the matching backend before rollout.`);
  }
}

/**
 * The deployment to check: with --prod the one the App Store build uses
 * (Production.xcconfig); otherwise CONVEX_AUDIT_URL, else the Debug one.
 * @param {string[]} argv
 * @param {Record<string, string | undefined>} env
 */
export function deploymentURL(argv, env) {
  const prod = argv.includes('--prod');
  const xcconfig = readFileSync(new URL(`../../Configuration/${prod ? 'Production' : 'Debug'}.xcconfig`, import.meta.url), 'utf8');
  const host = xcconfig.match(/^MAFIA_CONVEX_HOST = (\S+)/m)?.[1];
  return (prod ? undefined : env.CONVEX_AUDIT_URL) ?? (host && `https://${host}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = readFileSync(new URL('../../Core/Backend/ConvexConfig.swift', import.meta.url), 'utf8');
  const expected = Number(config.match(/apiContractVersion = (\d+)/)?.[1]);
  const url = deploymentURL(process.argv, process.env);
  if (!url || !Number.isInteger(expected)) throw new Error('Could not read app deployment/contract configuration');
  console.log(`Checking ${url} against app API contract ${expected}`);
  const health = await new ConvexHttpClient(url).query(anyApi.health.check, {});
  assertCompatible(health, expected);
  console.log(`PASS ${url}: deployment API contract ${health.api_contract} accepts app contract ${expected}`);
}
