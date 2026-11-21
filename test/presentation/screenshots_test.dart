// Renders key screens to PNG for visual review. Runs only when SCREENSHOT_DIR
// is set:  SCREENSHOT_DIR=/tmp/shots flutter test test/presentation/screenshots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/application/connect_session.dart';
import 'package:pixel_remote/application/controllers.dart';
import 'package:pixel_remote/application/providers.dart';
import 'package:pixel_remote/application/connection_log.dart';
import 'package:pixel_remote/application/session_monitor.dart';
import 'package:pixel_remote/domain/entities/app_preferences.dart';
import 'package:pixel_remote/domain/entities/connection_profile.dart';
import 'package:pixel_remote/domain/entities/keyboard.dart';
import 'package:pixel_remote/domain/entities/session_stats.dart';
import 'package:pixel_remote/domain/entities/ssh_address.dart';
import 'package:pixel_remote/domain/entities/stream_settings.dart';
import 'package:pixel_remote/domain/errors.dart';
import 'package:pixel_remote/domain/repositories/repositories.dart';
import 'package:pixel_remote/domain/services/platform_services.dart';
import 'package:pixel_remote/domain/services/remote_desktop.dart';
import 'package:pixel_remote/domain/services/secure_tunnel.dart';
import 'package:pixel_remote/domain/services/session_log.dart';
import 'package:pixel_remote/presentation/pixel_remote_app.dart';

final _outDir = Platform.environment['SCREENSHOT_DIR'];

// ---- in-memory adapters for the application's ports ---------------------------

final class _Profiles implements ProfileRepository {
  _Profiles(this._items);
  List<ConnectionProfile> _items;
  @override
  List<ConnectionProfile> load() => List.of(_items);
  @override
  Future<void> save(List<ConnectionProfile> profiles) async => _items = profiles;
}

final class _Prefs implements PreferencesRepository {
  _Prefs(this._prefs);
  AppPreferences _prefs;
  @override
  AppPreferences load() => _prefs;
  @override
  Future<void> save(AppPreferences p) async => _prefs = p;
}

final class _Platform implements LocalPlatform {
  @override
  HostOs get os => HostOs.macos;
  @override
  String get homeDirectory => '/Users/demo';
  @override
  String get userName => 'demo';
  @override
  String? get agentSocket => null;
}

final class _Window implements WindowController {
  @override
  bool isFullScreen = false;
  @override
  set title(String value) {}
}

final class _Tunnel implements SecureTunnel {
  @override
  Future<ByteChannel> open(String host, int port) => throw UnimplementedError();
  @override
  Future<String> run(String command) async => 'Linux';
  @override
  Future<void> spawn(String command) async {}
  @override
  Future<Duration> ping() async => const Duration(milliseconds: 14);
  @override
  Future<void> get done => Completer<void>().future;
  @override
  Future<void> close() async {}
}

/// A synthetic remote desktop: wallpaper, a document window and a terminal.
final class _Desktop implements RemoteDesktopSession, FrameView {
  _Desktop() {
    final px = rgba.buffer.asUint32List();
    int rgb(int r, int g, int b) => 0xFF000000 | b << 16 | g << 8 | r;
    void box(int x, int y, int w, int h, int c) {
      for (var j = y; j < y + h; j++) {
        px.fillRange(j * width + x, j * width + x + w, c);
      }
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final t = (x + y) / (width + height);
        px[y * width + x] = rgb((52 + 150 * t).round(), (70 + 60 * t).round(), (110 - 40 * t).round());
      }
    }
    box(0, 0, width, 30, rgb(28, 28, 30));
    box(150, 110, 640, 440, rgb(250, 250, 248));
    box(150, 110, 640, 36, rgb(232, 230, 226));
    for (var i = 0; i < 9; i++) {
      box(190, 180 + i * 34, 360 + (i * 53) % 200, 12, rgb(200, 198, 192));
    }
    box(700, 330, 500, 330, rgb(24, 24, 27));
    box(700, 330, 500, 30, rgb(44, 44, 48));
    for (var i = 0; i < 7; i++) {
      box(724, 380 + i * 34, 120 + (i * 71) % 300, 12, i.isEven ? rgb(110, 200, 140) : rgb(170, 170, 180));
    }
    box(440, 744, 400, 44, rgb(60, 60, 64));
  }

  @override
  final int width = 1280, height = 800;
  @override
  late final Uint8List rgba = Uint8List(width * height * 4);
  @override
  String get name => 'build-server';
  @override
  FrameView get frame => this;
  @override
  Stream<void> get frames => const Stream.empty();
  @override
  Stream<RemoteCursor> get cursors => const Stream.empty();
  @override
  Stream<String> get clipboard => const Stream.empty();
  @override
  Map<String, int> takeEncodingStats() => const {};
  @override
  bool get canResize => true;
  @override
  Future<RemoteException?> get closed => Completer<RemoteException?>().future;
  @override
  void sendKey(int keysym, {required bool down}) {}
  @override
  void sendPointer(int x, int y, int buttons) {}
  @override
  void sendClipboard(String text) {}
  @override
  void applySettings(StreamSettings settings) {}
  @override
  void resize(int width, int height) {}
  @override
  void refresh() {}
  @override
  Future<void> close() async {}
}

final class _FixedSession extends SessionController {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

// ---- harness ---------------------------------------------------------------------

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  await load('Sans', '/System/Library/Fonts/SFNS.ttf');
  await load('Serif', '/System/Library/Fonts/NewYork.ttf');
  await load('Menlo', '/System/Library/Fonts/SFNSMono.ttf');
  await load('PingFang SC', '/Library/Fonts/Arial Unicode.ttf');
  await load('MaterialIcons', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

TextTheme _typography(TextTheme base) {
  TextStyle? serif(TextStyle? s) => s?.copyWith(fontFamily: 'Serif', letterSpacing: -0.4);
  final sans = base.apply(fontFamily: 'Sans');
  return sans.copyWith(
    displaySmall: serif(base.displaySmall),
    headlineSmall: serif(base.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
  );
}

final _profiles = [
  ConnectionProfile(id: '1', address: 'deploy@build-server.lan', name: 'Build server', lastConnected: DateTime.now().subtract(const Duration(minutes: 12))),
  ConnectionProfile(id: '2', address: 'me@studio-mac.local', vncPort: 5900, lastConnected: DateTime.now().subtract(const Duration(hours: 5))),
  ConnectionProfile(id: '3', address: 'admin@10.0.4.21:2222', name: 'Lab workstation', vncPort: 5901, lastConnected: DateTime.now().subtract(const Duration(days: 3))),
];

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required AppPreferences prefs,
  SessionState session = const SessionIdle(),
  bool withStats = false,
  String encoding = 'Tight JPEG',
  Future<void> Function(WidgetTester tester)? act,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 820)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final stats = [
    for (var i = 0; i < 40; i++)
      SessionStats(
        rtt: Duration(microseconds: 14000 + (i * 3700) % 9000),
        rxBitsPerSecond: 2.5e6 + 2.2e6 * ((i * 7) % 11) / 11,
        txBitsPerSecond: 42e3,
        fps: 58.6,
        width: 1280,
        height: 800,
        encoding: encoding,
      ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localPlatformProvider.overrideWithValue(_Platform()),
        windowControllerProvider.overrideWithValue(_Window()),
        profileRepositoryProvider.overrideWithValue(_Profiles(_profiles)),
        preferencesRepositoryProvider.overrideWithValue(_Prefs(prefs)),
        sessionProvider.overrideWith(() => _FixedSession(session)),
        if (withStats) sessionStatsProvider.overrideWith((ref) => Stream.fromIterable(stats)),
      ],
      child: RepaintBoundary(key: boundary, child: PixelRemoteApp(navigatorKey: GlobalKey(), typography: _typography)),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump(const Duration(milliseconds: 600));
  if (act != null) {
    await act(tester);
    await tester.pump(); // starts any implicit animation…
    await tester.pump(const Duration(milliseconds: 600)); // …and lets it finish
  }
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox()); // dispose timers
}

ActiveSession _activeSession() {
  final desktop = _Desktop();
  final tunnel = _Tunnel();
  return ActiveSession(
    profile: _profiles.first,
    endpoint: const SshEndpoint(host: 'build-server.lan', port: 22, user: 'deploy'),
    tunnel: tunnel,
    desktop: desktop,
    remoteOs: HostOs.linux,
    monitor: SessionMonitor(tunnel: tunnel, traffic: TrafficMeter(), desktop: desktop),
    log: _sampleLog(),
  );
}

/// What a real connection to a TigerVNC server writes to the log.
ConnectionLog _sampleLog() {
  final log = ConnectionLog();
  for (final (level, src, msg) in const [
    (LogLevel.info, 'connect', '"deploy@build-server.lan" resolves to deploy@build-server.lan:22'),
    (LogLevel.info, 'ssh', 'Connecting to build-server.lan:22 as deploy'),
    (LogLevel.info, 'ssh', 'TCP connected in 4 ms'),
    (LogLevel.info, 'ssh', 'Offering 1 ssh-agent key(s) and 1 key file(s)'),
    (LogLevel.info, 'ssh', 'Server version: SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13'),
    (LogLevel.info, 'ssh', 'Key exchange: curve25519-sha256'),
    (LogLevel.info, 'ssh', 'Cipher client→server: chacha20-poly1305@openssh.com'),
    (LogLevel.info, 'ssh', 'Cipher server→client: chacha20-poly1305@openssh.com'),
    (LogLevel.info, 'ssh', 'Host key ssh-ed25519 SHA256:3xAmPLeFiNgErPrInT0nLyNoTaReAlKeY000000000 is trusted'),
    (LogLevel.info, 'ssh', 'Trying PublicKey authentication'),
    (LogLevel.info, 'ssh', 'Authenticated as deploy; SSH ready after 61 ms'),
    (LogLevel.info, 'connect', 'Remote OS: linux'),
    (LogLevel.info, 'tunnel', 'Opened channel to localhost:5900 on the remote side'),
    (LogLevel.info, 'rfb', 'Server speaks RFB 003.008; using RFB 3.8'),
    (LogLevel.info, 'rfb', 'Security types offered: VncAuth → using VncAuth'),
    (LogLevel.info, 'rfb', 'VNC password accepted'),
    (LogLevel.info, 'rfb', 'Desktop "build-server:1 (deploy)" 1280×800; server pixel format 32 bpp, depth 24, little-endian'),
    (LogLevel.info, 'rfb', 'Requesting pixel format 32 bpp, depth 24 (R8G8B8)'),
    (LogLevel.info, 'rfb', 'Encodings offered: Tight, ZRLE, CopyRect, Raw, JPEG quality 5, zlib level 6, Cursor, DesktopSize, ExtendedDesktopSize, LastRect, DesktopName, ExtendedClipboard'),
    (LogLevel.info, 'connect', 'Connected in 118 ms'),
    (LogLevel.info, 'rfb', 'Server supports remote resizing (ExtendedDesktopSize), 1 screen(s)'),
    (LogLevel.info, 'rfb', 'Server started sending Tight'),
    (LogLevel.info, 'rfb', 'Server started sending Tight JPEG'),
    (LogLevel.info, 'rfb', 'Extended clipboard enabled (UTF-8)'),
    (LogLevel.info, 'session', 'Colour depth 24-bit → 8-bit: opening a new stream alongside the current one'),
    (LogLevel.warning, 'session', 'The server did not accept 8-bit colour (RemoteException(disconnected)); keeping 24-bit'),
    (LogLevel.info, 'rfb', '583 updates in 10 s, 5.6 MB (4.7 Mbit/s), avg 9.8 KB and 2.1 ms per update; Tight JPEG 1204×4.9 MB, Tight 3120×0.6 MB, CopyRect 12×0.0 KB'),
  ]) {
    log.add(level, src, msg);
  }
  return log;
}

void main() {
  final skip = _outDir == null;
  setUpAll(() async {
    if (!skip) await _loadFonts();
  });

  const en = AppPreferences(languageCode: 'en', themeMode: AppThemeMode.light);
  const zhDark = AppPreferences(languageCode: 'zh', themeMode: AppThemeMode.dark);

  testWidgets('home, English, light', (t) => _shoot(t, 'home_en_light', prefs: en), skip: skip);
  testWidgets(
    'home, advanced options',
    (t) => _shoot(t, 'home_advanced_en_light', prefs: en, act: (t) => t.tap(find.text('Advanced options'))),
    skip: skip,
  );
  testWidgets('home, Chinese, dark', (t) => _shoot(t, 'home_zh_dark', prefs: zhDark), skip: skip);
  testWidgets(
    'connecting',
    (t) => _shoot(t, 'connecting_en_light', prefs: en, session: SessionConnecting(_profiles.first, ConnectStage.tunnelling, _sampleLog())),
    skip: skip,
  );
  testWidgets(
    'connection error',
    (t) => _shoot(t, 'error_zh_dark', prefs: zhDark, session: SessionIdle(const RemoteException(RemoteErrorKind.vncUnavailable, 'localhost:5900'), _sampleLog())),
    skip: skip,
  );
  testWidgets(
    'session with stats',
    (t) => _shoot(t, 'session_en_light', prefs: en, session: SessionActive(_activeSession()), withStats: true),
    skip: skip,
  );
  testWidgets(
    'session settings panel, Chinese',
    (t) => _shoot(
      t,
      'session_zh_dark',
      prefs: zhDark,
      session: SessionActive(_activeSession()),
      withStats: true,
      encoding: 'ZRLE',
      act: (t) => t.tap(find.byIcon(Icons.tune_rounded)),
    ),
    skip: skip,
  );
  testWidgets(
    'session connection log',
    (t) => _shoot(
      t,
      'session_log_en_light',
      prefs: en,
      session: SessionActive(_activeSession()),
      act: (t) => t.tap(find.byIcon(Icons.receipt_long_rounded)),
    ),
    skip: skip,
  );
}
