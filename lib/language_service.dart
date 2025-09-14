import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _languageKey = 'selected_language';
  static const String _defaultLanguage = 'zh';
  
  static const Map<String, String> supportedLanguages = {
    'zh': '中文',
    'en': 'English',
  };

  /// 获取当前语言
  static Future<String> getCurrentLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? _defaultLanguage;
  }

  /// 设置语言
  static Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }

  /// 获取语言显示名称
  static String getLanguageDisplayName(String languageCode) {
    return supportedLanguages[languageCode] ?? languageCode;
  }

  /// 检查是否支持该语言
  static bool isLanguageSupported(String languageCode) {
    return supportedLanguages.containsKey(languageCode);
  }

  /// 获取所有支持的语言
  static List<String> getSupportedLanguages() {
    return supportedLanguages.keys.toList();
  }
}

