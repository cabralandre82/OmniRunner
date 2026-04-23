/**
 * L09-05 — IOF primitive barrel.
 *
 * Pure-domain module: no IO, no imports of service clients, no
 * platform-specific APIs.  Safe to import from edge, node, workers,
 * tests and tools.
 */

export * from "./types";
export { computeIof } from "./calculator";
