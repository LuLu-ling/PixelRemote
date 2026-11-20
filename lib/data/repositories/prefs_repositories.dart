import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_preferences.dart';
import '../../domain/entities/connection_profile.dart';
import '../../domain/repositories/repositories.dart';

final class PrefsProfileRepository implements ProfileRepository {
  const PrefsProfileRepository(this._prefs);

  static const storageKey = 'profiles.v1';
  final SharedPreferencesWithCache _prefs;

  @override
  List<ConnectionProfile> load() {
    try {
      final list = jsonDecode(_prefs.getString(storageKey) ?? '[]') as List;
      return [for (final j in list) ConnectionProfile.fromJson((j as Map).cast())];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<ConnectionProfile> profiles) =>
      _prefs.setString(storageKey, jsonEncode([for (final p in profiles) p.toJson()]));
}

final class PrefsPreferencesRepository implements PreferencesRepository {
  const PrefsPreferencesRepository(this._prefs);

  static const storageKey = 'preferences.v1';
  final SharedPreferencesWithCache _prefs;

  @override
  AppPreferences load() {
    try {
      return AppPreferences.fromJson((jsonDecode(_prefs.getString(storageKey) ?? '{}') as Map).cast());
    } catch (_) {
      return const AppPreferences();
    }
  }

  @override
  Future<void> save(AppPreferences preferences) => _prefs.setString(storageKey, jsonEncode(preferences.toJson()));
}
