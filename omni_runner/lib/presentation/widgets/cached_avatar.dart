import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
