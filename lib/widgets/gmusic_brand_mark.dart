import 'package:flutter/material.dart';

class GMusicBrandMark extends StatelessWidget {
  const GMusicBrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: size * 0.52,
        color: scheme.onPrimary,
      ),
    );
  }
}
