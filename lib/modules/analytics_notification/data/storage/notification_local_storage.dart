import 'package:shared_preferences/shared_preferences.dart';

abstract interface class NotificationLocalStorage {
  Future<List<String>?> readNotificationRecords();

  Future<void> writeNotificationRecords(List<String> records);

  Future<String?> readNotificationPreferences();

  Future<void> writeNotificationPreferences(String preferencesJson);
}

class SharedPreferencesNotificationLocalStorage
    implements NotificationLocalStorage {
  SharedPreferencesNotificationLocalStorage({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _notificationsKey = 'module5.transit_notifications';
  static const _preferencesKey = 'module5.notification_preferences';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>?> readNotificationRecords() {
    return _preferences.getStringList(_notificationsKey);
  }

  @override
  Future<void> writeNotificationRecords(List<String> records) {
    return _preferences.setStringList(_notificationsKey, records);
  }

  @override
  Future<String?> readNotificationPreferences() {
    return _preferences.getString(_preferencesKey);
  }

  @override
  Future<void> writeNotificationPreferences(String preferencesJson) {
    return _preferences.setString(_preferencesKey, preferencesJson);
  }
}
