import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/composition_root.dart';
import 'data/platform/native_window_controller.dart';
import 'presentation/pixel_remote_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  final window = NativeWindowController.create(
    title: 'PixelRemote',
    size: const Size(1180, 800),
    minimumSize: const Size(760, 560),
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(
    ProviderScope(
      overrides: compositionRoot(prefs: prefs, navigatorKey: navigatorKey, window: window),
      child: PixelRemoteApp(navigatorKey: navigatorKey),
    ),
  );
}
