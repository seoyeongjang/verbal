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

enum MessengerFontSizeChoice {
  extraSmall('더 작게', 0.86),
  small('작게', 0.93),
  normal('보통', 1),
  large('크게', 1.08),
  extraLarge('더 크게', 1.16);

  const MessengerFontSizeChoice(this.label, this.scale);

  final String label;
  final double scale;
}

class AppPreferenceScope extends InheritedWidget {
  const AppPreferenceScope({
    required this.language,
    required this.themeChoice,
    required this.fontSizeChoice,
    required this.setLanguage,
    required this.setThemeChoice,
    required this.setFontSizeChoice,
    required super.child,
    super.key,
  });

  final AppLanguage language;
  final MessengerThemeChoice themeChoice;
  final MessengerFontSizeChoice fontSizeChoice;
  final ValueChanged<AppLanguage> setLanguage;
  final ValueChanged<MessengerThemeChoice> setThemeChoice;
  final ValueChanged<MessengerFontSizeChoice> setFontSizeChoice;

  static AppPreferenceScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppPreferenceScope>();
    assert(scope != null, 'AppPreferenceScope is missing above this context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppPreferenceScope oldWidget) {
    return language != oldWidget.language ||
        themeChoice != oldWidget.themeChoice ||
        fontSizeChoice != oldWidget.fontSizeChoice;
  }
}
