import 'keyboard.dart';
import 'stream_settings.dart';

enum AppThemeMode { system, light, dark }

final class AppPreferences {
  const AppPreferences({
    this.themeMode = AppThemeMode.system,
    this.languageCode = '',
    this.stream = const StreamSettings(),
    this.keyMapping = KeyMappingMode.auto,
    this.showStats = true,
  });

  final AppThemeMode themeMode;

  /// Empty means "follow the system locale".
  final String languageCode;
  final StreamSettings stream;
  final KeyMappingMode keyMapping;
  final bool showStats;

  AppPreferences copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    StreamSettings? stream,
    KeyMappingMode? keyMapping,
    bool? showStats,
  }) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        languageCode: languageCode ?? this.languageCode,
        stream: stream ?? this.stream,
        keyMapping: keyMapping ?? this.keyMapping,
        showStats: showStats ?? this.showStats,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'languageCode': languageCode,
        'stream': stream.toJson(),
        'keyMapping': keyMapping.name,
        'showStats': showStats,
      };

  factory AppPreferences.fromJson(Map<String, Object?> j) => AppPreferences(
        themeMode: AppThemeMode.values.asNameMap()[j['themeMode']] ?? AppThemeMode.system,
        languageCode: j['languageCode'] as String? ?? '',
        stream: StreamSettings.fromJson((j['stream'] as Map?)?.cast<String, Object?>() ?? const {}),
        keyMapping: KeyMappingMode.values.asNameMap()[j['keyMapping']] ?? KeyMappingMode.auto,
        showStats: j['showStats'] as bool? ?? true,
      );
}
