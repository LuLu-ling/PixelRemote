import '../entities/app_preferences.dart';
import '../entities/connection_profile.dart';

abstract interface class ProfileRepository {
  List<ConnectionProfile> load();
  Future<void> save(List<ConnectionProfile> profiles);
}

abstract interface class PreferencesRepository {
  AppPreferences load();
  Future<void> save(AppPreferences preferences);
}
