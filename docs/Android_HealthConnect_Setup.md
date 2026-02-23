# Android Health Connect — Setup Guide

## Overview

Health Connect is Google's unified health data API for Android, replacing
Google Fit. It requires a separate app (`com.google.android.apps.healthdata`)
installed on the device and runs as a system service on Android 14+.

The Omni Runner app uses the `health` Flutter package (v13.3.1) which wraps
Health Connect behind the same API used for HealthKit on iOS.

---

## 1. AndroidManifest.xml

### 1.1 Health Connect Permissions

All declared in `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Health Connect (read/write HR, steps, exercise, route, calories) -->
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.WRITE_STEPS"/>
<uses-permission android:name="android.permission.health.READ_EXERCISE"/>
<uses-permission android:name="android.permission.health.WRITE_EXERCISE"/>
<uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE"/>
<uses-permission android:name="android.permission.health.WRITE_EXERCISE_ROUTE"/>
<uses-permission android:name="android.permission.health.READ_DISTANCE"/>
<uses-permission android:name="android.permission.health.WRITE_DISTANCE"/>
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"/>
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY"/>
```

**Notes:**
- `READ_HEALTH_DATA_IN_BACKGROUND`: Allows reading health data when the app
  is not in the foreground. Required for background step counting.
- `READ_HEALTH_DATA_HISTORY`: Enables reading data older than 30 days.
  Without this, Health Connect restricts reads to the last 30 days from
  when permission was granted.

### 1.2 Activity Recognition

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
```

Required by Health Connect for accessing fitness data (steps, exercise).
This is a `dangerous` permission — must be requested at runtime via
`permission_handler`.

### 1.3 Queries Block

Android 11+ (API 30) requires declaring package visibility. Without this,
the app cannot detect whether Health Connect is installed.

```xml
<queries>
    <!-- Health Connect app detection -->
    <package android:name="com.google.android.apps.healthdata"/>
    <!-- Health Connect permissions rationale screen -->
    <intent>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
    </intent>
</queries>
```

### 1.4 MainActivity Intent Filter

The `health` plugin requires the permissions rationale intent-filter on
the main activity so Health Connect can route back to the app:

```xml
<activity android:name=".MainActivity" ...>
    ...
    <!-- Health Connect: show permissions rationale screen -->
    <intent-filter>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
    </intent-filter>
</activity>
```

### 1.5 Privacy Policy Activity Alias

Google Play review requires a link from the Health Connect permissions
screen to your app's privacy policy. The `ViewPermissionUsageActivity`
alias routes this intent to `MainActivity`:

```xml
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>
        <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
    </intent-filter>
</activity-alias>
```

**TODO:** Implement a privacy policy screen/route in the Flutter app that
`MainActivity` navigates to when launched via this intent.

---

## 2. MainActivity.kt

```kotlin
package com.omnirunner.omni_runner

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity()
```

**Why `FlutterFragmentActivity`?**

The `health` plugin uses `registerForActivityResult` to request Health
Connect permissions. This requires `ComponentActivity`, which
`FlutterFragmentActivity` extends but `FlutterActivity` does not. On
Android 14+ (API 34), using `FlutterActivity` causes a runtime crash
when requesting permissions.

---

## 3. build.gradle (app-level)

Key settings in `android/app/build.gradle`:

| Setting | Value | Reason |
|---------|-------|--------|
| `minSdkVersion` | 26 | Health Connect minimum requirement |
| `compileSdk` | `flutter.compileSdkVersion` | Uses Flutter's default (34+) |
| `targetSdkVersion` | `flutter.targetSdkVersion` | Android 14 target |
| `JavaVersion` | `VERSION_17` | Required by AGP 8.7 |
| `jvmTarget` | `'17'` | Kotlin compiler target matching Java |

---

## 4. gradle.properties

```properties
org.gradle.jvmargs=-Xmx4G
android.useAndroidX=true
android.enableJetifier=true
```

Both `useAndroidX` and `enableJetifier` are required by the `health`
package.

---

## 5. Health Connect Data Types Used

| Data Type | Permission | Purpose |
|-----------|-----------|---------|
| `HEART_RATE` | READ + WRITE | Read HR from watch, write BLE HR |
| `STEPS` | READ + WRITE | Read real steps for anti-cheat |
| `EXERCISE` | READ + WRITE | Write completed workouts |
| `EXERCISE_ROUTE` | READ + WRITE | Attach GPS route to workouts |
| `DISTANCE` | READ + WRITE | Read/write walking+running distance |
| `ACTIVE_CALORIES_BURNED` | READ + WRITE | Future: calorie tracking |

---

## 6. Permission Flow (Runtime)

```
1. App calls HealthPlatformService.isAvailable()
   └── checks Health Connect SDK status via getHealthConnectSdkStatus()
   └── returns sdkAvailable / sdkUnavailable / sdkUnavailableProviderUpdateRequired

2. App calls HealthPlatformService.requestPermissions(scopes)
   └── maps HealthPermissionScope → (HealthDataType, HealthDataAccess)
   └── calls Health.requestAuthorization(types, permissions)
   └── opens Health Connect permission dialog (native UI)
   └── user grants/denies individual data types

3. App calls Permission.activityRecognition.request()
   └── shows Android runtime permission dialog
   └── required before reading steps
```

**Key differences from iOS:**
- Health Connect tells you definitively if permissions were granted (`true`/`false`).
- Health Connect requires a separate app installed (or system module on Android 14+).
- No background delivery mechanism (unlike HealthKit's `enableBackgroundDelivery`).
- Data is restricted to 30 days unless `READ_HEALTH_DATA_HISTORY` is declared.

---

## 7. Environment Requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| Android API | 26 (Oreo) | `minSdkVersion` in build.gradle |
| Health Connect | Installed | System module on Android 14+, APK on older |
| Google Play Services | Not required | Health Connect is independent |
| Internet | First launch only | HC needs network for initial setup |
| AGP | 8.7.0 | Declared in `settings.gradle` |
| Gradle | 8.11.1 | Declared in `gradle-wrapper.properties` |
| Kotlin | 2.1.0 | Declared in `settings.gradle` |

---

## 8. Troubleshooting

### Health Connect not detected
- **Cause:** `com.google.android.apps.healthdata` not installed.
- **Fix:** Install from Play Store. On Android 14+ it may be a system module
  — check Settings → Apps → Health Connect.
- **Code path:** `HealthPlatformService.isAvailable()` returns `false`.

### Permission dialog not appearing
- **Cause:** `MainActivity` doesn't extend `FlutterFragmentActivity`.
- **Fix:** Verify `MainActivity.kt` uses `FlutterFragmentActivity`.
- **Cause:** Missing `ACTION_SHOW_PERMISSIONS_RATIONALE` intent-filter on
  the activity.

### "Permission denied" on steps
- **Cause:** `ACTIVITY_RECOGNITION` not granted at runtime.
- **Fix:** Call `Permission.activityRecognition.request()` before reading steps.

### Data limited to last 30 days
- **Cause:** `READ_HEALTH_DATA_HISTORY` not declared in manifest.
- **Fix:** Already added (SPRINT W3.1). Call
  `Health.requestHealthDataHistoryAuthorization()` at runtime.

### Build fails with "Cannot cast Activity to ComponentActivity"
- **Cause:** `FlutterActivity` used instead of `FlutterFragmentActivity`.
- **Fix:** Update `MainActivity.kt`.

### Google Play review rejection
- **Cause:** No privacy policy linked from Health Connect permissions screen.
- **Fix:** Implement privacy policy activity/route via `ViewPermissionUsageActivity`
  alias.

---

## 9. File Checklist

| File | Status |
|------|--------|
| `android/app/src/main/AndroidManifest.xml` | 14 HC permissions + ACTIVITY_RECOGNITION + queries + intent-filters + alias |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `FlutterFragmentActivity` |
| `android/app/build.gradle` | `minSdkVersion 26`, Java 17, Kotlin 17 |
| `android/gradle.properties` | `useAndroidX=true`, `enableJetifier=true` |
| `android/settings.gradle` | AGP 8.7.0, Kotlin 2.1.0 |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle 8.11.1 |
| `pubspec.yaml` | `health: ^13.3.1` |
