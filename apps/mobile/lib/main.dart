import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/models/messenger_models.dart';
import 'src/services/app_preferences.dart';
import 'src/services/briefing_speaker.dart';
import 'src/services/demo_backend.dart';
import 'src/services/firebase_app_config.dart';
import 'src/services/firebase_backend.dart';
import 'src/services/local_stt_transcriber.dart';
import 'src/services/messenger_backend.dart';
import 'src/ui/auth/auth_screen.dart';
import 'src/ui/home/home_screen.dart';
import 'src/ui/profile/profile_setup_screen.dart';

const _kAppLogoBlack = Color(0xFF111111);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(_systemChromeStyle);

  const forceDemo = bool.fromEnvironment('VERBAL_DEMO');
  const localStt = bool.fromEnvironment('VERBAL_LOCAL_STT');
  const localSttEndpoint = String.fromEnvironment(
    'LOCAL_STT_ENDPOINT',
    defaultValue: 'http://127.0.0.1:8787/transcribe',
  );
  final firebaseOptions = FirebaseAppConfig.currentPlatform;
  final MessengerBackend backend;
  if (localStt) {
    backend = DemoMessengerBackend(
      transcriber: LocalSttTranscriber(endpoint: localSttEndpoint).transcribe,
    );
  } else if (forceDemo || firebaseOptions == null) {
    backend = DemoMessengerBackend();
  } else {
    await Firebase.initializeApp(options: firebaseOptions);
    backend = FirebaseMessengerBackend();
  }

  runApp(VerbalApp(backend: backend));
}

class VerbalApp extends StatefulWidget {
  const VerbalApp({required this.backend, super.key});

  final MessengerBackend backend;

  @override
  State<VerbalApp> createState() => _VerbalAppState();
}

class _VerbalAppState extends State<VerbalApp> {
  var _language = AppLanguage.ko;
  var _themeChoice = MessengerThemeChoice.system;
  var _fontSizeChoice = MessengerFontSizeChoice.normal;

  @override
  Widget build(BuildContext context) {
    return AppPreferenceScope(
      language: _language,
      themeChoice: _themeChoice,
      fontSizeChoice: _fontSizeChoice,
      setLanguage: (language) => setState(() => _language = language),
      setThemeChoice: (choice) => setState(() => _themeChoice = choice),
      setFontSizeChoice: (choice) => setState(() => _fontSizeChoice = choice),
      child: BackendScope(
        backend: widget.backend,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Verbal',
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemChromeStyle,
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(_fontSizeChoice.scale),
                ),
                child: _ResponsivePhoneShell(child: child),
              ),
            );
          },
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: _themeChoice.themeMode,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

const _systemChromeStyle = SystemUiOverlayStyle(
  statusBarColor: _kAppLogoBlack,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: _kAppLogoBlack,
  systemNavigationBarDividerColor: _kAppLogoBlack,
  systemNavigationBarIconBrightness: Brightness.light,
);

ThemeData _buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF00A86B),
      onPrimary: Colors.white,
      secondary: Color(0xFF009E74),
      onSecondary: Colors.white,
      tertiary: Color(0xFF119B4F),
      surface: _kAppLogoBlack,
      onSurface: Color(0xFFF7F7F8),
      error: Color(0xFFD92D20),
    ),
    scaffoldBackgroundColor: _kAppLogoBlack,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: _kAppLogoBlack,
      foregroundColor: Color(0xFFF7F7F8),
      surfaceTintColor: _kAppLogoBlack,
      titleTextStyle: TextStyle(
        color: Color(0xFFF7F7F8),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Color(0xFF1C211F),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF00A86B),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xFF1C1C1E),
      surfaceTintColor: Color(0xFF1C1C1E),
    ),
  );
}

ThemeData _buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF24C987),
      onPrimary: Colors.white,
      secondary: Color(0xFF20B982),
      onSecondary: Colors.white,
      tertiary: Color(0xFF5BDB91),
      surface: Color(0xFF111815),
      onSurface: Color(0xFFF7FFF9),
      error: Color(0xFFFF6B6B),
    ),
    scaffoldBackgroundColor: const Color(0xFF111815),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Color(0xFF111815),
      foregroundColor: Color(0xFFF7FFF9),
      surfaceTintColor: Color(0xFF111815),
      titleTextStyle: TextStyle(
        color: Color(0xFFF7FFF9),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Color(0xFF193A2A),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF17211C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF00A86B),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xFF17211C),
      surfaceTintColor: Color(0xFF17211C),
    ),
  );
}

class _ResponsivePhoneShell extends StatelessWidget {
  const _ResponsivePhoneShell({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return content;
        }
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kAppLogoBlack, Color(0xFF17191B), Color(0xFF050505)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: AspectRatio(
                aspectRatio: 390 / 760,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kAppLogoBlack,
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return StreamBuilder<AppUser?>(
      stream: backend.authState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _LoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) {
          return AuthScreen(isDemoMode: !backend.isConfigured);
        }
        if (!user.hasProfile) {
          return ProfileSetupScreen(user: user);
        }
        return HomeBootstrap(user: user);
      },
    );
  }
}

class HomeBootstrap extends StatefulWidget {
  const HomeBootstrap({required this.user, super.key});

  final AppUser user;

  @override
  State<HomeBootstrap> createState() => _HomeBootstrapState();
}

class _HomeBootstrapState extends State<HomeBootstrap> {
  var _registeredToken = false;
  var _checkedInitialMessage = false;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _openedMessageSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = BackendScope.of(context);
    if (!_registeredToken) {
      _registeredToken = true;
      backend.registerMessagingToken();
    }
    if (backend.isConfigured && _foregroundMessageSub == null) {
      _foregroundMessageSub = FirebaseMessaging.onMessage.listen(
        _handleRemoteMessage,
      );
      _openedMessageSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteMessage,
      );
    }
    if (backend.isConfigured && !_checkedInitialMessage) {
      _checkedInitialMessage = true;
      unawaited(
        FirebaseMessaging.instance.getInitialMessage().then((message) {
          if (message != null) {
            _handleRemoteMessage(message);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _foregroundMessageSub?.cancel();
    _openedMessageSub?.cancel();
    super.dispose();
  }

  void _handleRemoteMessage(RemoteMessage message) {
    if (message.data['type'] != 'calendarMorningBriefing') {
      return;
    }
    final dataText = message.data['briefingText']?.toString().trim();
    final body = message.notification?.body?.trim();
    final briefingText = dataText?.isNotEmpty == true
        ? dataText!
        : body?.isNotEmpty == true
        ? body!
        : '오늘의 일정 브리핑입니다.';
    unawaited(BriefingSpeaker.speak(briefingText));
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(user: widget.user);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00A86B))),
    );
  }
}
