import 'package:flutter/material.dart';

import '../../domain/entities/keyboard.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Floating pill of session controls. Purely presentational: every action is
/// a callback, so the page decides what each one means.
class SessionToolbar extends StatelessWidget {
  const SessionToolbar({
    super.key,
    required this.title,
    required this.fullScreen,
    required this.statsOn,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.onToggleStats,
    required this.onToggleFullScreen,
    required this.onRefresh,
    required this.onSendKeys,
    required this.onDisconnect,
  });

  final String title;
  final bool fullScreen, statsOn, settingsOpen;
  final VoidCallback onToggleSettings, onToggleStats, onToggleFullScreen, onRefresh, onDisconnect;
  final ValueChanged<List<int>> onSendKeys;

  static const _combos = <String, List<int>>{
    'Ctrl + Alt + Del': [Keysym.controlL, Keysym.altL, Keysym.delete],
    'Alt + Tab': [Keysym.altL, Keysym.tab],
    'super': [Keysym.superL],
    'print': [Keysym.print],
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    Widget toggle(IconData icon, String tip, bool on, VoidCallback onTap) => IconButton(
          tooltip: tip,
          isSelected: on,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: on ? Palette.clay.withValues(alpha: 0.16) : null,
            foregroundColor: on ? Palette.clay : colors.muted,
          ),
          onPressed: onTap,
        );
    final divider = Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: colors.line);

    return Glass(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          divider,
          toggle(Icons.tune_rounded, l10n.streamSettings, settingsOpen, onToggleSettings),
          toggle(Icons.query_stats_rounded, l10n.statsOverlay, statsOn, onToggleStats),
          PopupMenuButton<List<int>>(
            tooltip: l10n.sendKeys,
            icon: Icon(Icons.keyboard_command_key_rounded, size: 20, color: colors.muted),
            onSelected: onSendKeys,
            itemBuilder: (_) => [
              for (final MapEntry(:key, :value) in _combos.entries)
                PopupMenuItem(
                  value: value,
                  child: Text(switch (key) { 'super' => l10n.keySuper, 'print' => l10n.keyPrintScreen, _ => key }),
                ),
            ],
          ),
          toggle(Icons.refresh_rounded, l10n.refreshScreen, false, onRefresh),
          toggle(
            fullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            fullScreen ? l10n.exitFullScreen : l10n.fullScreen,
            false,
            onToggleFullScreen,
          ),
          divider,
          IconButton(
            tooltip: l10n.disconnect,
            icon: const Icon(Icons.power_settings_new_rounded, size: 20),
            style: IconButton.styleFrom(foregroundColor: colors.danger),
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}
