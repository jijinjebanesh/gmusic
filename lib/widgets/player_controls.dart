import 'package:flutter/material.dart';

/// Large circular transport button used by the full player.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.playing, required this.buffering, this.onPressed});

  final bool playing;
  final bool buffering;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: buffering
                ? SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(color: scheme.onPrimary, strokeWidth: 3),
                  )
                : Icon(playing ? Icons.pause : Icons.play_arrow, size: 36, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// Seek bar with position / total labels under the slider.
class SeekBar extends StatelessWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  String _fmt(Duration? d) {
    if (d == null) return '--:--';
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final max = duration?.inMilliseconds ?? 0;
    final value = max > 0 ? position.inMilliseconds.clamp(0, max) : 0;
    return Column(
      children: [
        Slider(
          value: value.toDouble(),
          max: max > 0 ? max.toDouble() : 1.0,
          onChanged: max > 0 ? (v) => onSeek(Duration(milliseconds: v.round())) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(position), style: Theme.of(context).textTheme.bodySmall),
              Text(_fmt(duration), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
