import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences? _prefs;

class StorageService {
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String? get(String key) => _prefs?.getString(key);

  static void set(String key, String value) => _prefs?.setString(key, value);

  static void remove(String key) => _prefs?.remove(key);
}
