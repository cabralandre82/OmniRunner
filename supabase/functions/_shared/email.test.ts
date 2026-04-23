/**
 * Unit tests for `_shared/email.ts` (L15-04).
 *
 * Covers:
 *   • escapeHtml: every metacharacter + nullables
 *   • renderTemplate: placeholder substitution, HTML-escape,
 *                     missing-key reporting, no-escape mode for subjects
 *   • validateEmailAddress: accepts canonical shapes, rejects malformed
 *   • assertRequiredVars: missing_vars error with the full list
 *   • resolveProvider: picks by env, defaults to null, rejects unknown
 *   • NullProvider: fabricates id and never touches the network
 *   • InMemoryLoader: happy path + missing-template EmailError
 *   • sendEmail: rejects bad recipient, unknown template, missing vars;
 *                succeeds with injected loader + NullProvider; maps
 *                provider rejection into status='failed' with terminal flag
 *
 * Run with: deno test supabase/functions/_shared/email.test.ts
 */

import {
  assert,
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  assertRequiredVars,
  EmailError,
  escapeHtml,
  InMemoryLoader,
  NullProvider,
  renderTemplate,
  resolveProvider,
  sendEmail,
  TEMPLATE_MANIFEST,
  validateEmailAddress,
  type EmailProvider,
  type EmailTemplateKey,
  type ProviderDispatchResult,
  type RenderedEmail,
} from "./email.ts";

// ─────────────────────────── escapeHtml ───────────────────────────

Deno.test("escapeHtml — every metacharacter", () => {
  assertEquals(escapeHtml("& < > \" ' /"), "&amp; &lt; &gt; &quot; &#39; &#x2F;");
});

Deno.test("escapeHtml — safe strings pass through", () => {
  assertEquals(escapeHtml("Bruno Silva"), "Bruno Silva");
});

Deno.test("escapeHtml — null/undefined/number", () => {
  assertEquals(escapeHtml(null), "");
  assertEquals(escapeHtml(undefined), "");
  assertEquals(escapeHtml(42), "42");
});

Deno.test("escapeHtml — XSS payload inert", () => {
  assertEquals(
    escapeHtml("<img src=x onerror=alert(1)>"),
    "&lt;img src=x onerror=alert(1)&gt;",
  );
});

// ────────────────────────── renderTemplate ──────────────────────────

Deno.test("renderTemplate — substitutes and escapes by default", () => {
  const out = renderTemplate(
    "Hello <b>{{name}}</b>!",
    { name: "<script>x</script>" },
  );
  assertEquals(out, "Hello <b>&lt;script&gt;x&lt;&#x2F;script&gt;</b>!");
});

Deno.test("renderTemplate — escape:false for subjects", () => {
  const out = renderTemplate(
    "Welcome {{name}}",
    { name: "Alice & Bob" },
    { escape: false },
  );
  assertEquals(out, "Welcome Alice & Bob");
});

Deno.test("renderTemplate — missing placeholder reports via onMissing", () => {
  const missing: string[] = [];
  const out = renderTemplate(
    "Hi {{name}} ({{email}})",
    { name: "Ana" },
    { onMissing: (n) => missing.push(n) },
  );
  assertEquals(out, "Hi Ana ()");
  assertEquals(missing, ["email"]);
});

Deno.test("renderTemplate — placeholder with spaces inside braces", () => {
  assertEquals(
    renderTemplate("{{ name }}", { name: "Dev" }, { escape: false }),
    "Dev",
  );
});

// ───────────────────────── validateEmailAddress ─────────────────────────

Deno.test("validateEmailAddress — canonical shapes pass", () => {
  assert(validateEmailAddress("user@example.com"));
  assert(validateEmailAddress("user.tag+filter@example.co.uk"));
  assert(validateEmailAddress("a@b.io"));
});

Deno.test("validateEmailAddress — rejects malformed", () => {
  assert(!validateEmailAddress(""));
  assert(!validateEmailAddress("no-at-sign"));
  assert(!validateEmailAddress("user@"));
  assert(!validateEmailAddress("@example.com"));
  assert(!validateEmailAddress("user @example.com"));
  assert(!validateEmailAddress("user@exa mple.com"));
  assert(!validateEmailAddress("user@example"));
  assert(!validateEmailAddress("a".repeat(255) + "@example.com"));
});

// ─────────────────────── assertRequiredVars ───────────────────────

Deno.test("assertRequiredVars — happy path for every manifest template", () => {
  for (const [key, def] of Object.entries(TEMPLATE_MANIFEST)) {
    const vars: Record<string, string> = {};
    for (const name of def.required_vars) vars[name] = `value-${name}`;
    assertRequiredVars(key as EmailTemplateKey, vars);
  }
});

Deno.test("assertRequiredVars — reports missing vars in thrown error", () => {
  const err = assertThrows(
    () =>
      assertRequiredVars("payment_confirmation", {
        user_name: "Ana",
      }),
    EmailError,
  );
  assertEquals(err.reason, "missing_vars");
  assert(err.terminal);
  assertStringIncludes(err.message, "amount");
  assertStringIncludes(err.message, "description");
  assertStringIncludes(err.message, "receipt_link");
});

Deno.test("assertRequiredVars — unknown template name", () => {
  const err = assertThrows(
    () =>
      assertRequiredVars(
        "does_not_exist" as unknown as EmailTemplateKey,
        {},
      ),
    EmailError,
  );
  assertEquals(err.reason, "unknown_template");
});

// ───────────────────────── resolveProvider ─────────────────────────

function withEnv<T>(
  overrides: Record<string, string | undefined>,
  fn: () => T,
): T {
  const saved: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(overrides)) {
    saved[k] = Deno.env.get(k);
    if (v === undefined) Deno.env.delete(k);
    else Deno.env.set(k, v);
  }
  try {
    return fn();
  } finally {
    for (const [k, prev] of Object.entries(saved)) {
      if (prev === undefined) Deno.env.delete(k);
      else Deno.env.set(k, prev);
    }
  }
}

Deno.test("resolveProvider — defaults to null when EMAIL_PROVIDER unset", () => {
  withEnv({ EMAIL_PROVIDER: undefined }, () => {
    assertEquals(resolveProvider().name, "null");
  });
});

Deno.test("resolveProvider — honours EMAIL_PROVIDER=inbucket", () => {
  withEnv({ EMAIL_PROVIDER: "inbucket" }, () => {
    assertEquals(resolveProvider().name, "inbucket");
  });
});

Deno.test("resolveProvider — honours EMAIL_PROVIDER=resend", () => {
  withEnv({ EMAIL_PROVIDER: "resend" }, () => {
    assertEquals(resolveProvider().name, "resend");
  });
});

Deno.test("resolveProvider — rejects unknown values", () => {
  withEnv({ EMAIL_PROVIDER: "mailchimp" }, () => {
    const err = assertThrows(() => resolveProvider(), EmailError);
    assertEquals(err.reason, "unknown_provider");
    assert(err.terminal);
  });
});

// ─────────────────────────── NullProvider ───────────────────────────

Deno.test("NullProvider — never throws, returns fabricated id", async () => {
  const p = new NullProvider();
  const r = await p.send({
    to: "user@example.com",
    from: "no-reply@omnirunner.app",
    fromName: "OmniRunner",
    subject: "x",
    html: "<p>x</p>",
    templateKey: "payment_confirmation",
  });
  assert(r.providerMessageId);
  assert(r.providerMessageId!.startsWith("null-"));
});

// ─────────────────────────── InMemoryLoader ───────────────────────────

Deno.test("InMemoryLoader — happy path", async () => {
  const l = new InMemoryLoader({ "foo.html": "<p>hi</p>" });
  assertEquals(await l.load("foo.html"), "<p>hi</p>");
});

Deno.test("InMemoryLoader — missing template raises EmailError", async () => {
  const l = new InMemoryLoader({});
  try {
    await l.load("missing.html");
    assert(false, "should have thrown");
  } catch (err) {
    assert(err instanceof EmailError);
    assertEquals(err.reason, "template_not_found");
    assert(err.terminal);
  }
});

// ─────────────────────────── sendEmail ───────────────────────────

const BASE_VARS: Record<string, string> = {
  user_name: "Alice",
  amount: "1.234,56",
  description: "OmniCoin pack",
  receipt_link: "https://omnirunner.app/r/abc",
};

Deno.test("sendEmail — rejects invalid recipient", async () => {
  const r = await sendEmail({
    to: "not-an-email",
    templateKey: "payment_confirmation",
    vars: BASE_VARS,
  }, {
    loader: new InMemoryLoader({
      "payment_confirmation.html": "<p>{{user_name}}</p>",
    }),
    provider: new NullProvider(),
  });
  assertEquals(r.status, "failed");
  assertEquals(r.error?.terminal, true);
  assertStringIncludes(r.error?.message ?? "", "not-an-email");
});

Deno.test("sendEmail — rejects unknown template", async () => {
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "does_not_exist" as unknown as EmailTemplateKey,
    vars: {},
  }, {
    loader: new InMemoryLoader({}),
    provider: new NullProvider(),
  });
  assertEquals(r.status, "failed");
  assert(r.error?.terminal);
});

Deno.test("sendEmail — rejects missing required vars", async () => {
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "payment_confirmation",
    vars: { user_name: "Alice" },
  }, {
    loader: new InMemoryLoader({
      "payment_confirmation.html": "<p>{{user_name}}</p>",
    }),
    provider: new NullProvider(),
  });
  assertEquals(r.status, "failed");
  assert(r.error?.terminal);
  assertStringIncludes(r.error?.message ?? "", "amount");
});

Deno.test("sendEmail — success with NullProvider", async () => {
  const loader = new InMemoryLoader({
    "payment_confirmation.html":
      "<p>Oi {{user_name}}, R$ {{amount}} — {{description}}</p>",
  });
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "payment_confirmation",
    vars: BASE_VARS,
  }, { loader, provider: new NullProvider() });
  assertEquals(r.status, "sent");
  assertEquals(r.provider, "null");
  assert(r.providerMessageId?.startsWith("null-"));
});

Deno.test("sendEmail — HTML escapes hostile values", async () => {
  let captured: RenderedEmail | null = null;
  const recorder: EmailProvider = {
    name: "null" as const,
    send(m) {
      captured = m;
      return Promise.resolve<ProviderDispatchResult>({ providerMessageId: "rec-1" });
    },
  };
  const loader = new InMemoryLoader({
    "payment_confirmation.html": "<p>{{description}}</p>",
  });
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "payment_confirmation",
    vars: {
      ...BASE_VARS,
      description: "<img src=x onerror=alert(1)>",
    },
  }, { loader, provider: recorder });
  assertEquals(r.status, "sent");
  assert(captured);
  const html = (captured as unknown as RenderedEmail).html;
  assertStringIncludes(html, "&lt;img src=x onerror=alert(1)&gt;");
});

Deno.test("sendEmail — provider terminal rejection propagates as terminal", async () => {
  const rejecting: EmailProvider = {
    name: "null" as const,
    send() {
      return Promise.reject(
        new EmailError("provider_4xx", "resend HTTP 422: bad address", true),
      );
    },
  };
  const loader = new InMemoryLoader({
    "payment_confirmation.html": "<p>x</p>",
  });
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "payment_confirmation",
    vars: BASE_VARS,
  }, { loader, provider: rejecting });
  assertEquals(r.status, "failed");
  assertEquals(r.error?.terminal, true);
  assertStringIncludes(r.error?.message ?? "", "resend HTTP 422");
});

Deno.test("sendEmail — provider transient failure flagged non-terminal", async () => {
  const flaky: EmailProvider = {
    name: "null" as const,
    send() {
      return Promise.reject(new Error("fetch timeout"));
    },
  };
  const loader = new InMemoryLoader({
    "payment_confirmation.html": "<p>x</p>",
  });
  const r = await sendEmail({
    to: "user@example.com",
    templateKey: "payment_confirmation",
    vars: BASE_VARS,
  }, { loader, provider: flaky });
  assertEquals(r.status, "failed");
  assertEquals(r.error?.terminal, false);
});
