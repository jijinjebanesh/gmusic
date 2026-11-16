import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_tokens.dart';

/// Album artwork or a deterministic gradient placeholder with the track's
/// initial. Artwork URLs point at the bridge's ticket-gated `/art/:ticket`
/// endpoint, which needs no Authorization header (so it works on the web too).
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.track,
    this.size = 56,
    this.radius,
  });

  final Track track;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final artUrl = track.artUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? tokens.radiusThumb),
      child: artUrl == null
          ? _Placeholder(size: size, title: track.title)
          : CachedNetworkImage(
              imageUrl: artUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              fadeInDuration: tokens.motionFast,
              placeholder: (context, url) => _Placeholder(size: size, title: track.title),
              errorWidget: (context, url, error) => _Placeholder(size: size, title: track.title),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.title});

  final double size;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = title.trim().isEmpty ? '♪' : title.trim().characters.first.toUpperCase();
    // Hash the title so a track keeps one stable gradient colour.
    final hue = (title.hashCode % 360).abs();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromColor(scheme.primary).withHue(hue.toDouble()).toColor(),
            HSLColor.fromColor(scheme.secondary).withHue((hue + 60) % 360).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
