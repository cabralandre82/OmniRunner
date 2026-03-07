import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { handleCors } from "../_shared/cors.ts";
import { jsonErr } from "../_shared/http.ts";

// ─── FIT Protocol Constants ────────────────────────────────────────────────────

const FIT_EPOCH_OFFSET = 631065600; // seconds between Unix epoch and FIT epoch (1989-12-31)

const MESG_FILE_ID = 0;
const MESG_WORKOUT = 26;
const MESG_WORKOUT_STEP = 27;

const FILE_TYPE_WORKOUT = 5;
const SPORT_RUNNING = 1;
const SUB_SPORT_GENERIC = 0;
const MANUFACTURER_DEVELOPMENT = 255;

// Duration types
const DUR_TIME = 0;
const DUR_DISTANCE = 1;
const DUR_OPEN = 14;
const DUR_REPEAT_UNTIL_STEPS_CMPLT = 28;

// Target types
const TARGET_SPEED = 0;
const TARGET_HEART_RATE = 1;
const TARGET_OPEN = 2;

// Intensity
const INTENSITY_ACTIVE = 0;
const INTENSITY_REST = 1;
const INTENSITY_WARMUP = 2;
const INTENSITY_COOLDOWN = 3;
const INTENSITY_RECOVERY = 4;

// Base types
const BASE_ENUM = 0x00;
const BASE_UINT8 = 0x02;
const BASE_UINT16 = 0x84;
const BASE_UINT32 = 0x86;
const BASE_STRING = 0x07;

// ─── CRC-16 ────────────────────────────────────────────────────────────────────

const CRC_TABLE = new Uint16Array(256);
for (let i = 0; i < 256; i++) {
  let crc = i;
  for (let j = 0; j < 8; j++) {
    crc = crc & 1 ? (crc >>> 1) ^ 0xA001 : crc >>> 1;
  }
  CRC_TABLE[i] = crc;
}

function crc16(data: Uint8Array, initial = 0): number {
  let crc = initial;
  for (const byte of data) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ byte) & 0xff];
  }
  return crc;
}

// ─── Binary Writer ─────────────────────────────────────────────────────────────

class FitWriter {
  private chunks: Uint8Array[] = [];
  private dataCrc = 0;

  writeUint8(v: number) {
    const b = new Uint8Array([v & 0xff]);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeUint16(v: number) {
    const b = new Uint8Array(2);
    new DataView(b.buffer).setUint16(0, v, true);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeUint32(v: number) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, v, true);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeString(s: string, size: number) {
    const encoder = new TextEncoder();
    const encoded = encoder.encode(s);
    const b = new Uint8Array(size);
    b.set(encoded.subarray(0, size - 1));
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  getDataSize(): number {
    return this.chunks.reduce((sum, c) => sum + c.length, 0);
  }

  getDataCrc(): number {
    return this.dataCrc;
  }

  toBytes(): Uint8Array {
    const total = this.chunks.reduce((s, c) => s + c.length, 0);
    const result = new Uint8Array(total);
    let offset = 0;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }
}

// ─── FIT Workout File Builder ──────────────────────────────────────────────────

interface WorkoutBlock {
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  repeat_count: number | null;
  notes: string | null;
  order_index: number;
}

function blockToIntensity(type: string): number {
  switch (type) {
    case "warmup": return INTENSITY_WARMUP;
    case "cooldown": return INTENSITY_COOLDOWN;
    case "recovery": return INTENSITY_RECOVERY;
    case "rest": return INTENSITY_REST;
    default: return INTENSITY_ACTIVE;
  }
}

function paceToSpeed(secPerKm: number): number {
  if (secPerKm <= 0) return 0;
  return Math.round((1_000_000 / secPerKm) * 1000); // mm/s * 1000 for FIT scale
}

function buildFitWorkout(name: string, blocks: WorkoutBlock[]): Uint8Array {
  const fitSteps = expandBlocks(blocks);
  const numSteps = fitSteps.length;
  const WKT_NAME_SIZE = 40;

  const writer = new FitWriter();

  // ── Definition: File ID (local 0) ──
  writer.writeUint8(0x40); // definition, local 0
  writer.writeUint8(0);    // reserved
  writer.writeUint8(0);    // little-endian
  writer.writeUint16(MESG_FILE_ID);
  writer.writeUint8(4);    // 4 fields
  // type (field 0): enum, 1 byte
  writer.writeUint8(0); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  // manufacturer (field 1): uint16, 2 bytes
  writer.writeUint8(1); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  // product (field 2): uint16, 2 bytes
  writer.writeUint8(2); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  // time_created (field 4): uint32, 4 bytes
  writer.writeUint8(4); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);

  // ── Data: File ID ──
  writer.writeUint8(0x00); // data, local 0
  writer.writeUint8(FILE_TYPE_WORKOUT);
  writer.writeUint16(MANUFACTURER_DEVELOPMENT);
  writer.writeUint16(0); // product
  const fitTimestamp = Math.floor(Date.now() / 1000) - FIT_EPOCH_OFFSET;
  writer.writeUint32(fitTimestamp);

  // ── Definition: Workout (local 1) ──
  writer.writeUint8(0x41); // definition, local 1
  writer.writeUint8(0);
  writer.writeUint8(0);
  writer.writeUint16(MESG_WORKOUT);
  writer.writeUint8(3); // 3 fields
  // sport (field 4): enum
  writer.writeUint8(4); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  // num_valid_steps (field 6): uint16
  writer.writeUint8(6); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  // wkt_name (field 8): string
  writer.writeUint8(8); writer.writeUint8(WKT_NAME_SIZE); writer.writeUint8(BASE_STRING);

  // ── Data: Workout ──
  writer.writeUint8(0x01); // data, local 1
  writer.writeUint8(SPORT_RUNNING);
  writer.writeUint16(numSteps);
  writer.writeString(name, WKT_NAME_SIZE);

  // ── Definition: Workout Step (local 2) ──
  writer.writeUint8(0x42); // definition, local 2
  writer.writeUint8(0);
  writer.writeUint8(0);
  writer.writeUint16(MESG_WORKOUT_STEP);
  writer.writeUint8(8); // 8 fields
  // message_index (field 254): uint16
  writer.writeUint8(254); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  // duration_type (field 1): enum
  writer.writeUint8(1); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  // duration_value (field 2): uint32
  writer.writeUint8(2); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  // target_type (field 3): enum
  writer.writeUint8(3); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  // target_value (field 4): uint32
  writer.writeUint8(4); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  // custom_target_value_low (field 5): uint32
  writer.writeUint8(5); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  // custom_target_value_high (field 6): uint32
  writer.writeUint8(6); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  // intensity (field 7): enum
  writer.writeUint8(7); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);

  // ── Data: Workout Steps ──
  for (let i = 0; i < fitSteps.length; i++) {
    const step = fitSteps[i];
    writer.writeUint8(0x02); // data, local 2
    writer.writeUint16(i);   // message_index

    writer.writeUint8(step.durationType);
    writer.writeUint32(step.durationValue);
    writer.writeUint8(step.targetType);
    writer.writeUint32(step.targetValue);
    writer.writeUint32(step.customLow);
    writer.writeUint32(step.customHigh);
    writer.writeUint8(step.intensity);
  }

  // ── Assemble file ──
  const dataBytes = writer.toBytes();
  const dataSize = dataBytes.length;

  // File header (14 bytes)
  const header = new Uint8Array(14);
  const hv = new DataView(header.buffer);
  header[0] = 14;    // header size
  header[1] = 0x20;  // protocol version 2.0
  hv.setUint16(2, 2064, true); // profile version
  hv.setUint32(4, dataSize, true);
  header[8] = 0x2E;  // '.'
  header[9] = 0x46;  // 'F'
  header[10] = 0x49; // 'I'
  header[11] = 0x54; // 'T'
  const headerCrc = crc16(header.subarray(0, 12));
  hv.setUint16(12, headerCrc, true);

  // Data CRC
  const dataCrcValue = writer.getDataCrc();
  const crcBytes = new Uint8Array(2);
  new DataView(crcBytes.buffer).setUint16(0, dataCrcValue, true);

  // Combine: header + data + crc
  const file = new Uint8Array(14 + dataSize + 2);
  file.set(header, 0);
  file.set(dataBytes, 14);
  file.set(crcBytes, 14 + dataSize);

  return file;
}

interface FitStep {
  durationType: number;
  durationValue: number;
  targetType: number;
  targetValue: number;
  customLow: number;
  customHigh: number;
  intensity: number;
}

function expandBlocks(blocks: WorkoutBlock[]): FitStep[] {
  const steps: FitStep[] = [];
  let i = 0;

  while (i < blocks.length) {
    const block = blocks[i];

    if (block.block_type === "repeat") {
      const repeatCount = block.repeat_count ?? 1;
      const repeatStartIndex = steps.length;

      // Collect inner blocks (everything between repeat and next repeat/end)
      i++;
      const innerBlocks: WorkoutBlock[] = [];
      while (i < blocks.length && blocks[i].block_type !== "repeat") {
        innerBlocks.push(blocks[i]);
        i++;
      }

      // Add inner blocks as steps
      for (const inner of innerBlocks) {
        steps.push(blockToFitStep(inner));
      }

      // Add repeat step pointing back to the first inner step
      steps.push({
        durationType: DUR_REPEAT_UNTIL_STEPS_CMPLT,
        durationValue: repeatStartIndex,
        targetType: TARGET_OPEN,
        targetValue: repeatCount,
        customLow: 0,
        customHigh: 0,
        intensity: INTENSITY_ACTIVE,
      });
    } else {
      steps.push(blockToFitStep(block));
      i++;
    }
  }

  return steps;
}

function blockToFitStep(block: WorkoutBlock): FitStep {
  // Duration
  let durationType = DUR_OPEN;
  let durationValue = 0;

  if (block.duration_seconds != null && block.duration_seconds > 0) {
    durationType = DUR_TIME;
    durationValue = block.duration_seconds * 1000; // milliseconds
  } else if (block.distance_meters != null && block.distance_meters > 0) {
    durationType = DUR_DISTANCE;
    durationValue = block.distance_meters * 100; // centimeters
  }

  // Target
  let targetType = TARGET_OPEN;
  let targetValue = 0;
  let customLow = 0;
  let customHigh = 0;

  if (block.target_pace_min_sec_per_km != null && block.target_pace_max_sec_per_km != null) {
    targetType = TARGET_SPEED;
    targetValue = 0; // custom range
    // Note: "low" speed = slower pace (higher sec/km) = max pace value
    // "high" speed = faster pace (lower sec/km) = min pace value
    customLow = paceToSpeed(block.target_pace_max_sec_per_km);
    customHigh = paceToSpeed(block.target_pace_min_sec_per_km);
  } else if (block.target_hr_min != null && block.target_hr_max != null) {
    targetType = TARGET_HEART_RATE;
    targetValue = 0; // custom range
    customLow = block.target_hr_min + 100; // FIT HR offset
    customHigh = block.target_hr_max + 100;
  } else if (block.target_hr_zone != null) {
    targetType = TARGET_HEART_RATE;
    targetValue = block.target_hr_zone;
  }

  return {
    durationType,
    durationValue,
    targetType,
    targetValue,
    customLow,
    customHigh,
    intensity: blockToIntensity(block.block_type),
  };
}

// ─── Edge Function Handler ─────────────────────────────────────────────────────

serve(async (req) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (req.method === "OPTIONS") return handleCors(req);

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const { assignment_id, template_id } = await req.json();
    let templateId = template_id;
    let workoutName = "";

    if (assignment_id) {
      const { data: assignment, error: aErr } = await supabase
        .from("coaching_workout_assignments")
        .select("template_id, coaching_workout_templates(name)")
        .eq("id", assignment_id)
        .single();

      if (aErr || !assignment) {
        return new Response(JSON.stringify({ error: "Assignment not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" },
        });
      }
      templateId = assignment.template_id;
      workoutName = (assignment as any).coaching_workout_templates?.name ?? "Workout";
    }

    if (!templateId) {
      return new Response(JSON.stringify({ error: "template_id or assignment_id required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!workoutName) {
      const { data: tmpl } = await supabase
        .from("coaching_workout_templates")
        .select("name")
        .eq("id", templateId)
        .single();
      workoutName = tmpl?.name ?? "Workout";
    }

    const { data: blocks, error: bErr } = await supabase
      .from("coaching_workout_blocks")
      .select(
        "order_index, block_type, duration_seconds, distance_meters, " +
        "target_pace_min_sec_per_km, target_pace_max_sec_per_km, " +
        "target_hr_zone, target_hr_min, target_hr_max, repeat_count, notes"
      )
      .eq("template_id", templateId)
      .order("order_index");

    if (bErr || !blocks || blocks.length === 0) {
      return new Response(JSON.stringify({ error: "No workout blocks found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    const fitBytes = buildFitWorkout(workoutName, blocks as WorkoutBlock[]);

    const safeFileName = workoutName
      .replace(/[^a-zA-Z0-9_\- ]/g, "")
      .replace(/\s+/g, "_")
      .substring(0, 50);

    return new Response(fitBytes, {
      status: 200,
      headers: {
        "Content-Type": "application/octet-stream",
        "Content-Disposition": `attachment; filename="${safeFileName}.fit"`,
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-store",
      },
    });
  } catch (err) {
    console.error("generate-fit-workout error:", err);
    return jsonErr(500, "INTERNAL", err instanceof Error ? err.message : String(err), undefined, undefined, undefined, req);
  }
});
