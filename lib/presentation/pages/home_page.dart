import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controllers.dart';
import '../../application/providers.dart';
import '../../domain/entities/app_preferences.dart';
import '../../domain/entities/connection_profile.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/connect_card.dart';
import '../widgets/connecting_overlay.dart';
import '../widgets/recent_connections.dart';
import '../widgets/stream_settings_panel.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Profile loaded into the connect form for editing.
  final _editing = ValueNotifier<ConnectionProfile?>(null);

  @override
  void dispose() {
    _editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.homeHeadline, style: text.displaySmall),
                            const SizedBox(height: 12),
                            Text(
                              context.l10n.homeSubtitle,
                              style: text.bodyLarge?.copyWith(color: AppColors.of(context).muted, height: 1.5),
                            ),
                            const SizedBox(height: 32),
                            ConnectCard(editing: _editing, error: session is SessionIdle ? session.error : null),
                            const SizedBox(height: 44),
                            RecentConnections(onEdit: (p) => _editing.value = p),
                            const SizedBox(height: 48),
                            Center(
                              child: Text(
                                context.l10n.footer,
                                style: text.bodySmall?.copyWith(color: AppColors.of(context).muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (session is SessionConnecting) ConnectingOverlay(state: session),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prefs = ref.watch(preferencesProvider);
    final update = ref.read(preferencesProvider.notifier).update;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
      child: Row(
        children: [
          const Wordmark(),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: l10n.language,
            icon: const Icon(Icons.translate_rounded),
            initialValue: prefs.languageCode,
            onSelected: (code) => update((p) => p.copyWith(languageCode: code)),
            itemBuilder: (_) => [
              PopupMenuItem(value: '', child: Text(l10n.languageSystem)),
              const PopupMenuItem(value: 'en', child: Text('English (US)')),
              const PopupMenuItem(value: 'zh', child: Text('简体中文')),
            ],
          ),
          PopupMenuButton<AppThemeMode>(
            tooltip: l10n.appearance,
            icon: Icon(switch (prefs.themeMode) {
              AppThemeMode.system => Icons.brightness_auto_outlined,
              AppThemeMode.light => Icons.light_mode_outlined,
              AppThemeMode.dark => Icons.dark_mode_outlined,
            }),
            initialValue: prefs.themeMode,
            onSelected: (mode) => update((p) => p.copyWith(themeMode: mode)),
            itemBuilder: (_) => [
              PopupMenuItem(value: AppThemeMode.system, child: Text(l10n.themeSystem)),
              PopupMenuItem(value: AppThemeMode.light, child: Text(l10n.themeLight)),
              PopupMenuItem(value: AppThemeMode.dark, child: Text(l10n.themeDark)),
            ],
          ),
          IconButton(
            tooltip: l10n.defaultSettings,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: StreamSettingsPanel(title: l10n.defaultSettings, onClose: () => Navigator.of(context).pop()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
