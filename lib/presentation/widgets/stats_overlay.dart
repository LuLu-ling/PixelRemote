import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/session_stats.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Draggable floating panel with live latency, loss, bandwidth and frame rate.
class StatsOverlay extends ConsumerStatefulWidget {
  const StatsOverlay({super.key, required this.targetFps, required this.onClose});

  final int targetFps;
  final VoidCallback onClose;

  @override
  ConsumerState<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends ConsumerState<StatsOverlay> {
  static const _width = 236.0, _historyLength = 60;
  final _history = <double>[];
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionStatsProvider, (_, next) {
      if (next.value case final s?) {
        _history.add(s.rxBitsPerSecond);
        if (_history.length > _historyLength) _history.removeAt(0);
      }
    });
    final stats = ref.watch(sessionStatsProvider).value ?? SessionStats.empty;
    final screen = MediaQuery.sizeOf(context);
    final offset = _offset ?? Offset(screen.width - _width - 20, screen.height - 300);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final rttMs = stats.rtt?.inMicroseconds == null ? null : stats.rtt!.inMicroseconds / 1000;
    final health = rttMs == null
        ? colors.muted
        : (rttMs < 60 && stats.lossPercent < 1)
            ? colors.success
            : (rttMs < 150 && stats.lossPercent < 5)
                ? colors.warning
                : colors.danger;

    return Positioned(
      left: offset.dx.clamp(0, max(0, screen.width - _width)),
      top: offset.dy.clamp(0, max(0, screen.height - 60)),
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _offset = offset + d.delta),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Glass(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
            child: SizedBox(
              width: _width - 22,
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: health, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.statsTitle, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          tooltip: l10n.close,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _row(l10n.statsLatency, rttMs == null ? '—' : '${rttMs.toStringAsFixed(rttMs < 10 ? 1 : 0)} ms'),
                    Tooltip(
                      message: l10n.statsLossHint,
                      child: _row(l10n.statsLoss, '${stats.lossPercent.toStringAsFixed(1)} %'),
                    ),
                    _row(l10n.statsDown, _rate(stats.rxBitsPerSecond)),
                    _row(l10n.statsUp, _rate(stats.txBitsPerSecond)),
                    _row(l10n.statsFrameRate, '${stats.fps.round()} / ${widget.targetFps}'),
                    _row(l10n.statsResolution, stats.width == 0 ? '—' : '${stats.width} × ${stats.height}'),
                    _row(l10n.statsEncoding, stats.encoding ?? '—'),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SizedBox(
                        height: 34,
                        child: CustomPaint(painter: _Sparkline(List.of(_history), Palette.clay, colors.line)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 10, top: 3, bottom: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: AppColors.of(context).muted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  static String _rate(double bps) => switch (bps) {
        >= 1e6 => '${(bps / 1e6).toStringAsFixed(1)} Mb/s',
        >= 1e3 => '${(bps / 1e3).toStringAsFixed(0)} kb/s',
        _ => '${bps.toStringAsFixed(0)} b/s',
      };
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color, this.baseline);

  final List<double> values;
  final Color color, baseline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = baseline);
    if (values.length < 2) return;
    final peak = values.reduce(max).clamp(1.0, double.infinity);
    final dx = size.width / (_StatsOverlayState._historyLength - 1);
    final start = size.width - dx * (values.length - 1);
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(start + i * dx, size.height - values[i] / peak * (size.height - 2));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(start, size.height)
      ..close();
    canvas
      ..drawPath(fill, Paint()..color = color.withValues(alpha: 0.14))
      ..drawPath(line, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_Sparkline old) => true;
}
