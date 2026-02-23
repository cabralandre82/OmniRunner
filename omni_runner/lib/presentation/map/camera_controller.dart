import 'package:maplibre_gl/maplibre_gl.dart';

/// Smooth camera follow for live tracking with optional bearing rotation.
///
/// Animates the map camera to the runner's latest GPS position.
/// Throttled to max 1 update per second to prevent motion sickness
/// and excessive GPU / battery drain.
///
/// Lifecycle:
///   1. [attach] after `onStyleLoaded`.
///   2. [update] with each new GPS coordinate.
///   3. [detach] when the screen is disposed.
///
/// The user can [disable] follow to pan the map freely,
/// and [enable] to resume tracking.
class CameraFollowController {
  MapLibreMapController? _ctrl;
  bool _following = true;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Minimum interval between camera animations (ms).
  static const throttleMs = 1000;

  /// Duration of the smooth camera animation.
  static const _animDuration = Duration(milliseconds: 600);

  /// Zoom level used during follow mode.
  static const _followZoom = 16.5;

  /// Camera tilt during follow mode (degrees). Slight 3D perspective.
  static const _followTilt = 45.0;

  // ── Lifecycle ──

  /// Bind to a [MapLibreMapController]. Call after the map style loads.
  void attach(MapLibreMapController controller) => _ctrl = controller;

  /// Release the controller reference. Safe to call multiple times.
  void detach() => _ctrl = null;

  /// Whether a controller is currently attached.
  bool get isAttached => _ctrl != null;

  // ── Follow mode ──

  /// Whether follow mode is active.
  bool get isFollowing => _following;

  /// Enable follow mode. Camera resumes tracking on next [update].
  void enable() => _following = true;

  /// Disable follow mode. Camera stays where the user panned.
  void disable() => _following = false;

  /// Toggle follow mode and return the new state.
  bool toggle() {
    _following = !_following;
    return _following;
  }

  // ── Camera updates ──

  /// Smoothly move camera to [target] with optional [bearing].
  ///
  /// When [bearing] is provided, the camera rotates to align with the
  /// runner's heading and applies a slight 3D tilt.
  ///
  /// Skipped when:
  /// - follow is disabled
  /// - no controller attached
  /// - less than [throttleMs] ms since last animation
  void update(LatLng target, {double? bearing}) {
    if (!_following || _ctrl == null) return;

    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds < throttleMs) return;

    _lastUpdate = now;
    _ctrl!.animateCamera(
      bearing != null
          ? CameraUpdate.newCameraPosition(CameraPosition(
              target: target,
              zoom: _followZoom,
              bearing: bearing,
              tilt: _followTilt,
            ))
          : CameraUpdate.newLatLng(target),
      duration: _animDuration,
    );
  }

  /// Immediately animate to [target], bypassing the throttle.
  ///
  /// Use for the first GPS fix or when re-enabling follow mode.
  void jumpTo(LatLng target, {double? bearing}) {
    if (_ctrl == null) return;
    _lastUpdate = DateTime.now();
    _ctrl!.animateCamera(
      bearing != null
          ? CameraUpdate.newCameraPosition(CameraPosition(
              target: target,
              zoom: _followZoom,
              bearing: bearing,
              tilt: _followTilt,
            ))
          : CameraUpdate.newLatLng(target),
      duration: _animDuration,
    );
  }
}
