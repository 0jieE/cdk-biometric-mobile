import 'package:flutter/material.dart';

/// The Colegio de Kidapawan seal. Falls back to a text wordmark if the asset
/// is missing so the app still builds/renders.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96, this.onLight = false});

  /// Rendered width/height of the logo.
  final double size;

  /// When true, the wordmark fallback uses light text (for dark/gradient bg).
  final bool onLight;

  static const _assetPath = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          _Wordmark(size: size, onLight: onLight),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.size, required this.onLight});
  final double size;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final color = onLight
        ? Colors.white
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        'CDK',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.28,
        ),
      ),
    );
  }
}
