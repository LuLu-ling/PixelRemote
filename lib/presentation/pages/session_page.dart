import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/connect_session.dart';
import '../../application/controllers.dart';
import '../../application/providers.dart';
import '../../application/session_commands.dart';
import '../../domain/services/platform_services.dart';
import '../l10n.dart';
import '../widgets/common.dart';
import '../widgets/connection_log_panel.dart';
import '../widgets/remote_view.dart';
import '../widgets/session_toolbar.dart';
import '../widgets/stats_overlay.dart';
import '../widgets/stream_settings_panel.dart';

/// Full-bleed remote desktop with an auto-hiding toolbar, settings panel and
/// stats overlay. Also bridges the clipboard in both directions.
class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({super.key, required this.session});

  final ActiveSession session;

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

enum _Panel { none, settings, log }

class _SessionPageState extends ConsumerState<SessionPage> {
  final _viewFocus = FocusNode(debugLabel: 'remote');
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<String> _clipboardSub;
  late final StreamSubscription<Object?> _rejectionSub;
  Timer? _hideTimer;
  bool _toolbarVisible = true, _toolbarHovered = false, _fullScreen = false;
  _Panel _panel = _Panel.none;
  String? _lastClipboard;

  // Captured once: Riverpod forbids `ref` while the widget is being torn down,
  // which is exactly when the window must be restored and keys released.
  late final WindowController _window = ref.read(windowControllerProvider);
  late final SessionController _controller = ref.read(sessionProvider.notifier);

  ActiveSession get _session => widget.session;
  void _dispatch(SessionCommand command) => _controller.dispatch(command);

  @override
  void initState() {
    super.initState();
    _window.title = '${_session.profile.displayName} — PixelRemote';
    _clipboardSub = _session.desktop.clipboard.listen((text) {
      _lastClipboard = text;
      Clipboard.setData(ClipboardData(text: text));
    });
    _rejectionSub = _session.rejections.listen((r) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.depthRejected(r.rejected.bits))));
    });
    _lifecycle = AppLifecycleListener(onResume: _pushClipboard);
    _viewFocus.addListener(() => _viewFocus.hasFocus ? _pushClipboard() : null);
    _scheduleHide(const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _window
      ..title = 'PixelRemote'
      ..isFullScreen = false;
    _clipboardSub.cancel();
    _rejectionSub.cancel();
    _lifecycle.dispose();
    _hideTimer?.cancel();
    _viewFocus.dispose();
    super.dispose();
  }

  Future<void> _pushClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || text == null || text.isEmpty || text == _lastClipboard) return;
    _lastClipboard = text;
    _dispatch(ClipboardCommand(text));
  }

  // ---- toolbar visibility ------------------------------------------------------

  void _showToolbar() {
    _hideTimer?.cancel();
    if (!_toolbarVisible) setState(() => _toolbarVisible = true);
  }

  void _scheduleHide([Duration after = const Duration(milliseconds: 1500)]) {
    _hideTimer?.cancel();
    _hideTimer = Timer(after, () {
      if (mounted && !_toolbarHovered && _panel == _Panel.none) setState(() => _toolbarVisible = false);
    });
  }

  void _onPointerAt(Offset at) {
    if (at.dy < 8) _showToolbar();
  }

  void _toggle(_Panel panel) {
    setState(() => _panel = _panel == panel ? _Panel.none : panel);
    if (_panel == _Panel.none) {
      _viewFocus.requestFocus();
      _scheduleHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    final update = ref.read(preferencesProvider.notifier).update;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0D),
      body: Stack(
        children: [
          Positioned.fill(
            child: RemoteView(
              desktop: _session.desktop,
              remapper: ref.watch(keyRemapperProvider),
              isMac: ref.watch(localPlatformProvider).os.isMac,
              focusNode: _viewFocus,
              onCommand: _dispatch,
              onPointerAt: _onPointerAt,
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                ignoring: !_toolbarVisible,
                child: AnimatedSlide(
                  offset: _toolbarVisible ? Offset.zero : const Offset(0, -1.4),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: MouseRegion(
                    onEnter: (_) {
                      _toolbarHovered = true;
                      _showToolbar();
                    },
                    onExit: (_) {
                      _toolbarHovered = false;
                      _scheduleHide();
                    },
                    child: SessionToolbar(
                      title: _session.profile.displayName,
                      fullScreen: _fullScreen,
                      statsOn: prefs.showStats,
                      settingsOpen: _panel == _Panel.settings,
                      logOpen: _panel == _Panel.log,
                      onToggleSettings: () => _toggle(_Panel.settings),
                      onToggleLog: () => _toggle(_Panel.log),
                      onToggleStats: () => update((p) => p.copyWith(showStats: !p.showStats)),
                      onToggleFullScreen: () {
                        _window.isFullScreen = !_fullScreen;
                        setState(() => _fullScreen = !_fullScreen);
                      },
                      onRefresh: () => _dispatch(const RefreshCommand()),
                      onSendKeys: (keys) => _dispatch(KeyComboCommand(keys)),
                      onDisconnect: _controller.disconnect,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (prefs.showStats)
            StatsOverlay(
              targetFps: prefs.stream.frameRate,
              onClose: () => update((p) => p.copyWith(showStats: false)),
            ),
          if (_panel == _Panel.settings)
            Positioned(
              top: 68,
              right: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: Glass(
                  radius: 18,
                  child: StreamSettingsPanel(
                    title: context.l10n.streamSettings,
                    onClose: () => _toggle(_Panel.settings),
                  ),
                ),
              ),
            ),
          if (_panel == _Panel.log)
            Positioned(
              top: 68,
              right: 16,
              bottom: 16,
              child: Glass(
                radius: 18,
                child: ConnectionLogPanel(log: _session.log, onClose: () => _toggle(_Panel.log)),
              ),
            ),
        ],
      ),
    );
  }
}
