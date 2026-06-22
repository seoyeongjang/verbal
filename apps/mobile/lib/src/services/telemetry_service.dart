import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppTelemetry {
  AppTelemetry._();

  static var _enabled = false;

  static Future<void> configure({
    required bool enabled,
    required String backendMode,
  }) async {
    _enabled = enabled;
    if (!enabled) {
      return;
    }

    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await setDefaultContext(backendMode: backendMode);

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
      return false;
    };
  }

  static Future<void> setDefaultContext({required String backendMode}) async {
    if (!_enabled) {
      return;
    }
    await Future.wait([
      FirebaseCrashlytics.instance.setCustomKey(
        'app_backend_mode',
        backendMode,
      ),
      FirebaseCrashlytics.instance.setCustomKey(
        'platform',
        defaultTargetPlatform.name,
      ),
    ]);
  }

  static Future<void> setUser(String uid) async {
    if (!_enabled || uid.trim().isEmpty) {
      return;
    }
    await Future.wait([
      FirebaseAnalytics.instance.setUserId(id: uid),
      FirebaseCrashlytics.instance.setUserIdentifier(uid),
    ]);
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_enabled) {
      return;
    }
    await FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  static Future<void> recordNonFatal(
    Object error,
    StackTrace stack, {
    String? reason,
    Map<String, Object>? information,
  }) async {
    if (!_enabled) {
      return;
    }
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      information: information == null ? const [] : [information],
      fatal: false,
    );
  }
}
