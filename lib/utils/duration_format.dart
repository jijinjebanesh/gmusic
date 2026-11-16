/// "mm:ss" (or "h:mm:ss" past an hour). Unknown durations render as "--:--".
String formatDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return '--:--';
  final total = duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
