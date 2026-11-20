import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The PixelRemote mark: a 2×2 pixel cluster with one lit pixel.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(Theme.of(context).colorScheme.onSurface)),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.12, cell = (size.width - gap) / 2;
    final colors = [ink, Palette.clay, ink, ink.withValues(alpha: 0.28)];
    for (var i = 0; i < 4; i++) {
      final rect = Rect.fromLTWH((i % 2) * (cell + gap), (i ~/ 2) * (cell + gap), cell, cell);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.28)), Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(),
          const SizedBox(width: 10),
          Text('PixelRemote', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21)),
        ],
      );
}

/// Frosted, translucent surface for controls floating over the remote screen.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 16, this.padding = EdgeInsets.zero});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.84),
              borderRadius: shape,
              border: Border.all(color: AppColors.of(context).line),
            ),
            // Ink (hover, splashes) must paint above the frosted fill, not under it.
            child: Material(type: MaterialType.transparency, child: Padding(padding: padding, child: child)),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase label above a group of controls.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.of(context).muted,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [Expanded(child: Text(text.toUpperCase(), style: style)), ?trailing]),
    );
  }
}

/// A dropdown styled like the theme's text fields.
class Select<T> extends StatelessWidget {
  const Select({super.key, required this.value, required this.items, required this.label, required this.onChanged});

  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            borderRadius: BorderRadius.circular(12),
            items: [for (final item in items) DropdownMenuItem(value: item, child: Text(label(item)))],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      );
}
