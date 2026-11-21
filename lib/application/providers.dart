import 'package:riverpod/riverpod.dart';

import '../domain/entities/app_preferences.dart';
import '../domain/entities/connection_profile.dart';
import '../domain/entities/keyboard.dart';
import '../domain/entities/session_stats.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/platform_services.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/secure_tunnel.dart';
import 'connect_session.dart';
import 'connection_log.dart';
import 'controllers.dart';

// ---- ports ---------------------------------------------------------------------
// The application declares what it needs; lib/app/composition_root.dart binds
// concrete implementations. Nothing here knows about SSH libraries or Flutter.

Provider<T> _port<T>(String name) =>
    Provider<T>((_) => throw UnimplementedError('$name is bound in the composition root'), name: name);

final profileRepositoryProvider = _port<ProfileRepository>('ProfileRepository');
final preferencesRepositoryProvider = _port<PreferencesRepository>('PreferencesRepository');
final endpointResolverProvider = _port<SshEndpointResolver>('SshEndpointResolver');
final tunnelConnectorProvider = _port<TunnelConnector>('TunnelConnector');
final remoteDesktopProtocolProvider = _port<RemoteDesktopProtocol>('RemoteDesktopProtocol');
final userInteractionProvider = _port<UserInteraction>('UserInteraction');
final localPlatformProvider = _port<LocalPlatform>('LocalPlatform');
final windowControllerProvider = _port<WindowController>('WindowController');

// ---- use cases & state ---------------------------------------------------------

final connectSessionProvider = Provider(
  (ref) => ConnectSession(
    resolver: ref.watch(endpointResolverProvider),
    tunnels: ref.watch(tunnelConnectorProvider),
    protocol: ref.watch(remoteDesktopProtocolProvider),
    interaction: ref.watch(userInteractionProvider),
  ),
);

final preferencesProvider = NotifierProvider<PreferencesController, AppPreferences>(PreferencesController.new);
final profilesProvider = NotifierProvider<ProfilesController, List<ConnectionProfile>>(ProfilesController.new);
final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Log of the current or most recent connection.
final connectionLogProvider = Provider<ConnectionLog?>((ref) => ref.watch(sessionProvider).log);

final sessionStatsProvider = StreamProvider<SessionStats>((ref) {
  final state = ref.watch(sessionProvider);
  return state is SessionActive ? state.session.monitor.stats : const Stream.empty();
});

/// The modifier remapping in force for the current session.
final keyRemapperProvider = Provider<KeyRemapper>((ref) {
  final state = ref.watch(sessionProvider);
  return KeyRemapper.resolve(
    ref.watch(preferencesProvider.select((p) => p.keyMapping)),
    local: ref.watch(localPlatformProvider).os,
    remote: state is SessionActive ? state.session.remoteOs : HostOs.unknown,
  );
});
