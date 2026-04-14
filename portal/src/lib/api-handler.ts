import { NextRequest, NextResponse } from "next/server";
import { logger } from "./logger";

export type ApiHandler = (req: NextRequest, context?: Record<string, unknown>) => Promise<NextResponse>;

/**
 * Wraps route handlers with consistent logging and 500 responses.
 * The second argument is forwarded as Next.js supplies it (dynamic `params`, etc.).
 */
export function withErrorHandler(
  handler: (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
  routeName: string,
): ApiHandler {
  return async (req: NextRequest, context?: Record<string, unknown>) => {
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
