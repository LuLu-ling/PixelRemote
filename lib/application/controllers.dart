import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../core/command.dart';
import '../domain/entities/app_preferences.dart';
import '../domain/entities/connection_profile.dart';
import '../domain/errors.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/session_log.dart';
import 'connect_session.dart';
import 'connection_log.dart';
import 'managed_desktop.dart';
import 'providers.dart';
import 'session_commands.dart';

// ---- session lifecycle -------------------------------------------------------

sealed class SessionState {
  const SessionState();

  /// The log of the current or most recent connection, if any.
  ConnectionLog? get log;
}

final class SessionIdle extends SessionState {
  const SessionIdle([this.error, this.log]);

  /// Why the previous attempt or session ended, if it wasn't the user's doing.
  final RemoteException? error;

  @override
  final ConnectionLog? log;
}

final class SessionConnecting extends SessionState {
  const SessionConnecting(this.profile, this.stage, this.log);

  final ConnectionProfile profile;
  final ConnectStage stage;

  @override
  final ConnectionLog log;
}

final class SessionActive extends SessionState {
  const SessionActive(this.session);

  final ActiveSession session;

  @override
  ConnectionLog get log => session.log;
}

class SessionController extends Notifier<SessionState> {
  ActiveSession? _active;
  CommandInvoker<RemoteDesktopSession>? _invoker;
  StreamSubscription<DepthRejection>? _rejections;
  int _attempt = 0;

  @override
  SessionState build() {
    // Stream settings are edited as preferences; a live session follows them.
    ref.listen(preferencesProvider.select((p) => p.stream), (_, next) => dispatch(ApplySettingsCommand(next)));
    ref.onDispose(() => _active?.close());
    return const SessionIdle();
  }

  Future<void> connect(ConnectionProfile profile) async {
    if (state is! SessionIdle) return;
    final attempt = ++_attempt;
    bool current() => attempt == _attempt;
    final log = ConnectionLog();
    state = SessionConnecting(profile, ConnectStage.resolving, log);
    try {
      final session = await ref.read(connectSessionProvider).call(
            profile,
            ref.read(preferencesProvider).stream,
            log: log,
            onStage: (stage) => current() ? state = SessionConnecting(profile, stage, log) : null,
          );
      if (!current()) return unawaited(session.close());
      _active = session;
      _invoker = CommandInvoker(
        session.desktop,
        onError: (e, _) => log.error('command', 'Command failed: $e'),
      );
      // A depth the server refused snaps the preference back to what is running.
      _rejections = session.rejections.listen((r) => ref
          .read(preferencesProvider.notifier)
          .update((p) => p.copyWith(stream: p.stream.copyWith(colorDepth: r.kept))));
      state = SessionActive(session);
      ref.read(profilesProvider.notifier).upsert(profile.touched(DateTime.now()));
      final reason = await session.ended;
      if (identical(_active, session)) await _end(reason ?? const RemoteException(RemoteErrorKind.disconnected));
    } on RemoteException catch (e) {
      if (current()) state = SessionIdle(e, log);
    }
  }

  /// Abandons an in-flight connection attempt.
  void cancel() {
    final s = state;
    if (s is! SessionConnecting) return;
    _attempt++;
    s.log.info('connect', 'Cancelled by the user');
    state = SessionIdle(null, s.log);
  }

  Future<void> disconnect() => _end(null);

  void dispatch(SessionCommand command) => _invoker?.dispatch(command);

  Future<void> _end(RemoteException? reason) async {
    final session = _active;
    _active = null;
    _invoker = null;
    _attempt++;
    await _rejections?.cancel();
    state = SessionIdle(reason, session?.log);
    await session?.close();
  }
}

// ---- saved connections -------------------------------------------------------

final class ProfilesController extends Notifier<List<ConnectionProfile>> {
  @override
  List<ConnectionProfile> build() => ref.watch(profileRepositoryProvider).load()
    ..sort((a, b) => (b.lastConnected ?? DateTime(0)).compareTo(a.lastConnected ?? DateTime(0)));

  /// Inserts or replaces by id, moving the profile to the front.
  void upsert(ConnectionProfile profile) =>
      _save([profile, ...state.where((p) => p.id != profile.id)]);

  void remove(String id) => _save(state.where((p) => p.id != id).toList());

  void _save(List<ConnectionProfile> profiles) {
    state = profiles;
    unawaited(ref.read(profileRepositoryProvider).save(profiles));
  }
}

// ---- preferences ---------------------------------------------------------------

final class PreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => ref.watch(preferencesRepositoryProvider).load();

  void update(AppPreferences Function(AppPreferences current) change) {
    state = change(state);
    unawaited(ref.read(preferencesRepositoryProvider).save(state));
  }
}
