import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'app_shell.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

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
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        AndroidProvider.debug, // Change to .playIntegrity for production
    appleProvider: AppleProvider.debug, // Change to .appAttest for production
  );

  // Ensure user is signed in (anonymously if needed)
  // This guarantees a valid user ID for Firestore and Storage
  await AuthService.ensureSignedIn();

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
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
