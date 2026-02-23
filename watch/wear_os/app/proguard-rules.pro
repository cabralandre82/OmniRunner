# Omni Runner Watch — WearOS ProGuard Rules
# Keep Health Services and DataLayer classes used via reflection
-keep class androidx.health.services.** { *; }
-keep class com.google.android.gms.wearable.** { *; }
