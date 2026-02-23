import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/core/config/app_config.dart';

/// MapTiler style URL, or MapLibre demo tiles if no API key is set.
String get mapStyleUrl {
  const key = AppConfig.mapTilerApiKey;
  if (key.isEmpty) return MapLibreStyles.demo;
  return 'https://api.maptiler.com/maps/streets-v2/style.json?key=$key';
}
