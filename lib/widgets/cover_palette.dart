import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CoverPaletteBuilder extends StatefulWidget {
  const CoverPaletteBuilder({
    super.key,
    required this.imageUrl,
    required this.builder,
  });

  final String? imageUrl;
  final Widget Function(BuildContext context, ColorScheme colorScheme) builder;

  @override
  State<CoverPaletteBuilder> createState() => _CoverPaletteBuilderState();
}

class _CoverPaletteBuilderState extends State<CoverPaletteBuilder> {
  static const _maxCachedPalettes = 32;
  static final Map<String, ColorScheme> _palettes = {};
  static final List<String> _paletteOrder = [];

  String? _requestKey;
  ColorScheme? _resolvedScheme;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvePalette();
  }

  @override
  void didUpdateWidget(covariant CoverPaletteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolvePalette();
  }

  void _resolvePalette() {
    final source = widget.imageUrl;
    final brightness = Theme.of(context).brightness;
    if (source == null || source.isEmpty) {
      _requestKey = null;
      _resolvedScheme = null;
      _generation++;
      return;
    }

    final key = '$source|${brightness.name}';
    if (key == _requestKey) return;

    _requestKey = key;
    final generation = ++_generation;
    _resolvedScheme = _palettes[key];
    if (_resolvedScheme != null) return;

    ColorScheme.fromImageProvider(
      provider: CachedNetworkImageProvider(source),
      brightness: brightness,
    ).then(
      (scheme) {
        if (!mounted || generation != _generation || key != _requestKey) return;
        _palettes[key] = scheme;
        _paletteOrder.remove(key);
        _paletteOrder.add(key);
        while (_paletteOrder.length > _maxCachedPalettes) {
          _palettes.remove(_paletteOrder.removeAt(0));
        }
        setState(() => _resolvedScheme = scheme);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _generation || key != _requestKey) return;
        debugPrint('Could not derive player palette: $error');
        setState(() => _resolvedScheme = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _resolvedScheme ?? Theme.of(context).colorScheme);
}

Color coverPlayerTopColor(Color source) {
  final hsl = HSLColor.fromColor(source);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.18, 0.72).toDouble())
      .withLightness((hsl.lightness * 0.72).clamp(0.16, 0.36).toDouble())
      .toColor();
}

class CoverAtmosphere extends StatelessWidget {
  const CoverAtmosphere({
    super.key,
    required this.imageUrl,
    required this.colorScheme,
  });

  final String? imageUrl;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final source = imageUrl;
    final isDark = colorScheme.brightness == Brightness.dark;
    final base = colorScheme.surface;
    final scrim = isDark ? Colors.black : Colors.white;
    final top = coverPlayerTopColor(colorScheme.primary);

    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (source != null && source.isNotEmpty)
            ClipRect(
              child: Transform.scale(
                scale: 1.16,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
                  child: Opacity(
                    opacity: isDark ? 0.62 : 0.34,
                    child: CachedNetworkImage(
                      imageUrl: source,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const SizedBox.expand(),
                      errorWidget: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.46, 0.78, 1],
                colors: [
                  top.withValues(alpha: isDark ? 0.76 : 0.48),
                  Color.lerp(
                    top,
                    base,
                    isDark ? 0.38 : 0.62,
                  )!.withValues(alpha: 0.86),
                  base.withValues(alpha: 0.9),
                  base.withValues(alpha: 0.98),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scrim.withValues(alpha: isDark ? 0.05 : 0.02),
                  scrim.withValues(alpha: isDark ? 0.2 : 0.07),
                  scrim.withValues(alpha: isDark ? 0.72 : 0.2),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
