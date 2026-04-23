/**
 * tools/test_l10_08_audit_logs_append_only.ts
 *
 * L10-08 — integration tests for the generic append-only audit-log guard.
 * Runs via `docker exec supabase_db_project-running psql ...` so we do not
 * depend on the `pg` driver in node_modules.
 */

import { execSync } from "node:child_process";

const DB = "supabase_db_project-running";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;
let total = 0;

function psql(sql: string): string {
  return execSync(
    `docker exec -i ${DB} psql -U postgres -d postgres -X -A -t -v ON_ERROR_STOP=1`,
    {
      input: sql,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
}

function psqlAllowError(sql: string): { out: string; ok: boolean } {
  try {
    const out = execSync(
      `docker exec -i ${DB} psql -U postgres -d postgres -X -A -t -v ON_ERROR_STOP=1`,
      {
        input: sql,
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    return { out, ok: true };
  } catch (e) {
    const err = e as { stdout?: Buffer | string; stderr?: Buffer | string };
    const out =
      (err.stdout ? err.stdout.toString() : "") +
      (err.stderr ? err.stderr.toString() : "");
    return { out, ok: false };
  }
}

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  total += 1;
  try {
    await fn();
    passed += 1;
    console.log(`  ${GREEN}✓${RESET} ${name}`);
  } catch (e) {
    failed += 1;
    console.log(`  ${RED}✗${RESET} ${name}\n      ${(e as Error).message}`);
  }
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

async function main(): Promise<void> {
  console.log(`\n${BOLD}L10-08 — append-only audit guard integration tests${RESET}`);

  await test("1. audit_append_only_config table exists with RLS forced", () => {
    const out = psql(
      "SELECT relrowsecurity::text || '|' || relforcerowsecurity::text FROM pg_class WHERE oid = 'public.audit_append_only_config'::regclass;",
    );
    assert(out.trim() === "true|true", `RLS not forced: ${out.trim()}`);
  });

  await test("2. fn_audit_has_append_only_guard is STABLE SECURITY DEFINER", () => {
    const out = psql(
      "SELECT provolatile::text || '|' || prosecdef::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='fn_audit_has_append_only_guard';",
    );
    assert(out.trim() === "s|true", `expected s|true (stable, secdef), got ${out.trim()}`);
  });

  await test("3. mode CHECK rejects unknown values", () => {
    const r = psqlAllowError(
      "INSERT INTO public.audit_append_only_config (schema_name, table_name, mode) VALUES ('public','x','foreign');",
    );
    assert(!r.ok, "CHECK should have rejected");
    assert(/check_constraint|check/i.test(r.out), `expected check_violation: ${r.out.slice(0, 200)}`);
  });

  await test("4. fn_audit_reject_mutation is present", () => {
    const out = psql(
      "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='fn_audit_reject_mutation';",
    );
    assert(out.trim() === "1", `expected 1 function, got ${out.trim()}`);
  });

  await test("5. fn_audit_install_append_only_guard is SECURITY DEFINER", () => {
    const out = psql(
      "SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='fn_audit_install_append_only_guard';",
    );
    assert(out.trim() === "t", `expected SECURITY DEFINER, got ${out.trim()}`);
  });

  await test("6. fn_audit_has_append_only_guard returns true for portal_audit_log", () => {
    const out = psql(
      "SELECT public.fn_audit_has_append_only_guard('public','portal_audit_log')::text;",
    );
    assert(out.trim() === "true", `expected true, got ${out.trim()}`);
  });

  await test("7. portal_audit_log is registered with mode=strict", () => {
    const out = psql(
      "SELECT mode FROM public.audit_append_only_config WHERE schema_name='public' AND table_name='portal_audit_log';",
    );
    assert(out.trim() === "strict", `expected strict, got ${out.trim()}`);
  });

  await test("8. coin_ledger_pii_redactions has the guard", () => {
    const out = psql(
      "SELECT public.fn_audit_has_append_only_guard('public','coin_ledger_pii_redactions')::text;",
    );
    assert(out.trim() === "true", `expected true, got ${out.trim()}`);
  });

  await test("9. cron_edge_retry_attempts has the guard", () => {
    const out = psql(
      "SELECT public.fn_audit_has_append_only_guard('public','cron_edge_retry_attempts')::text;",
    );
    assert(out.trim() === "true", `expected true, got ${out.trim()}`);
  });

  await test("10. consent_events has the guard", () => {
    const out = psql(
      "SELECT public.fn_audit_has_append_only_guard('public','consent_events')::text;",
    );
    assert(out.trim() === "true", `expected true, got ${out.trim()}`);
  });

  await test("11. account_deletion_log is tracked when present", () => {
    const exists = psql(
      "SELECT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='account_deletion_log')::text;",
    ).trim();
    if (exists === "true") {
      const mode = psql(
        "SELECT mode FROM public.audit_append_only_config WHERE schema_name='public' AND table_name='account_deletion_log';",
      ).trim();
      assert(mode === "append_with_outcome", `got: ${mode}`);
    }
  });

  await test("12. DELETE on portal_audit_log raises P0010", () => {
    psql(`
      DO $$
      DECLARE
        v_actor uuid;
      BEGIN
        SELECT id INTO v_actor FROM auth.users LIMIT 1;
        IF v_actor IS NULL THEN
          v_actor := gen_random_uuid();
          INSERT INTO auth.users (id, instance_id, aud, role)
            VALUES (v_actor, '00000000-0000-0000-0000-000000000000', 'authenticated','authenticated')
            ON CONFLICT (id) DO NOTHING;
        END IF;
        INSERT INTO public.portal_audit_log (id, actor_id, action)
          VALUES ('11111111-1111-1111-1111-111111111111', v_actor, 'l10_08.test.delete')
          ON CONFLICT (id) DO NOTHING;
      END
      $$;
    `);
    const r = psqlAllowError(
      "DELETE FROM public.portal_audit_log WHERE id = '11111111-1111-1111-1111-111111111111';",
    );
    assert(!r.ok, "DELETE should have been rejected");
    assert(
      /L10-08|append_only_delete_blocked|P0010/i.test(r.out),
      `expected L10-08 block: ${r.out.slice(0, 300)}`,
    );
  });

  await test("13. UPDATE on portal_audit_log raises P0010", () => {
    const r = psqlAllowError(
      "UPDATE public.portal_audit_log SET action = 'tampered' WHERE id = '11111111-1111-1111-1111-111111111111';",
    );
    assert(!r.ok, "UPDATE should have been rejected");
    assert(
      /L10-08|append_only_update_blocked|P0010/i.test(r.out),
      `expected L10-08 block: ${r.out.slice(0, 300)}`,
    );
  });

  await test("14. TRUNCATE on portal_audit_log raises P0010", () => {
    const r = psqlAllowError("TRUNCATE TABLE public.portal_audit_log;");
    assert(!r.ok, "TRUNCATE should have been rejected");
    assert(
      /L10-08|append_only_truncate_blocked|P0010/i.test(r.out),
      `expected L10-08 block: ${r.out.slice(0, 300)}`,
    );
  });

  await test("15. INSERT on portal_audit_log is unaffected", () => {
    psql(`
      DO $$
      DECLARE
        v_actor uuid;
      BEGIN
        SELECT id INTO v_actor FROM auth.users LIMIT 1;
        INSERT INTO public.portal_audit_log (id, actor_id, action)
          VALUES (gen_random_uuid(), v_actor, 'l10_08.test.insert.ok');
      END
      $$;
    `);
  });

  await test("16. trigger raises WARNING with structured context", () => {
    const r = psqlAllowError(
      "DELETE FROM public.portal_audit_log WHERE id = '11111111-1111-1111-1111-111111111111';",
    );
    assert(!r.ok, "DELETE should have been rejected");
    assert(
      /WARNING:[^\n]*L10-08:[^\n]*attempt to DELETE/i.test(r.out),
      `expected WARNING with L10-08 attempt to DELETE: ${r.out.slice(0, 400)}`,
    );
  });

  await test("17. fn_audit_assert_append_only_shape passes on current DB", () => {
    psql("SELECT public.fn_audit_assert_append_only_shape();");
  });

  await test("18. installer is idempotent (re-run no-op)", () => {
    psql(
      "SELECT public.fn_audit_install_append_only_guard('public','portal_audit_log','re-run');",
    );
    const out = psql(
      "SELECT public.fn_audit_has_append_only_guard('public','portal_audit_log')::text;",
    );
    assert(out.trim() === "true", "guard should still be present after re-run");
  });

  await test("19. installer no-op on non-existent table", () => {
    const out = psql(
      "SELECT public.fn_audit_install_append_only_guard('public','no_such_table_l10_08')::text;",
    );
    assert(out.trim() === "false", `expected false, got ${out.trim()}`);
  });

  await test("20. anon has no EXECUTE on the installer", () => {
    const out = psql(
      "SELECT has_function_privilege('anon','public.fn_audit_install_append_only_guard(text,text,text)','EXECUTE')::text;",
    );
    assert(out.trim() === "false", `anon should not EXECUTE, got ${out.trim()}`);
  });

  console.log(
    `\n${BOLD}Summary:${RESET} ${passed}/${total} passed${
      failed ? `, ${RED}${failed} failed${RESET}` : ""
    }.`,
  );

  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
