#!/usr/bin/env node
// Generates a sample .FIT workout file for validation with Garmin FIT SDK Validator.
// Usage: node tools/test_fit_generation.js
// Output: tools/test_workout.fit

const fs = require("fs");
const path = require("path");

// ─── FIT Protocol Constants ────────────────────────────────────────────────────

const FIT_EPOCH_OFFSET = 631065600;
const MESG_FILE_ID = 0;
const MESG_WORKOUT = 26;
const MESG_WORKOUT_STEP = 27;

const FILE_TYPE_WORKOUT = 5;
const MANUFACTURER_DEVELOPMENT = 255;

const DUR_TIME = 0;
const DUR_DISTANCE = 1;
const DUR_OPEN = 14;
const DUR_REPEAT_UNTIL_STEPS_CMPLT = 28;

const TARGET_SPEED = 0;
const TARGET_HEART_RATE = 1;
const TARGET_OPEN = 2;

const INTENSITY_ACTIVE = 0;
const INTENSITY_REST = 1;
const INTENSITY_WARMUP = 2;
const INTENSITY_COOLDOWN = 3;
const INTENSITY_RECOVERY = 4;

const BASE_ENUM = 0x00;
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

function crc16(data, initial = 0) {
  let crc = initial;
  for (const byte of data) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ byte) & 0xff];
  }
  return crc;
}

// ─── Binary Writer ─────────────────────────────────────────────────────────────

class FitWriter {
  constructor() {
    this.chunks = [];
    this.dataCrc = 0;
  }

  writeUint8(v) {
    const b = Buffer.from([v & 0xff]);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeUint16(v) {
    const b = Buffer.alloc(2);
    b.writeUInt16LE(v, 0);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeUint32(v) {
    const b = Buffer.alloc(4);
    b.writeUInt32LE(v, 0);
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  writeString(s, size) {
    const b = Buffer.alloc(size);
    b.write(s, 0, size - 1, "utf8");
    this.chunks.push(b);
    this.dataCrc = crc16(b, this.dataCrc);
  }

  getDataSize() {
    return this.chunks.reduce((sum, c) => sum + c.length, 0);
  }

  getDataCrc() {
    return this.dataCrc;
  }

  toBuffer() {
    return Buffer.concat(this.chunks);
  }
}

// ─── Step Builder ──────────────────────────────────────────────────────────────

function paceToSpeed(secPerKm) {
  if (secPerKm <= 0) return 0;
  return Math.round((1_000_000 / secPerKm) * 1000);
}

function blockToIntensity(type) {
  switch (type) {
    case "warmup": return INTENSITY_WARMUP;
    case "cooldown": return INTENSITY_COOLDOWN;
    case "recovery": return INTENSITY_RECOVERY;
    case "rest": return INTENSITY_REST;
    default: return INTENSITY_ACTIVE;
  }
}

function blockToFitStep(block) {
  let durationType = DUR_OPEN;
  let durationValue = 0;

  if (block.duration_seconds > 0) {
    durationType = DUR_TIME;
    durationValue = block.duration_seconds * 1000;
  } else if (block.distance_meters > 0) {
    durationType = DUR_DISTANCE;
    durationValue = block.distance_meters * 100;
  }

  let targetType = TARGET_OPEN;
  let targetValue = 0;
  let customLow = 0;
  let customHigh = 0;

  if (block.target_pace_min_sec_per_km && block.target_pace_max_sec_per_km) {
    targetType = TARGET_SPEED;
    targetValue = 0;
    customLow = paceToSpeed(block.target_pace_max_sec_per_km);
    customHigh = paceToSpeed(block.target_pace_min_sec_per_km);
  } else if (block.target_hr_min && block.target_hr_max) {
    targetType = TARGET_HEART_RATE;
    targetValue = 0;
    customLow = block.target_hr_min + 100;
    customHigh = block.target_hr_max + 100;
  } else if (block.target_hr_zone) {
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

function expandBlocks(blocks) {
  const steps = [];
  let i = 0;
  while (i < blocks.length) {
    const block = blocks[i];
    if (block.block_type === "repeat") {
      const repeatCount = block.repeat_count || 1;
      const repeatStartIndex = steps.length;
      i++;
      const innerBlocks = [];
      while (i < blocks.length && blocks[i].block_type !== "repeat") {
        innerBlocks.push(blocks[i]);
        i++;
      }
      for (const inner of innerBlocks) {
        steps.push(blockToFitStep(inner));
      }
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

function buildFitWorkout(name, blocks) {
  const fitSteps = expandBlocks(blocks);
  const numSteps = fitSteps.length;
  const WKT_NAME_SIZE = 40;
  const writer = new FitWriter();

  // Definition: File ID (local 0)
  writer.writeUint8(0x40);
  writer.writeUint8(0);
  writer.writeUint8(0);
  writer.writeUint16(MESG_FILE_ID);
  writer.writeUint8(4);
  writer.writeUint8(0); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  writer.writeUint8(1); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  writer.writeUint8(2); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  writer.writeUint8(4); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);

  // Data: File ID
  writer.writeUint8(0x00);
  writer.writeUint8(FILE_TYPE_WORKOUT);
  writer.writeUint16(MANUFACTURER_DEVELOPMENT);
  writer.writeUint16(0);
  const fitTimestamp = Math.floor(Date.now() / 1000) - FIT_EPOCH_OFFSET;
  writer.writeUint32(fitTimestamp);

  // Definition: Workout (local 1)
  writer.writeUint8(0x41);
  writer.writeUint8(0);
  writer.writeUint8(0);
  writer.writeUint16(MESG_WORKOUT);
  writer.writeUint8(3);
  writer.writeUint8(4); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  writer.writeUint8(6); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  writer.writeUint8(8); writer.writeUint8(WKT_NAME_SIZE); writer.writeUint8(BASE_STRING);

  // Data: Workout
  writer.writeUint8(0x01);
  writer.writeUint8(1); // sport = running
  writer.writeUint16(numSteps);
  writer.writeString(name, WKT_NAME_SIZE);

  // Definition: Workout Step (local 2)
  writer.writeUint8(0x42);
  writer.writeUint8(0);
  writer.writeUint8(0);
  writer.writeUint16(MESG_WORKOUT_STEP);
  writer.writeUint8(8);
  writer.writeUint8(254); writer.writeUint8(2); writer.writeUint8(BASE_UINT16);
  writer.writeUint8(1); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  writer.writeUint8(2); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  writer.writeUint8(3); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);
  writer.writeUint8(4); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  writer.writeUint8(5); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  writer.writeUint8(6); writer.writeUint8(4); writer.writeUint8(BASE_UINT32);
  writer.writeUint8(7); writer.writeUint8(1); writer.writeUint8(BASE_ENUM);

  // Data: Workout Steps
  for (let i = 0; i < fitSteps.length; i++) {
    const step = fitSteps[i];
    writer.writeUint8(0x02);
    writer.writeUint16(i);
    writer.writeUint8(step.durationType);
    writer.writeUint32(step.durationValue);
    writer.writeUint8(step.targetType);
    writer.writeUint32(step.targetValue);
    writer.writeUint32(step.customLow);
    writer.writeUint32(step.customHigh);
    writer.writeUint8(step.intensity);
  }

  // Assemble file
  const dataBytes = writer.toBuffer();
  const dataSize = dataBytes.length;

  const header = Buffer.alloc(14);
  header[0] = 14;
  header[1] = 0x20;
  header.writeUInt16LE(2064, 2);
  header.writeUInt32LE(dataSize, 4);
  header[8] = 0x2E;
  header[9] = 0x46;
  header[10] = 0x49;
  header[11] = 0x54;
  const headerCrc = crc16(header.subarray(0, 12));
  header.writeUInt16LE(headerCrc, 12);

  const dataCrcValue = writer.getDataCrc();
  const crcBytes = Buffer.alloc(2);
  crcBytes.writeUInt16LE(dataCrcValue, 0);

  return Buffer.concat([header, dataBytes, crcBytes]);
}

// ─── Test Workout ──────────────────────────────────────────────────────────────

const testBlocks = [
  { block_type: "warmup", duration_seconds: 600, distance_meters: null, target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null, target_hr_zone: null, target_hr_min: null, target_hr_max: null, repeat_count: null, notes: null },
  { block_type: "repeat", duration_seconds: null, distance_meters: null, target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null, target_hr_zone: null, target_hr_min: null, target_hr_max: null, repeat_count: 5, notes: null },
  { block_type: "interval", duration_seconds: null, distance_meters: 1000, target_pace_min_sec_per_km: 270, target_pace_max_sec_per_km: 300, target_hr_zone: null, target_hr_min: null, target_hr_max: null, repeat_count: null, notes: null },
  { block_type: "recovery", duration_seconds: 120, distance_meters: null, target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null, target_hr_zone: null, target_hr_min: null, target_hr_max: null, repeat_count: null, notes: null },
  { block_type: "steady", duration_seconds: null, distance_meters: 3000, target_pace_min_sec_per_km: 330, target_pace_max_sec_per_km: 360, target_hr_zone: null, target_hr_min: 140, target_hr_max: 160, repeat_count: null, notes: null },
  { block_type: "cooldown", duration_seconds: 600, distance_meters: null, target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null, target_hr_zone: null, target_hr_min: null, target_hr_max: null, repeat_count: null, notes: null },
];

const fitBuffer = buildFitWorkout("Treino Intervalado 5x1km", testBlocks);
const outPath = path.join(__dirname, "test_workout.fit");
fs.writeFileSync(outPath, fitBuffer);

console.log(`Generated: ${outPath} (${fitBuffer.length} bytes)`);
console.log(`Header CRC OK, Data size: ${fitBuffer.length - 16} bytes`);

// Basic self-validation
const headerSize = fitBuffer[0];
console.log(`Header size: ${headerSize}`);
console.log(`Protocol version: ${fitBuffer[1]}`);
const profileVersion = fitBuffer.readUInt16LE(2);
console.log(`Profile version: ${profileVersion}`);
const dataSize = fitBuffer.readUInt32LE(4);
console.log(`Data size: ${dataSize}`);
const dataType = fitBuffer.toString("ascii", 8, 12);
console.log(`Data type: "${dataType}"`);
const storedHeaderCrc = fitBuffer.readUInt16LE(12);
const calcHeaderCrc = crc16(fitBuffer.subarray(0, 12));
console.log(`Header CRC: stored=0x${storedHeaderCrc.toString(16)}, calc=0x${calcHeaderCrc.toString(16)}, match=${storedHeaderCrc === calcHeaderCrc}`);

const dataEnd = 14 + dataSize;
const storedDataCrc = fitBuffer.readUInt16LE(dataEnd);
const calcDataCrc = crc16(fitBuffer.subarray(14, dataEnd));
console.log(`Data CRC: stored=0x${storedDataCrc.toString(16)}, calc=0x${calcDataCrc.toString(16)}, match=${storedDataCrc === calcDataCrc}`);
console.log(`Total file size: ${fitBuffer.length}, expected: ${14 + dataSize + 2}, match=${fitBuffer.length === 14 + dataSize + 2}`);

if (storedHeaderCrc === calcHeaderCrc && storedDataCrc === calcDataCrc) {
  console.log("\n✓ Self-validation PASSED: CRC checks OK");
} else {
  console.log("\n✗ Self-validation FAILED");
  process.exit(1);
}
