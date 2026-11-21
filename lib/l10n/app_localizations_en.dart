// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get homeHeadline => 'Reach any desktop, securely.';

  @override
  String get homeSubtitle =>
      'Enter an SSH address. PixelRemote carries VNC through an encrypted SSH tunnel, so the only port you need open is SSH.';

  @override
  String get addressHint => 'user@host:22, or an alias from ~/.ssh/config';

  @override
  String get connect => 'Connect';

  @override
  String get advanced => 'Advanced options';

  @override
  String get displayName => 'Display name';

  @override
  String get optional => 'Optional';

  @override
  String get vncHost => 'VNC host (as seen from the SSH server)';

  @override
  String get vncPort => 'VNC port';

  @override
  String get identityFile => 'Private key file';

  @override
  String get identityFileHint => 'Defaults to ssh-agent and ~/.ssh/id_*';

  @override
  String get startCommand => 'Start command';

  @override
  String get startCommandHint =>
      'e.g. x11vnc -localhost -display :0 -forever -shared';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String get recentTitle => 'Recent';

  @override
  String get recentEmpty => 'Hosts you connect to will appear here.';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: 'yesterday',
    );
    return '$_temp0';
  }

  @override
  String get neverConnected => 'not connected yet';

  @override
  String get footer =>
      'SSH tunnel · RFB 3.8 · Tight · ZRLE · Extended clipboard';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'Match system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get defaultSettings => 'Default stream settings';

  @override
  String connectingTo(String target) {
    return 'Connecting to $target';
  }

  @override
  String get stageResolving => 'Resolving address';

  @override
  String get stageConnecting => 'Establishing SSH session';

  @override
  String get stagePreparing => 'Preparing remote host';

  @override
  String get stageTunnelling => 'Opening encrypted tunnel';

  @override
  String get stageNegotiating => 'Negotiating display';

  @override
  String errorInvalidAddress(String address) {
    return '“$address” isn\'t a valid SSH address.';
  }

  @override
  String get errorHostUnreachable =>
      'Couldn\'t reach the SSH server. Check the host name, port and network.';

  @override
  String get errorAuthFailed => 'SSH authentication failed.';

  @override
  String get errorHostKeyRejected =>
      'The host key wasn\'t trusted, so the connection was stopped.';

  @override
  String get errorHostKeyChanged =>
      'Warning: this host\'s key has changed. Someone could be intercepting the connection, so it was refused.';

  @override
  String errorVncUnavailable(String target) {
    return 'Nothing is listening on $target on the remote host. Start a VNC server there, or set a start command under Advanced options.';
  }

  @override
  String get errorVncAuthFailed => 'The VNC password was rejected.';

  @override
  String errorUnsupportedSecurity(String types) {
    return 'The VNC server only offers security types this client doesn\'t support ($types). Enable “None” or “VncAuth”; the SSH tunnel already encrypts the session.';
  }

  @override
  String errorProtocol(String detail) {
    return 'Protocol error: $detail';
  }

  @override
  String get errorDisconnected => 'The remote session ended.';

  @override
  String get errorCancelled => 'Connection cancelled.';

  @override
  String get secretSshPassword => 'SSH password';

  @override
  String get secretKeyPassphrase => 'Key passphrase';

  @override
  String get secretVncPassword => 'VNC password';

  @override
  String get secretChallenge => 'Verification required';

  @override
  String secretFor(String subject) {
    return 'For $subject';
  }

  @override
  String get hostKeyTitle => 'Verify host identity';

  @override
  String hostKeyBody(String host) {
    return 'This is the first connection to $host. Before continuing, check that this fingerprint matches the server\'s.';
  }

  @override
  String get hostKeyTrust => 'Trust and connect';

  @override
  String get streamSettings => 'Display & stream';

  @override
  String get statsOverlay => 'Statistics overlay';

  @override
  String get sendKeys => 'Send keys';

  @override
  String get fullScreen => 'Full screen';

  @override
  String get exitFullScreen => 'Exit full screen';

  @override
  String get refreshScreen => 'Refresh screen';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get keySuper => 'Super / Win / ⌘';

  @override
  String get keyPrintScreen => 'Print Screen';

  @override
  String get quality => 'Image quality';

  @override
  String get qualityLow => 'Low';

  @override
  String get qualityBalanced => 'Balanced';

  @override
  String get qualityHigh => 'High';

  @override
  String get qualityLossless => 'Lossless';

  @override
  String get frameRate => 'Frame rate';

  @override
  String fps(int value) {
    return '$value fps';
  }

  @override
  String get resolution => 'Resolution';

  @override
  String get resolutionNative => 'Server default';

  @override
  String get resolutionWindow => 'Match window';

  @override
  String get resolutionUnsupported =>
      'This server can\'t change its resolution, so the image is scaled locally.';

  @override
  String get colorDepth => 'Color depth';

  @override
  String get depthFull => 'Full color';

  @override
  String get depthHigh => '16-bit';

  @override
  String get depthLow => '8-bit';

  @override
  String get bandwidth => 'Bandwidth limit';

  @override
  String get bandwidthHint =>
      'Frames are paced so the stream stays under this limit.';

  @override
  String get unlimited => 'Unlimited';

  @override
  String mbps(int value) {
    return '$value Mbps';
  }

  @override
  String get keyMapping => 'Keyboard mapping';

  @override
  String get mappingAuto => 'Automatic';

  @override
  String get mappingOff => 'Off (pass-through)';

  @override
  String get mappingCtrlCmd => 'Swap Ctrl ⇄ ⌘';

  @override
  String get mappingAltCmd => 'Swap Alt ⇄ ⌘';

  @override
  String mappingActive(String mode, String local, String remote) {
    return 'In effect: $mode · $local → $remote';
  }

  @override
  String get osMac => 'macOS';

  @override
  String get osWindows => 'Windows';

  @override
  String get osLinux => 'Linux';

  @override
  String get osUnknown => 'unknown OS';

  @override
  String get showStats => 'Show statistics overlay';

  @override
  String get statsTitle => 'Live stats';

  @override
  String get statsLatency => 'Latency';

  @override
  String get statsLoss => 'Packet loss';

  @override
  String get statsLossHint => 'Estimated from unanswered SSH keep-alive probes';

  @override
  String get statsDown => 'Down';

  @override
  String get statsUp => 'Up';

  @override
  String get statsFrameRate => 'Frame rate';

  @override
  String get statsResolution => 'Resolution';

  @override
  String get connectionLog => 'Connection log';

  @override
  String get copyLog => 'Copy all';

  @override
  String get copied => 'Copied to the clipboard';

  @override
  String get viewLog => 'View connection log';

  @override
  String get logEmpty => 'Nothing logged yet.';

  @override
  String get statsEncoding => 'Encoding';

  @override
  String qualityNoEffect(String encoding) {
    return 'This server is sending $encoding, which is lossless, so image quality has no effect here. Lower the colour depth, resolution or frame rate to save bandwidth.';
  }

  @override
  String depthRejected(int bits) {
    return 'The server didn\'t accept $bits-bit colour, so the session stayed on the previous depth. The connection log has the details.';
  }
}
