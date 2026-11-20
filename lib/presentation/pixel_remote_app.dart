import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controllers.dart';
import '../application/providers.dart';
import '../domain/entities/app_preferences.dart';
import 'l10n.dart';
import 'pages/home_page.dart';
import 'pages/session_page.dart';
import 'theme/app_theme.dart';

class PixelRemoteApp extends ConsumerWidget {
  const PixelRemoteApp({super.key, required this.navigatorKey, this.typography = googleTypography});

  final GlobalKey<NavigatorState> navigatorKey;
  final TextThemeBuilder typography;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PixelRemote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light, typography),
      darkTheme: AppTheme.build(Brightness.dark, typography),
      themeMode: switch (prefs.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      locale: switch (prefs.languageCode) {
        'en' => const Locale('en', 'US'),
        'zh' => const Locale('zh', 'CN'),
        _ => null,
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
      home: const AppShell(),
    );
  }
}

/// Shows the home screen or the live session, cross-fading between them.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      child: state is SessionActive
          ? SessionPage(key: ObjectKey(state.session), session: state.session)
          : const HomePage(key: ValueKey('home')),
    );
  }
}
