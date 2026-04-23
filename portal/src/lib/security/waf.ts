/**
 * waf.ts — L10-04 in-process WAF defence-in-depth.
 *
 * The portal sits behind Vercel's edge firewall, but the edge rules
 * are out-of-band (configured via dashboard) and we cannot enforce
 * them in CI. This module is the **inline** complement that runs on
 * every request handled by `middleware.ts`, covering the cheapest
 * broad-stroke rejections (malicious User-Agent, well-known scanner
 * paths, head-full proxies).
 *
 * Rules here are **allow-everything-then-deny** — only explicit
 * matches block. That keeps this surface safe to iterate without
 * accidentally breaking legitimate traffic.
 *
 * See docs/runbooks/WAF_RUNBOOK.md for the policy governing these
 * lists and how to add new entries.
 */

// User-Agent substrings that we categorically block. Keep this list
// short and curated — wider deny-lists belong at Vercel / Cloudflare.
const BLOCKED_USER_AGENT_SUBSTRINGS = Object.freeze([
  "sqlmap",
  "nikto",
  "nmap",
  "masscan",
  "havij",
  "acunetix",
  "nessus",
  "wpscan",
  "hydra ",
  "dirbuster",
  "gobuster",
  "zgrab",
  "zmap",
  "shodan",
]);

// Request-path fragments that no legitimate client ever asks for.
// Matching these saves round-trips against admin scanners probing
// WordPress / phpMyAdmin / Laravel endpoints that we do not expose.
const BLOCKED_PATH_FRAGMENTS = Object.freeze([
  "/wp-admin",
  "/wp-login.php",
  "/wp-content",
  "/wp-includes",
  "/phpmyadmin",
  "/pma",
  "/adminer",
  "/xmlrpc.php",
  "/.env",
  "/.git/",
  "/.git/config",
  "/.git/HEAD",
  "/.aws/credentials",
  "/.ssh/id_rsa",
  "/.DS_Store",
  "/config.php",
  "/config.yaml",
  "/cgi-bin/",
  "/bin/sh",
]);

// Paths we want to keep EVEN if an attacker spells them suspiciously;
// currently unused but declared as the allow-list contract for the
// future. Consumers should not use this to exempt arbitrary rules.
const EXPLICIT_ALLOW_PATHS = Object.freeze(["/.well-known/security.txt"]);

export type WafVerdict =
  | { ok: true }
  | { ok: false; rule: "ua" | "path" | "tor"; detail: string };

/** Case-insensitive User-Agent check. */
export function shouldBlockUserAgent(ua: string | null | undefined): WafVerdict {
  if (!ua) return { ok: true };
  const lower = ua.toLowerCase();
  for (const sub of BLOCKED_USER_AGENT_SUBSTRINGS) {
    if (lower.includes(sub)) {
      return { ok: false, rule: "ua", detail: `blocked UA: ${sub}` };
    }
  }
  return { ok: true };
}

/**
 * Path fragment check. Uses case-sensitive match because typical
 * attacker paths are exact strings; our own routes never lowercase.
 */
export function shouldBlockPath(pathname: string): WafVerdict {
  if (!pathname) return { ok: true };
  if (EXPLICIT_ALLOW_PATHS.includes(pathname)) return { ok: true };
  for (const frag of BLOCKED_PATH_FRAGMENTS) {
    if (pathname.includes(frag)) {
      return { ok: false, rule: "path", detail: `blocked path: ${frag}` };
    }
  }
  return { ok: true };
}

/**
 * Single entry point the middleware calls. Applies UA then path. The
 * order is deliberate — UA check is O(n) over a short list and
 * catches the loudest attackers first.
 */
export function evaluateWaf(req: {
  userAgent: string | null | undefined;
  pathname: string;
}): WafVerdict {
  const uaVerdict = shouldBlockUserAgent(req.userAgent);
  if (!uaVerdict.ok) return uaVerdict;
  return shouldBlockPath(req.pathname);
}

// Exported for unit tests and docs cross-references.
export const WAF_BLOCKED_UA_SUBSTRINGS = BLOCKED_USER_AGENT_SUBSTRINGS;
export const WAF_BLOCKED_PATH_FRAGMENTS = BLOCKED_PATH_FRAGMENTS;
export const WAF_EXPLICIT_ALLOW_PATHS = EXPLICIT_ALLOW_PATHS;
