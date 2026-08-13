import 'dart:html' as html;

class StorageService {
  static String? get(String key) => html.window.localStorage[key];
  static void set(String key, String value) => html.window.localStorage[key] = value;
  static void remove(String key) => html.window.localStorage.remove(key);
  static Future<void> init() async {}
}
