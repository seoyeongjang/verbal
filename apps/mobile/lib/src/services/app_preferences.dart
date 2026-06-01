import 'package:flutter/material.dart';

enum AppLanguage {
  ko('한국어', 'ko'),
  en('English', 'en'),
  ja('日本語', 'ja'),
  zh('中文', 'zh');

  const AppLanguage(this.label, this.code);

  final String label;
  final String code;
}

enum MessengerThemeChoice {
  system('시스템 설정', ThemeMode.system),
  light('라이트 모드', ThemeMode.light),
  dark('다크 모드', ThemeMode.dark);

  const MessengerThemeChoice(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;
}

class AppPreferenceScope extends InheritedWidget {
  const AppPreferenceScope({
    required this.language,
    required this.themeChoice,
    required this.setLanguage,
    required this.setThemeChoice,
    required super.child,
    super.key,
  });

  final AppLanguage language;
  final MessengerThemeChoice themeChoice;
  final ValueChanged<AppLanguage> setLanguage;
  final ValueChanged<MessengerThemeChoice> setThemeChoice;

  static AppPreferenceScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppPreferenceScope>();
    assert(scope != null, 'AppPreferenceScope is missing above this context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppPreferenceScope oldWidget) {
    return language != oldWidget.language ||
        themeChoice != oldWidget.themeChoice;
  }
}
