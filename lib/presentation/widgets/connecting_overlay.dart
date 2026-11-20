import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/connect_session.dart';
import '../../application/controllers.dart';
import '../../application/providers.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';

/// Modal progress card that walks through each [ConnectStage].
class ConnectingOverlay extends ConsumerWidget {
  const ConnectingOverlay({super.key, required this.state});

  final SessionConnecting state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.18),
          child: Center(
            child: SizedBox(
              width: 400,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.connectingTo(state.profile.displayName), style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 20),
                      for (final stage in ConnectStage.values)
                        _StageRow(
                          label: l10n.stage(stage),
                          status: stage.index.compareTo(state.stage.index),
                          muted: colors.muted,
                        ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: ref.read(sessionProvider.notifier).cancel,
                          child: Text(l10n.cancel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  /// [status] < 0: done, 0: in progress, > 0: pending.
  const _StageRow({required this.label, required this.status, required this.muted});

  final String label;
  final int status;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      < 0 => const Icon(Icons.check_circle_rounded, size: 20, color: Palette.sage),
      0 => const SizedBox.square(dimension: 20, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.2))),
      _ => Icon(Icons.circle_outlined, size: 20, color: muted.withValues(alpha: 0.5)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: status > 0 ? muted : null, fontWeight: status == 0 ? FontWeight.w600 : null)),
        ],
      ),
    );
  }
}
