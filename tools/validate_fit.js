#!/usr/bin/env node
// Validates a .FIT workout file using fit-file-parser (same parser Garmin uses)
// Usage: node tools/validate_fit.js tools/test_workout.fit

const fs = require("fs");
const FitParser = require("fit-file-parser").default;

const filePath = process.argv[2] || "tools/test_workout.fit";

if (!fs.existsSync(filePath)) {
  console.error(`File not found: ${filePath}`);
  process.exit(1);
}

const fitParser = new FitParser({
  force: false,
  speedUnit: "km/h",
  lengthUnit: "km",
  elapsedRecordField: false,
});

const content = fs.readFileSync(filePath);

fitParser.parse(content, (error, data) => {
  if (error) {
    console.error("✗ VALIDATION FAILED:", error);
    process.exit(1);
  }

  console.log("✓ FIT file parsed successfully!\n");

  // File ID
  if (data.file_id) {
    const fid = data.file_id;
    console.log("File ID:");
    console.log(`  Type: ${fid.type}`);
    console.log(`  Manufacturer: ${fid.manufacturer}`);
    console.log(`  Product: ${fid.product}`);
    console.log(`  Time Created: ${fid.time_created}`);
  }

  // Workout
  if (data.workout) {
    const w = data.workout;
    console.log("\nWorkout:");
    console.log(`  Name: ${w.wkt_name || w.name || "?"}`);
    console.log(`  Sport: ${w.sport}`);
    console.log(`  Num Steps: ${w.num_valid_steps}`);
  }

  // Workout Steps
  if (data.workout_steps && data.workout_steps.length > 0) {
    console.log(`\nWorkout Steps (${data.workout_steps.length}):`);
    for (const step of data.workout_steps) {
      const parts = [`  Step ${step.message_index ?? "?"}:`];
      parts.push(`dur=${step.duration_type}`);
      if (step.duration_value != null) parts.push(`durVal=${step.duration_value}`);
      parts.push(`target=${step.target_type}`);
      if (step.target_value != null) parts.push(`tgtVal=${step.target_value}`);
      if (step.custom_target_value_low != null) parts.push(`low=${step.custom_target_value_low}`);
      if (step.custom_target_value_high != null) parts.push(`high=${step.custom_target_value_high}`);
      parts.push(`intensity=${step.intensity}`);
      console.log(parts.join(" | "));
    }
  }

  // Summary
  const stepCount = data.workout_steps?.length ?? 0;
  const hasFileId = !!data.file_id;
  const hasWorkout = !!data.workout;

  console.log("\n═══════════════════════════════════");
  console.log("VALIDATION SUMMARY:");
  console.log(`  File ID present: ${hasFileId ? "✓" : "✗"}`);
  console.log(`  Workout message present: ${hasWorkout ? "✓" : "✗"}`);
  console.log(`  Workout steps: ${stepCount}`);
  console.log(`  Sport: ${data.workout?.sport ?? "N/A"}`);

  if (hasFileId && hasWorkout && stepCount > 0) {
    console.log("\n✓ ALL CHECKS PASSED — File is a valid .FIT workout");
  } else {
    console.log("\n✗ VALIDATION INCOMPLETE — Missing required messages");
    process.exit(1);
  }
});
