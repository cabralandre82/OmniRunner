import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/presentation/map/map_style.dart';

/// Base map screen displaying a MapLibre GL map.
///
/// Uses MapTiler streets-v2 style when MAPTILER_API_KEY is provided
/// via --dart-define. Falls back to MapLibre demo tiles otherwise.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _controller;
  bool _styleLoaded = false;
  bool _mapTimedOut = false;
  Timer? _mapTimeout;

  static const _mapLoadTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _mapTimeout = Timer(_mapLoadTimeout, () {
      if (!mounted || _styleLoaded) return;
      setState(() {
        _styleLoaded = true;
        _mapTimedOut = true;
      });
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    _mapTimeout?.cancel();
    setState(() {
      _styleLoaded = true;
      _mapTimedOut = false;
    });
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (AppConfig.mapTilerApiKey.isEmpty)
            const Tooltip(
              message: 'Sem chave API — usando tiles de demonstração',
              child: Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.warning_amber, color: Colors.orange),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-15.7975, -47.8919),
              zoom: 13,
            ),
            styleString: mapStyleUrl,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            myLocationEnabled: false,
            trackCameraPosition: false,
          ),
          if (!_styleLoaded)
            const Center(child: CircularProgressIndicator()),
          if (_mapTimedOut)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Mapa indisponível',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verifique sua conexão com a internet '
                      'ou a configuração da chave MapTiler.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
