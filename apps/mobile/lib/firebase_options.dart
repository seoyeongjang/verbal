import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return android;
        case TargetPlatform.iOS:
          return ios;
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          break;
      }
    }
    throw UnsupportedError('Firebase is configured for Android and iOS only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDjkwqlejaw7fPfzcHJ3T4JCa6n1zY6-5o',
    appId: '1:203811587610:android:60b60d74b332290520f3a3',
    messagingSenderId: '203811587610',
    projectId: 'voice-messenger-jangs-260522',
    storageBucket: 'voice-messenger-jangs-260522.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBA438qYBAESmVqWtxD1xwwGCMlyNiq1VE',
    appId: '1:203811587610:ios:e953a69e5930e77720f3a3',
    messagingSenderId: '203811587610',
    projectId: 'voice-messenger-jangs-260522',
    storageBucket: 'voice-messenger-jangs-260522.firebasestorage.app',
    iosBundleId: 'com.voicebeta.verbal',
  );
}
