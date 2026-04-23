/**
 * L17-01 — testes do safety-net `withErrorHandler`.
 *
 * Cobre:
 *   - happy path: response do handler é devolvida como veio
 *   - throw: cai no envelope canônico `{ ok:false, error:{ code, message,
 *     request_id } }` com status 500
 *   - request_id: preservado quando o cliente envia, gerado quando ausente,
 *     ecoado em header tanto em sucesso quanto em erro
 *   - context fwd: handlers de rota dinâmica (`{ params }`) recebem o
 *     segundo argumento intacto
 *   - errorMap: mapeia erros de domínio antes do fallback 500; retorna
 *     null/undefined para deixar passar
 *   - logger: erros viram `logger.error` (que por sua vez chama Sentry)
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest, NextResponse } from "next/server";

const loggerErrorSpy = vi.fn();
vi.mock("./logger", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: (...args: unknown[]) => loggerErrorSpy(...args),
  },
}));

vi.mock("@sentry/nextjs", () => ({
  getActiveSpan: () => null,
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  spanToJSON: () => ({}),
}));

import { withErrorHandler, type RouteParams } from "./api-handler";

function makeReq(headers: Record<string, string> = {}, method = "POST") {
  const h = new Headers();
  for (const [k, v] of Object.entries(headers)) h.set(k, v);
  return new NextRequest("https://example.com/api/x", {
    headers: h,
    method,
  });
}

beforeEach(() => {
  loggerErrorSpy.mockClear();
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("withErrorHandler — happy path", () => {
  it("returns the handler response untouched when no throw", async () => {
    const handler = vi.fn(async () =>
      NextResponse.json({ ok: true, data: { x: 1 } }),
    );
    const wrapped = withErrorHandler(handler, "api.test.ok");
    const res = await wrapped(makeReq({ "x-request-id": "rq-1" }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ ok: true, data: { x: 1 } });
    expect(loggerErrorSpy).not.toHaveBeenCalled();
  });

  it("echoes incoming x-request-id on success responses", async () => {
    const handler = vi.fn(async () => NextResponse.json({ ok: true }));
    const wrapped = withErrorHandler(handler, "api.test.echo");
    const res = await wrapped(makeReq({ "x-request-id": "rq-echo" }));
    expect(res.headers.get("x-request-id")).toBe("rq-echo");
  });

  it("does NOT overwrite an x-request-id the handler already set", async () => {
    const handler = vi.fn(async () =>
      NextResponse.json(
        { ok: true },
        { headers: { "x-request-id": "from-handler" } },
      ),
    );
    const wrapped = withErrorHandler(handler, "api.test.no-clobber");
    const res = await wrapped(makeReq({ "x-request-id": "from-client" }));
    expect(res.headers.get("x-request-id")).toBe("from-handler");
  });
});

describe("withErrorHandler — throw fallback", () => {
  it("converts thrown Error into canonical 500 envelope", async () => {
    const handler = vi.fn(async () => {
      throw new Error("kaboom");
    });
    const wrapped = withErrorHandler(handler, "api.test.boom");
    const res = await wrapped(makeReq({ "x-request-id": "rq-boom" }));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body).toEqual({
      ok: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Internal server error",
        request_id: "rq-boom",
      },
    });
    expect(res.headers.get("x-request-id")).toBe("rq-boom");
    expect(loggerErrorSpy).toHaveBeenCalledTimes(1);
    const [msg, err, meta] = loggerErrorSpy.mock.calls[0] as [
      string,
      Error,
      Record<string, unknown>,
    ];
    expect(msg).toContain("api.test.boom");
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toBe("kaboom");
    expect(meta).toMatchObject({
      requestId: "rq-boom",
      method: "POST",
      route: "api.test.boom",
    });
  });

  it("generates a UUID v4 request_id when client did not send one", async () => {
    const handler = vi.fn(async () => {
      throw new Error("kaboom");
    });
    const wrapped = withErrorHandler(handler, "api.test.gen-id");
    const res = await wrapped(makeReq({}));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.request_id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    );
    expect(res.headers.get("x-request-id")).toBe(body.error.request_id);
  });

  it("uses the custom fallbackMessage when provided", async () => {
    const handler = vi.fn(async () => {
      throw new Error("boom");
    });
    const wrapped = withErrorHandler(handler, "api.test.custom-msg", {
      fallbackMessage: "Erro inesperado em swap",
    });
    const res = await wrapped(makeReq());
    const body = await res.json();
    expect(body.error.message).toBe("Erro inesperado em swap");
  });
});

describe("withErrorHandler — context forwarding", () => {
  it("forwards { params } from Next.js dynamic routes", async () => {
    // L17-03 — ctx is TYPED, not `any`. The generic `TArgs` inference on
    // withErrorHandler pulls { params: { id: string } } from the handler
    // signature all the way through the wrapper; a wrong key here
    // (e.g. `ctx?.params?.slug`) is a compile error.
    const handler = vi.fn(
      async (
        _req: NextRequest,
        ctx: RouteParams<{ id: string }>,
      ): Promise<NextResponse> =>
        NextResponse.json({ id: ctx.params.id }),
    );
    const wrapped = withErrorHandler(handler, "api.test.dyn");
    const res = await wrapped(makeReq(), { params: { id: "abc-123" } });
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][1]).toEqual({ params: { id: "abc-123" } });
    const body = await res.json();
    expect(body.id).toBe("abc-123");
  });

  it("L17-03 — preserves the handler signature exactly (no any)", async () => {
    // Static route (no ctx). Calling `wrapped(req, {...})` must be a
    // compile-time error; we verify by asserting arity at runtime.
    const staticHandler = async (_req: NextRequest): Promise<NextResponse> =>
      NextResponse.json({ ok: true });
    const wrapped = withErrorHandler(staticHandler, "api.test.static");
    expect(wrapped.length).toBe(staticHandler.length);

    // Dynamic route with a specific param shape.
    const dynHandler = async (
      _req: NextRequest,
      ctx: RouteParams<{ groupId: string; id: string }>,
    ): Promise<NextResponse> =>
      NextResponse.json({ gid: ctx.params.groupId, id: ctx.params.id });
    const wrappedDyn = withErrorHandler(dynHandler, "api.test.nested");
    const res = await wrappedDyn(makeReq(), {
      params: { groupId: "g-1", id: "a-2" },
    });
    const body = await res.json();
    expect(body).toEqual({ gid: "g-1", id: "a-2" });
  });
});

describe("withErrorHandler — errorMap", () => {
  class DomainError extends Error {
    constructor(public code: string) {
      super(code);
    }
  }

  it("invokes errorMap and returns its response when matched", async () => {
    const handler = vi.fn(async () => {
      throw new DomainError("not_found");
    });
    const wrapped = withErrorHandler(handler, "api.test.map-found", {
      errorMap: (err) => {
        if (err instanceof DomainError) {
          return NextResponse.json(
            {
              ok: false,
              error: { code: err.code, message: err.code, request_id: null },
            },
            { status: 404 },
          );
        }
        return null;
      },
    });
    const res = await wrapped(makeReq({ "x-request-id": "rq-map" }));
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error.code).toBe("not_found");
    expect(res.headers.get("x-request-id")).toBe("rq-map");
    // domain mapping is not a server error → no logger.error
    expect(loggerErrorSpy).not.toHaveBeenCalled();
  });

  it("falls through to 500 when errorMap returns null", async () => {
    const handler = vi.fn(async () => {
      throw new Error("unknown");
    });
    const wrapped = withErrorHandler(handler, "api.test.map-fallthrough", {
      errorMap: () => null,
    });
    const res = await wrapped(makeReq());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
    expect(loggerErrorSpy).toHaveBeenCalledTimes(1);
  });

  it("falls through to 500 when errorMap itself throws", async () => {
    const handler = vi.fn(async () => {
      throw new Error("boom");
    });
    const wrapped = withErrorHandler(handler, "api.test.map-throws", {
      errorMap: () => {
        throw new Error("errorMap exploded");
      },
    });
    const res = await wrapped(makeReq());
    expect(res.status).toBe(500);
    // Two error logs: one for the map throw, one for the original.
    expect(loggerErrorSpy).toHaveBeenCalledTimes(2);
  });
});

describe("withErrorHandler — non-Error throws", () => {
  it("handles handler rejecting with a string", async () => {
    const handler = vi.fn(async () => {
      throw "naked string"; // eslint-disable-line no-throw-literal
    });
    const wrapped = withErrorHandler(handler, "api.test.naked");
    const res = await wrapped(makeReq());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
    expect(loggerErrorSpy).toHaveBeenCalledTimes(1);
  });
});
