import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class _AvatarCacheManager {
  static const key = 'omni_avatar_cache';
  static final instance = CacheManager(
    Config(
      key,
      maxNrOfCacheObjects: 500,
      stalePeriod: const Duration(days: 7),
    ),
  );
}

class CachedAvatar extends StatelessWidget {
  final String? url;
  final String fallbackText;
  final double radius;

  const CachedAvatar({
    super.key,
    this.url,
    required this.fallbackText,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: Text(
          _initials(fallbackText),
          style: TextStyle(
            fontSize: radius * 0.7,
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      cacheManager: _AvatarCacheManager.instance,
      imageBuilder: (_, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
      ),
      placeholder: (_, __) => CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) => CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: Text(
          _initials(fallbackText),
          style: TextStyle(
            fontSize: radius * 0.7,
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
      ),
    );
  }

  @visibleForTesting
  static String initialsOf(String name) => _initials(name);

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }
}
