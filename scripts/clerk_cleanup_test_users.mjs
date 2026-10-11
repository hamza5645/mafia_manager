#!/usr/bin/env node
// Lists, and with --delete removes, the Clerk development users that
// ClerkAccountIntegrationTests signs up (mafia-native-<uuid>+clerk_test@example.com).
//
//   CLERK_SECRET_KEY=sk_test_... node scripts/clerk_cleanup_test_users.mjs            # dry run
//   CLERK_SECRET_KEY=sk_test_... node scripts/clerk_cleanup_test_users.mjs --delete   # delete
//
// Reads the development secret key from the environment only; never commit it.
// Production keys (sk_live_) are refused. Their Convex user rows are not touched.

const API = "https://api.clerk.com/v1";
const TEST_EMAIL = /^mafia-native-[^@\s]+\+clerk_test@example\.com$/i;
const PAGE_SIZE = 100;

const shouldDelete = process.argv.includes("--delete");
const key = process.env.CLERK_SECRET_KEY ?? "";

if (key.startsWith("sk_live_")) {
  console.error("Refusing to run with a production key (sk_live_). Use the development instance's sk_test_ key.");
  process.exit(1);
}
if (!key.startsWith("sk_test_")) {
  console.error("Set CLERK_SECRET_KEY to the development instance's secret key (sk_test_...).");
  process.exit(1);
}

async function clerk(method, path) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}` },
  });
  if (!response.ok) {
    throw new Error(`${method} ${path.split("?")[0]} failed: HTTP ${response.status} ${await response.text()}`);
  }
  return response.json();
}

function testEmails(user) {
  return (user.email_addresses ?? []).map((e) => e.email_address).filter((email) => TEST_EMAIL.test(email));
}

async function findTestUsers() {
  const matches = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const query = new URLSearchParams({ query: "mafia-native-", limit: String(PAGE_SIZE), offset: String(offset), order_by: "created_at" });
    const page = await clerk("GET", `/users?${query}`);
    for (const user of page) {
      const emails = testEmails(user);
      // Every address must be a test address, so a real account is never selected.
      if (emails.length > 0 && emails.length === (user.email_addresses ?? []).length) {
        matches.push({ id: user.id, email: emails[0], createdAt: new Date(user.created_at).toISOString() });
      }
    }
    if (page.length < PAGE_SIZE) return matches;
  }
}

const users = await findTestUsers();
for (const user of users) console.log(`${user.id}  ${user.email}  created ${user.createdAt}`);
console.log(`${users.length} test user(s) found.`);

if (!shouldDelete) {
  if (users.length > 0) console.log("Dry run. Re-run with --delete to remove them.");
  process.exit(0);
}

let deleted = 0;
for (const user of users) {
  await clerk("DELETE", `/users/${encodeURIComponent(user.id)}`);
  deleted += 1;
}
console.log(`Deleted ${deleted} test user(s).`);
