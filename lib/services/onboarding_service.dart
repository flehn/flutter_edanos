import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage first-time onboarding state
class OnboardingService {
  // SharedPreferences key for onboarding completion state
  static const String _hasSeenOnboardingKey = 'has_seen_onboarding';

  /// Check if user has completed onboarding
  static Future<bool> hasSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hasSeenOnboardingKey) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Mark onboarding as complete
  static Future<void> setOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasSeenOnboardingKey, true);
    } catch (e) {
      // Ignore errors - worst case user sees onboarding again
    }
  }

  /// Reset onboarding state (for testing)
  static Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_hasSeenOnboardingKey);
    } catch (e) {
      // Ignore errors
    }
  }
}
