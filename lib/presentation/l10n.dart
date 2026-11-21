import 'package:flutter/widgets.dart';

import '../application/connect_session.dart';
import '../domain/entities/keyboard.dart';
import '../domain/entities/stream_settings.dart';
import '../domain/errors.dart';
import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Maps domain values onto localized text; the domain stays language-free.
extension DomainText on AppLocalizations {
  String error(RemoteException e) => switch (e.kind) {
        RemoteErrorKind.invalidAddress => errorInvalidAddress(e.detail ?? ''),
        RemoteErrorKind.hostUnreachable => errorHostUnreachable,
        RemoteErrorKind.authFailed => errorAuthFailed,
        RemoteErrorKind.hostKeyRejected => errorHostKeyRejected,
        RemoteErrorKind.hostKeyChanged => errorHostKeyChanged,
        RemoteErrorKind.vncUnavailable => errorVncUnavailable(e.detail ?? ''),
        RemoteErrorKind.vncAuthFailed => errorVncAuthFailed,
        RemoteErrorKind.unsupportedSecurity => errorUnsupportedSecurity(e.detail ?? ''),
        RemoteErrorKind.protocol => errorProtocol(e.detail ?? ''),
        RemoteErrorKind.disconnected => errorDisconnected,
        RemoteErrorKind.cancelled => errorCancelled,
      };

  String stage(ConnectStage s) => switch (s) {
        ConnectStage.resolving => stageResolving,
        ConnectStage.connecting => stageConnecting,
        ConnectStage.preparing => stagePreparing,
        ConnectStage.tunnelling => stageTunnelling,
        ConnectStage.negotiating => stageNegotiating,
      };

  String os(HostOs o) => switch (o) {
        HostOs.macos => osMac,
        HostOs.windows => osWindows,
        HostOs.linux => osLinux,
        HostOs.unknown => osUnknown,
      };

  String qualityName(ImageQuality q) => switch (q) {
        ImageQuality.auto => qualityAuto,
        ImageQuality.low => qualityLow,
        ImageQuality.balanced => qualityBalanced,
        ImageQuality.high => qualityHigh,
        ImageQuality.lossless => qualityLossless,
      };

  String depth(ColorDepth d) => switch (d) {
        ColorDepth.full => depthFull,
        ColorDepth.high => depthHigh,
        ColorDepth.low => depthLow,
      };

  String mapping(KeyMappingMode m) => switch (m) {
        KeyMappingMode.auto => mappingAuto,
        KeyMappingMode.off => mappingOff,
        KeyMappingMode.ctrlCmd => mappingCtrlCmd,
        KeyMappingMode.altCmd => mappingAltCmd,
      };

  String bandwidthLimit(int mbps) => mbps == 0 ? unlimited : this.mbps(mbps);

  String since(DateTime? at) {
    if (at == null) return neverConnected;
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return justNow;
    if (d.inHours < 1) return minutesAgo(d.inMinutes);
    if (d.inDays < 1) return hoursAgo(d.inHours);
    return daysAgo(d.inDays);
  }
}
