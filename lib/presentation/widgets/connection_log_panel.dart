import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/connection_log.dart';
import '../../domain/services/session_log.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';

/// Live, scrollable view of a [ConnectionLog], newest entries at the bottom.
class ConnectionLogPanel extends StatelessWidget {
  const ConnectionLogPanel({super.key, required this.log, required this.onClose, this.width = 560});

  final ConnectionLog log;
  final VoidCallback onClose;
  final double width;

  static Future<void> show(BuildContext context, ConnectionLog log) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            height: 560,
            child: ConnectionLogPanel(log: log, width: 720, onClose: () => Navigator.of(context).pop()),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'monospace'], fontSize: 12, height: 1.45);
    Color levelColor(LogLevel level) => switch (level) {
          LogLevel.debug => colors.muted,
          LogLevel.info => Theme.of(context).colorScheme.onSurface,
          LogLevel.warning => colors.warning,
          LogLevel.error => colors.danger,
        };

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(l10n.connectionLog, style: Theme.of(context).textTheme.headlineSmall)),
                TextButton.icon(
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: Text(l10n.copyLog),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: log.export()));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.copied)));
                  },
                ),
                IconButton(tooltip: l10n.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<void>(
              stream: log.changes,
              builder: (context, _) {
                final entries = log.entries;
                if (entries.isEmpty) {
                  return Center(child: Text(l10n.logEmpty, style: TextStyle(color: colors.muted)));
                }
                return SelectionArea(
                  child: ListView.builder(
                    reverse: true, // stays pinned to the newest entry
                    padding: const EdgeInsets.fromLTRB(22, 10, 18, 14),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[entries.length - 1 - i];
                      final line = e.format();
                      final split = line.indexOf('] ') + 2;
                      return Text.rich(
                        TextSpan(children: [
                          TextSpan(text: line.substring(0, split), style: TextStyle(color: colors.muted)),
                          TextSpan(text: e.message, style: TextStyle(color: levelColor(e.level))),
                        ]),
                        style: mono,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
