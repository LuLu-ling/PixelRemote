import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @homeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Reach any desktop, securely.'**
  String get homeHeadline;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter an SSH address. PixelRemote carries VNC through an encrypted SSH tunnel, so the only port you need open is SSH.'**
  String get homeSubtitle;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'user@host:22, or an alias from ~/.ssh/config'**
  String get addressHint;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get advanced;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @vncHost.
  ///
  /// In en, this message translates to:
  /// **'VNC host (as seen from the SSH server)'**
  String get vncHost;

  /// No description provided for @vncPort.
  ///
  /// In en, this message translates to:
  /// **'VNC port'**
  String get vncPort;

  /// No description provided for @identityFile.
  ///
  /// In en, this message translates to:
  /// **'Private key file'**
  String get identityFile;

  /// No description provided for @identityFileHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to ssh-agent and ~/.ssh/id_*'**
  String get identityFileHint;

  /// No description provided for @startCommand.
  ///
  /// In en, this message translates to:
  /// **'Start command'**
  String get startCommand;

  /// No description provided for @startCommandHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. x11vnc -localhost -display :0 -once'**
  String get startCommandHint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @recentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentTitle;

  /// No description provided for @recentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Hosts you connect to will appear here.'**
  String get recentEmpty;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{yesterday} other{{count} days ago}}'**
  String daysAgo(int count);

  /// No description provided for @neverConnected.
  ///
  /// In en, this message translates to:
  /// **'not connected yet'**
  String get neverConnected;

  /// No description provided for @footer.
  ///
  /// In en, this message translates to:
  /// **'SSH tunnel · RFB 3.8 · Tight · ZRLE · Extended clipboard'**
  String get footer;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @defaultSettings.
  ///
  /// In en, this message translates to:
  /// **'Default stream settings'**
  String get defaultSettings;

  /// No description provided for @connectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {target}'**
  String connectingTo(String target);

  /// No description provided for @stageResolving.
  ///
  /// In en, this message translates to:
  /// **'Resolving address'**
  String get stageResolving;

  /// No description provided for @stageConnecting.
  ///
  /// In en, this message translates to:
  /// **'Establishing SSH session'**
  String get stageConnecting;

  /// No description provided for @stagePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing remote host'**
  String get stagePreparing;

  /// No description provided for @stageTunnelling.
  ///
  /// In en, this message translates to:
  /// **'Opening encrypted tunnel'**
  String get stageTunnelling;

  /// No description provided for @stageNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Negotiating display'**
  String get stageNegotiating;

  /// No description provided for @errorInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'“{address}” isn\'t a valid SSH address.'**
  String errorInvalidAddress(String address);

  /// No description provided for @errorHostUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the SSH server. Check the host name, port and network.'**
  String get errorHostUnreachable;

  /// No description provided for @errorAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'SSH authentication failed.'**
  String get errorAuthFailed;

  /// No description provided for @errorHostKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'The host key wasn\'t trusted, so the connection was stopped.'**
  String get errorHostKeyRejected;

  /// No description provided for @errorHostKeyChanged.
  ///
  /// In en, this message translates to:
  /// **'Warning: this host\'s key has changed. Someone could be intercepting the connection, so it was refused.'**
  String get errorHostKeyChanged;

  /// No description provided for @errorVncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nothing is listening on {target} on the remote host. Start a VNC server there, or set a start command under Advanced options.'**
  String errorVncUnavailable(String target);

  /// No description provided for @errorVncAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'The VNC password was rejected.'**
  String get errorVncAuthFailed;

  /// No description provided for @errorUnsupportedSecurity.
  ///
  /// In en, this message translates to:
  /// **'The VNC server only offers security types this client doesn\'t support ({types}). Enable “None” or “VncAuth”; the SSH tunnel already encrypts the session.'**
  String errorUnsupportedSecurity(String types);

  /// No description provided for @errorProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol error: {detail}'**
  String errorProtocol(String detail);

  /// No description provided for @errorDisconnected.
  ///
  /// In en, this message translates to:
  /// **'The remote session ended.'**
  String get errorDisconnected;

  /// No description provided for @errorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Connection cancelled.'**
  String get errorCancelled;

  /// No description provided for @secretSshPassword.
  ///
  /// In en, this message translates to:
  /// **'SSH password'**
  String get secretSshPassword;

  /// No description provided for @secretKeyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Key passphrase'**
  String get secretKeyPassphrase;

  /// No description provided for @secretVncPassword.
  ///
  /// In en, this message translates to:
  /// **'VNC password'**
  String get secretVncPassword;

  /// No description provided for @secretChallenge.
  ///
  /// In en, this message translates to:
  /// **'Verification required'**
  String get secretChallenge;

  /// No description provided for @secretFor.
  ///
  /// In en, this message translates to:
  /// **'For {subject}'**
  String secretFor(String subject);

  /// No description provided for @hostKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify host identity'**
  String get hostKeyTitle;

  /// No description provided for @hostKeyBody.
  ///
  /// In en, this message translates to:
  /// **'This is the first connection to {host}. Before continuing, check that this fingerprint matches the server\'s.'**
  String hostKeyBody(String host);

  /// No description provided for @hostKeyTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust and connect'**
  String get hostKeyTrust;

  /// No description provided for @streamSettings.
  ///
  /// In en, this message translates to:
  /// **'Display & stream'**
  String get streamSettings;

  /// No description provided for @statsOverlay.
  ///
  /// In en, this message translates to:
  /// **'Statistics overlay'**
  String get statsOverlay;

  /// No description provided for @sendKeys.
  ///
  /// In en, this message translates to:
  /// **'Send keys'**
  String get sendKeys;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullScreen;

  /// No description provided for @exitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get exitFullScreen;

  /// No description provided for @refreshScreen.
  ///
  /// In en, this message translates to:
  /// **'Refresh screen'**
  String get refreshScreen;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @keySuper.
  ///
  /// In en, this message translates to:
  /// **'Super / Win / ⌘'**
  String get keySuper;

  /// No description provided for @keyPrintScreen.
  ///
  /// In en, this message translates to:
  /// **'Print Screen'**
  String get keyPrintScreen;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Image quality'**
  String get quality;

  /// No description provided for @qualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get qualityLow;

  /// No description provided for @qualityBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get qualityBalanced;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get qualityHigh;

  /// No description provided for @qualityLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get qualityLossless;

  /// No description provided for @frameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get frameRate;

  /// No description provided for @fps.
  ///
  /// In en, this message translates to:
  /// **'{value} fps'**
  String fps(int value);

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// No description provided for @resolutionNative.
  ///
  /// In en, this message translates to:
  /// **'Server default'**
  String get resolutionNative;

  /// No description provided for @resolutionWindow.
  ///
  /// In en, this message translates to:
  /// **'Match window'**
  String get resolutionWindow;

  /// No description provided for @resolutionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server can\'t change its resolution, so the image is scaled locally.'**
  String get resolutionUnsupported;

  /// No description provided for @colorDepth.
  ///
  /// In en, this message translates to:
  /// **'Color depth'**
  String get colorDepth;

  /// No description provided for @depthFull.
  ///
  /// In en, this message translates to:
  /// **'Full color'**
  String get depthFull;

  /// No description provided for @depthHigh.
  ///
  /// In en, this message translates to:
  /// **'16-bit'**
  String get depthHigh;

  /// No description provided for @depthLow.
  ///
  /// In en, this message translates to:
  /// **'8-bit'**
  String get depthLow;

  /// No description provided for @bandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth limit'**
  String get bandwidth;

  /// No description provided for @bandwidthHint.
  ///
  /// In en, this message translates to:
  /// **'Frames are paced so the stream stays under this limit.'**
  String get bandwidthHint;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @mbps.
  ///
  /// In en, this message translates to:
  /// **'{value} Mbps'**
  String mbps(int value);

  /// No description provided for @keyMapping.
  ///
  /// In en, this message translates to:
  /// **'Keyboard mapping'**
  String get keyMapping;

  /// No description provided for @mappingAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get mappingAuto;

  /// No description provided for @mappingOff.
  ///
  /// In en, this message translates to:
  /// **'Off (pass-through)'**
  String get mappingOff;

  /// No description provided for @mappingCtrlCmd.
  ///
  /// In en, this message translates to:
  /// **'Swap Ctrl ⇄ ⌘'**
  String get mappingCtrlCmd;

  /// No description provided for @mappingAltCmd.
  ///
  /// In en, this message translates to:
  /// **'Swap Alt ⇄ ⌘'**
  String get mappingAltCmd;

  /// No description provided for @mappingActive.
  ///
  /// In en, this message translates to:
  /// **'In effect: {mode} · {local} → {remote}'**
  String mappingActive(String mode, String local, String remote);

  /// No description provided for @osMac.
  ///
  /// In en, this message translates to:
  /// **'macOS'**
  String get osMac;

  /// No description provided for @osWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get osWindows;

  /// No description provided for @osLinux.
  ///
  /// In en, this message translates to:
  /// **'Linux'**
  String get osLinux;

  /// No description provided for @osUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown OS'**
  String get osUnknown;

  /// No description provided for @showStats.
  ///
  /// In en, this message translates to:
  /// **'Show statistics overlay'**
  String get showStats;

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Live stats'**
  String get statsTitle;

  /// No description provided for @statsLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get statsLatency;

  /// No description provided for @statsLoss.
  ///
  /// In en, this message translates to:
  /// **'Packet loss'**
  String get statsLoss;

  /// No description provided for @statsLossHint.
  ///
  /// In en, this message translates to:
  /// **'Estimated from unanswered SSH keep-alive probes'**
  String get statsLossHint;

  /// No description provided for @statsDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get statsDown;

  /// No description provided for @statsUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get statsUp;

  /// No description provided for @statsFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get statsFrameRate;

  /// No description provided for @statsResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get statsResolution;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
