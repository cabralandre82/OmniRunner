import { NextRequest, NextResponse } from "next/server";
import { logger } from "./logger";

// Flexible context type that covers both parameterized and param-less routes
type RouteContext = { params?: Record<string, string | string[]> };
type ApiHandler = (req: NextRequest, context: RouteContext) => Promise<NextResponse>;

export function withErrorHandler(handler: ApiHandler, routeName: string): ApiHandler {
  return async (req: NextRequest, context: RouteContext) => {
    const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();
    try {
      return await handler(req, context);
    } catch (error) {
      logger.error(`API error in ${routeName}`, error, {
        requestId,
        method: req.method,
        url: req.nextUrl.pathname,
      });
      return NextResponse.json(
        { error: "Erro interno do servidor" },
        { status: 500, headers: { "x-request-id": requestId } }
      );
    }
  };
}
