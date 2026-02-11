import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/onboarding_service.dart';
import '../app_shell.dart';

/// Onboarding screen shown on first app launch
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    await OnboardingService.setOnboardingComplete();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AppShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: const [
                  _WelcomePage(),
                  _AIEvaluationPage(),
                  _DailyViewPage(),
                  _MealDetailsPage(),
                ],
              ),
            ),
            // Page indicator dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _totalPages,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppTheme.primaryBlue
                          : AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            // Next/Get Started button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _currentPage == _totalPages - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 1: Welcome & Core Feature
class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      icon: Icons.restaurant_menu,
      iconColor: AppTheme.accentOrange,
      title: 'Welcome to EdanosAI',
      subtitle: 'Your AI-powered nutrition tracker',
      description:
          'Take pictures of your meals or scan nutritional labels from food packages. '
          'Our AI instantly extracts all nutritional information and logs it for you.',
      highlightText: '📸 Food photos  •  🏷️ Nutrition labels',
    );
  }
}

/// Page 2: AI Health Evaluation
class _AIEvaluationPage extends StatelessWidget {
  const _AIEvaluationPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      icon: Icons.insights,
      iconColor: AppTheme.accentGreen,
      title: 'AI Health Insights',
      subtitle: 'Personalized recommendations',
      description:
          'After scanning at least 3 meals, unlock your AI health evaluation. '
          'Get a comprehensive overview of your nutrition and actionable insights to improve your diet.',
      highlightText: '✨ Scan 3+ meals to unlock insights',
    );
  }
}

/// Page 3: Understanding the Daily View
class _DailyViewPage extends StatelessWidget {
  const _DailyViewPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      icon: Icons.bar_chart_rounded,
      iconColor: AppTheme.primaryBlue,
      title: 'Track Your Progress',
      subtitle: 'Weekly calorie overview',
      description:
          'The main screen shows your weekly calorie consumption with colorful bars. '
          'Each bar displays protein, carbs, and fat distribution. '
          'The number below shows total kcal for that day.',
      highlightText: '🔵 Protein  •  🟢 Carbs  •  🟠 Fat',
    );
  }
}

/// Page 4: Meal Details & Editing
class _MealDetailsPage extends StatelessWidget {
  const _MealDetailsPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      icon: Icons.edit_note,
      iconColor: AppTheme.fiberColor,
      title: 'Fine-tune Your Meals',
      subtitle: 'Full control over ingredients',
      description:
          'Tap any scanned dish to see complete nutritional details. '
          'Adjust ingredient amounts with sliders, or add new ingredients using the camera or search.',
      highlightText: '📝 Edit amounts  •  📷 Add via camera',
    );
  }
}

/// Reusable page template
class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
  final String highlightText;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.highlightText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with gradient background
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  iconColor.withOpacity(0.3),
                  iconColor.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(
              icon,
              size: 56,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 40),
          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              color: iconColor,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Description
          Text(
            description,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Highlight text chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              highlightText,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
