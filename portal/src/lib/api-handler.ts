import { NextRequest, NextResponse } from "next/server";
import { logger } from "./logger";

type ApiHandler = (req: NextRequest) => Promise<NextResponse>;

export function withErrorHandler(handler: ApiHandler, routeName: string): ApiHandler {
  return async (req: NextRequest) => {
    const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();
    try {
      return await handler(req);
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
