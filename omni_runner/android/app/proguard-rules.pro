# ─────────────────────────────────────────────────────────────────────────────
# Omni Runner — ProGuard / R8 keep rules (L01-30)
#
# Layered on top of `proguard-android-optimize.txt` (AGP-shipped) by
# `app/build.gradle`. The default file already covers Android framework
# classes, AndroidX, Java reflection roots, etc. — we only add what's
# required for our specific dependency mix.
#
# Audit/recovery procedure (read this first if R8 starts failing):
#   1. `flutter build apk --release` produces an R8 trace under
#      `build/app/outputs/mapping/prodRelease/missing_rules.txt` when a
#      keep rule is needed. R8 prints the suggested rule verbatim — copy
#      it into the matching section below and re-run.
#   2. To validate without provisioning a keystore, use the L01-31 escape:
#      `flutter build apk --release -PallowReleaseDebugSigning=true`.
#   3. As a last resort, uncomment the `-dontobfuscate` line below to
#      keep R8 shrinking + resource shrinking but disable renaming —
#      this is a temporary recovery toggle, NOT a permanent answer.
#
# Keep rule grouping (alphabetical within sections):
#   §1 Build-system / global toggles
#   §2 Flutter framework
#   §3 Plugins backed by JNI / reflection
#   §4 Crash reporting + observability (Sentry)
#   §5 Firebase + Google Play Services
#   §6 Supabase + Realtime + GoTrue
#   §7 Database (Drift / SQLCipher)
#   §8 Misc utilities (kotlinx, OkHttp, JSON, etc.)
#   §9 Anti-cheat — obfuscate AGGRESSIVELY (no keeps required)
# ─────────────────────────────────────────────────────────────────────────────


# ═════════════════════════════════════════════════════════════════════════════
# §1 — Global toggles
# ═════════════════════════════════════════════════════════════════════════════

# Preserve method/source info so Sentry-symbolicated stack traces are
# usable in production. Without these, R8 emits stripped frames and the
# debug-info uploader has nothing to match against.
-keepattributes SourceFile,LineNumberTable,Signature,*Annotation*,EnclosingMethod,InnerClasses

# Rename the source file to `SourceFile` to avoid leaking the full
# repo path in stack traces shipped to crash reporters.
-renamesourcefileattribute SourceFile

# Recovery escape-hatch — uncomment ONLY if a plugin breaks under R8
# renaming and there is no time to add the proper keep rule. Resource
# shrinking and code shrinking remain active, only renaming is off.
# -dontobfuscate


# ═════════════════════════════════════════════════════════════════════════════
# §2 — Flutter framework
#
# Flutter ships its own consumer ProGuard rules via the engine AAR, so
# `io.flutter.embedding.**` is mostly handled. The keeps below cover the
# bridge points the engine cannot annotate (plugin registration via
# reflection, generated `GeneratedPluginRegistrant`).
# ═════════════════════════════════════════════════════════════════════════════

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# `GeneratedPluginRegistrant` is reflectively instantiated by the engine.
-keep class com.omnirunner.omni_runner.** { *; }


# ═════════════════════════════════════════════════════════════════════════════
# §3 — JNI / reflection-heavy plugins
# ═════════════════════════════════════════════════════════════════════════════

# flutter_secure_storage — uses BouncyCastle for AES wrap on Android 22-,
# accessed via JNI from the AndroidKeystore bridge.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# flutter_local_notifications + AlarmManager scheduled receivers
-keep class com.dexterous.** { *; }

# flutter_blue_plus — registers BLE callbacks invoked from native.
-keep class com.lib.flutter_blue_plus.** { *; }

# mobile_scanner — uses ML Kit barcode reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }

# health (Health Connect) — reflectively loads response handlers.
-keep class cachet.plugins.health.** { *; }
-keep class androidx.health.** { *; }

# flutter_foreground_task — service registered in Manifest, woken via
# `PendingIntent.getActivity` from native code.
-keep class com.pravera.flutter_foreground_task.** { *; }

# geolocator — listener proxies invoked by the LocationManager system
# service.
-keep class com.baseflow.geolocator.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_web_auth_2 — registers a callback activity in the Manifest.
-keep class com.linusu.flutter_web_auth_2.** { *; }

# google_sign_in / sign_in_with_apple — Google Identity Services + Apple
# JS-WebView bridge.
-keep class com.google.android.gms.auth.** { *; }
-keep class io.aboutcode.signinwithapple.** { *; }

# image_picker / cached_network_image — kept lightly, both reach UI
# threads from native callbacks.
-keep class io.flutter.plugins.imagepicker.** { *; }

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# WearOS Wearable APIs (declared in app/build.gradle dependencies block).
-keep class com.google.android.gms.wearable.** { *; }
-keep class com.google.android.gms.tasks.** { *; }


# ═════════════════════════════════════════════════════════════════════════════
# §4 — Sentry (crash reporting + tracing)
#
# Sentry's ANR / native-crash collector reflects into NDK symbols; without
# these keeps the symbolicated stack traces in production are unusable.
# ═════════════════════════════════════════════════════════════════════════════

-keep class io.sentry.** { *; }
-dontwarn io.sentry.**


# ═════════════════════════════════════════════════════════════════════════════
# §5 — Firebase + Google Play Services
# ═════════════════════════════════════════════════════════════════════════════

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.gson.** { *; }

# Firebase Messaging onMessageReceived / token refresh callbacks.
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }

# Firebase Common — uses reflection on Component constructors.
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.platforminfo.** { *; }

-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**


# ═════════════════════════════════════════════════════════════════════════════
# §6 — Supabase / Realtime / GoTrue
#
# `supabase_flutter` is mostly Dart, but it bundles `gotrue`/`realtime` HTTP
# clients that shape JSON via Dart reflection on Android. The Kotlin side
# only carries the platform channel and the secure-token storage shim.
# ═════════════════════════════════════════════════════════════════════════════

-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# postgrest / realtime serialise model classes by name.
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}


# ═════════════════════════════════════════════════════════════════════════════
# §7 — Drift (sqflite-replacement) + SQLCipher
#
# Drift uses code generation, but the native sqlite/SQLCipher libs are
# loaded by JNI and registered prepared-statement callbacks must survive.
# ═════════════════════════════════════════════════════════════════════════════

# SQLCipher native bindings.
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }

-dontwarn net.sqlcipher.**
-dontwarn net.zetetic.**


# ═════════════════════════════════════════════════════════════════════════════
# §8 — Kotlin coroutines + OkHttp + general JVM noise
# ═════════════════════════════════════════════════════════════════════════════

-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Generic Kotlin metadata — without this R8 occasionally strips
# @Metadata annotations that Kotlin reflection needs.
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Java reflection over enums.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable (for any platform-channel argument we declare).
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Native methods (anywhere) — JNI cannot rename these.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}


# ═════════════════════════════════════════════════════════════════════════════
# §9 — Anti-cheat — obfuscate AGGRESSIVELY (no keeps)
#
# The integrity detectors at `lib/domain/usecases/integrity_detect_*` AND
# their thresholds are the literal payload an attacker would target with
# `apktool` / `jadx`. By NOT listing keep rules for them we let R8:
#
#   • rename classes from `IntegrityDetectSpeed` →  one-letter mangle;
#   • inline literal thresholds into call sites (no longer a single grep
#     target);
#   • dead-code-eliminate detector branches when feature flags strip them.
#
# This is the entire raison d'être of this finding: the threshold values
# move from "trivially recoverable" to "requires correlated-trace
# reverse-engineering across multiple sessions".
#
# If you ever ADD a `-keep` for `lib.domain.usecases.integrity_detect_*`
# you have re-opened L01-30. Don't.
# ═════════════════════════════════════════════════════════════════════════════
