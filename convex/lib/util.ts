import { fail } from "./errors";

// Apple/NSDate reference epoch (2001-01-01) in seconds. Swift's
// Date(timeIntervalSinceReferenceDate:) decodes this natively.
export const nowAppleEpochSeconds = () => Date.now() / 1000 - 978307200;
export const uuid = () => crypto.randomUUID();

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function cleanText(value: string, min: number, max: number, message: string): string {
  const text = value.trim();
  if (text.length < min || text.length > max || /[\n\r]/.test(text)) fail(message);
  return text;
}
