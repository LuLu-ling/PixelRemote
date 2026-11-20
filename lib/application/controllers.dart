import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../core/command.dart';
import '../domain/entities/app_preferences.dart';
import '../domain/entities/connection_profile.dart';
import '../domain/errors.dart';
import '../domain/services/remote_desktop.dart';
import 'connect_session.dart';
import 'providers.dart';
import 'session_commands.dart';

// ---- session lifecycle -------------------------------------------------------

sealed class SessionState {
  const SessionState();
}

final class SessionIdle extends SessionState {
  const SessionIdle([this.error]);

  /// Why the previous attempt or session ended, if it wasn't the user's doing.
  final RemoteException? error;
}

final class SessionConnecting extends SessionState {
  const SessionConnecting(this.profile, this.stage);

  final ConnectionProfile profile;
  final ConnectStage stage;
}

final class SessionActive extends SessionState {
  const SessionActive(this.session);

  final ActiveSession session;
}

class SessionController extends Notifier<SessionState> {
  ActiveSession? _active;
  CommandInvoker<RemoteDesktopSession>? _invoker;
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
    state = SessionConnecting(profile, ConnectStage.resolving);
    try {
      final session = await ref.read(connectSessionProvider).call(
            profile,
            ref.read(preferencesProvider).stream,
            onStage: (stage) => current() ? state = SessionConnecting(profile, stage) : null,
          );
      if (!current()) return unawaited(session.close());
      _active = session;
      _invoker = CommandInvoker(session.desktop);
      state = SessionActive(session);
      ref.read(profilesProvider.notifier).upsert(profile.touched(DateTime.now()));
      final reason = await session.ended;
      if (identical(_active, session)) await _end(reason ?? const RemoteException(RemoteErrorKind.disconnected));
    } on RemoteException catch (e) {
      if (current()) state = SessionIdle(e);
    }
  }

  /// Abandons an in-flight connection attempt.
  void cancel() {
    if (state is! SessionConnecting) return;
    _attempt++;
    state = const SessionIdle();
  }

  Future<void> disconnect() => _end(null);

  void dispatch(SessionCommand command) => _invoker?.dispatch(command);

  Future<void> _end(RemoteException? reason) async {
    final session = _active;
    _active = null;
    _invoker = null;
    _attempt++;
    state = SessionIdle(reason);
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
