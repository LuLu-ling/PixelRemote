import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/providers.dart';
import '../data/platform/io_local_platform.dart';
import '../data/platform/ui_jpeg_codec.dart';
import '../data/repositories/prefs_repositories.dart';
import '../data/rfb/rfb_session.dart';
import '../data/ssh/dartssh2_tunnel.dart';
import '../data/ssh/known_hosts_verifier.dart';
import '../data/ssh/ssh_config_resolver.dart';
import '../domain/services/platform_services.dart';
import '../presentation/dialogs/dialog_user_interaction.dart';

/// The only place that knows concrete classes: binds every application port
/// to its implementation. Swap an entry here to change an implementation.
List<Override> compositionRoot({
  required SharedPreferencesWithCache prefs,
  required GlobalKey<NavigatorState> navigatorKey,
  required WindowController window,
}) {
  const platform = IoLocalPlatform();
  final interaction = DialogUserInteraction(navigatorKey);
  return [
    localPlatformProvider.overrideWithValue(platform),
    windowControllerProvider.overrideWithValue(window),
    userInteractionProvider.overrideWithValue(interaction),
    profileRepositoryProvider.overrideWithValue(PrefsProfileRepository(prefs)),
    preferencesRepositoryProvider.overrideWithValue(PrefsPreferencesRepository(prefs)),
    endpointResolverProvider.overrideWithValue(SshConfigResolver(platform)),
    tunnelConnectorProvider.overrideWithValue(
      Dartssh2TunnelConnector(interaction: interaction, hostKeys: KnownHostsVerifier(prefs, platform.homeDirectory)),
    ),
    remoteDesktopProtocolProvider.overrideWithValue(const RfbProtocol(UiJpegCodec())),
  ];
}
