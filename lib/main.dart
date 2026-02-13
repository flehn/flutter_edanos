import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseException;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'app_shell.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/onboarding_service.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.surfaceDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Firebase App Check for security
  // Using Play Integrity for Android (production)
  // Using App Attest for iOS (requires iOS 14.0+, production)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.appAttest //.appAttest,
  );

  // Ensure user is signed in (anonymously if needed)
  // This guarantees a valid user ID for Firestore and Storage
  try {
    await AuthService.ensureSignedIn();
  } catch (e, stackTrace) {
    debugPrint('=== FIREBASE AUTH ERROR ===');
    debugPrint('Error type: ${e.runtimeType}');
    debugPrint('Error: $e');
    if (e is FirebaseException) {
      debugPrint('Firebase Error Code: ${e.code}');
      debugPrint('Firebase Error Message: ${e.message}');
      debugPrint('Firebase Plugin: ${e.plugin}');
      debugPrint('');
      debugPrint('TROUBLESHOOTING:');
      debugPrint('1. Check Firebase Console > App Check — if Authentication is "Enforced", '
            'either disable enforcement or enable the debug provider in code.');
      debugPrint('2. Check GCP Console > APIs & Services > Library — '
            'ensure "Identity Toolkit API" is enabled.');
      debugPrint('3. Check GCP Console > APIs & Services > Credentials — '
            'ensure the iOS API key allows "Identity Toolkit API" and "Token Service API".');
    }
    debugPrint('Stack trace: $stackTrace');
    debugPrint('===========================');

    // Don't crash the app — retry once after a short delay
    debugPrint('Retrying anonymous sign-in after 2 seconds...');
    await Future.delayed(const Duration(seconds: 2));
    try {
      await AuthService.ensureSignedIn();
      debugPrint('Retry succeeded!');
    } catch (retryError) {
      debugPrint('Retry also failed: $retryError');
      rethrow;
    }
  }

  // Initialize notification service for meal reminders
  await NotificationService.initialize();

  runApp(const EdanosAIApp());
}

class EdanosAIApp extends StatelessWidget {
  const EdanosAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EdanosAI Food Analyzer',
      theme: AppTheme.darkTheme,
      home: FutureBuilder<bool>(
        future: OnboardingService.hasSeenOnboarding(),
        builder: (context, snapshot) {
          // Show loading indicator while checking
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppTheme.backgroundDark,
              body: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryBlue,
                ),
              ),
            );
          }
          // Show onboarding if not seen, otherwise show main app
          final hasSeenOnboarding = snapshot.data ?? false;
          return hasSeenOnboarding ? const AppShell() : const OnboardingScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
