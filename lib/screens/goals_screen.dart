import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/circle_progress_painter.dart';
import '../services/meal_repository.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';
import '../services/progress_service.dart';
import '../widgets/progress_dots_widget.dart';

/// Goals Screen - User's daily calorie and macro targets
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  GoalsScreenState createState() => GoalsScreenState();
}

class GoalsScreenState extends State<GoalsScreen> {
  // Progress dots widget key for refreshing
  final _progressDotsKey = GlobalKey<ProgressDotsWidgetState>();

  /// Public method to refresh data (called when tab becomes active)
  void refresh() {
    _progressDotsKey.currentState?.refresh();
    _loadData();
  }

  // Weight goal mode: true = gain weight, false = lose weight
  bool _isGainMode = false;
  bool _loseFat = false;
  bool _gainMuscles = false;

  // Goals from Firestore
  int _calorieGoal = 2000;
  int _proteinGoal = 150;
  int _carbsGoal = 250;
  int _fatGoal = 67;
  int _perMealProtein = 40;
  int _perMealCarbs = 40;
  int _perMealFat = 20;

  // Today's progress from Firestore
  int _caloriesConsumed = 0;
  int _proteinConsumed = 0;
  int _carbsConsumed = 0;
  int _fatConsumed = 0;

  // Weekly stats (calculated from actual data)
  int _weeklyAvgCalories = 0;
  int _daysTracked = 0;
  int _goalMetDays = 0;

  // Past reports
  List<Map<String, dynamic>> _reports = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load goals, today's summary, weekly stats and reports in parallel
      final reportsFuture = ProgressService.getReportHistory();
      final results = await Future.wait([
        MealRepository.getUserGoals(),
        MealRepository.getTodaySummary(),
        _loadWeeklyStats(),
      ]);
      _reports = await reportsFuture;

      final goals = results[0] as UserGoals;
      final todaySummary = results[1] as DailySummary;

      setState(() {
        _calorieGoal = goals.dailyCalories;
        _proteinGoal = goals.dailyProtein;
        _carbsGoal = goals.dailyCarbs;
        _fatGoal = goals.dailyFat;
        _perMealProtein = goals.perMealProtein;
        _perMealCarbs = goals.perMealCarbs;
        _perMealFat = goals.perMealFat;
        _isGainMode = goals.isGainMode;
        _loseFat = goals.loseFat;
        _gainMuscles = goals.gainMuscles;

        _caloriesConsumed = todaySummary.totalCalories.round();
        _proteinConsumed = todaySummary.totalProtein.round();
        _carbsConsumed = todaySummary.totalCarbs.round();
        _fatConsumed = todaySummary.totalFat.round();
      });
    } catch (e) {
      debugPrint('Error loading goals: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWeeklyStats() async {
    try {
      // Get start of current week (Monday)
      final now = DateTime.now();
      final daysFromMonday = now.weekday - 1;
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: daysFromMonday));

      final weeklySummaries = await MealRepository.getWeeklySummaries(
        weekStart,
      );

      // Calculate stats
      int totalCalories = 0;
      int daysWithMeals = 0;
      int goalMetCount = 0;

      for (final day in weeklySummaries) {
        if (day.mealCount > 0) {
          totalCalories += day.totalCalories.round();
          daysWithMeals++;
          if (day.totalCalories <= _calorieGoal) {
            goalMetCount++;
          }
        }
      }

      setState(() {
        _weeklyAvgCalories = daysWithMeals > 0
            ? (totalCalories / daysWithMeals).round()
            : 0;
        _daysTracked = daysWithMeals;
        _goalMetDays = goalMetCount;
      });
    } catch (e) {
      debugPrint('Error loading weekly stats: $e');
    }
  }

  Future<void> _saveGoals(int calories, int protein, int carbs, int fat) async {
    try {
      final goals = UserGoals(
        dailyCalories: calories,
        dailyProtein: protein,
        dailyCarbs: carbs,
        dailyFat: fat,
        dailyFiber: 30, // Default
        isGainMode: _isGainMode,
        loseFat: _loseFat,
        gainMuscles: _gainMuscles,
        perMealProtein: _perMealProtein,
        perMealCarbs: _perMealCarbs,
        perMealFat: _perMealFat,
      );

      await MealRepository.saveUserGoals(goals);

      setState(() {
        _calorieGoal = calories;
        _proteinGoal = protein;
        _carbsGoal = carbs;
        _fatGoal = fat;
        // Per-meal goals are updated from the sheet save handler
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Goals saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        title: const Text('Goals'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _showEditGoalsSheet,
            child: const Text(
              'Edit',
              style: TextStyle(color: AppTheme.primaryBlue, fontSize: 16),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Weight goal mode toggle
              _buildWeightModeToggle(),

              const SizedBox(height: 12),

              // Goal detail chips
              _buildGoalChips(),

              const SizedBox(height: 16),

              // 20-day progress dots
              ProgressDotsWidget(key: _progressDotsKey),

              const SizedBox(height: 16),

              // Today's Progress title
              const Text(
                "Today's Progress",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 24),

              // Four circular progress indicators in a row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCircularProgress(
                    'Calories',
                    _caloriesConsumed,
                    _calorieGoal,
                    'kcal',
                    AppTheme.calorieOrange,
                  ),
                  _buildCircularProgress(
                    'Protein',
                    _proteinConsumed,
                    _proteinGoal,
                    'g',
                    AppTheme.proteinColor,
                  ),
                  _buildCircularProgress(
                    'Carbs',
                    _carbsConsumed,
                    _carbsGoal,
                    'g',
                    AppTheme.carbsColor,
                  ),
                  _buildCircularProgress(
                    'Fat',
                    _fatConsumed,
                    _fatGoal,
                    'g',
                    AppTheme.fatColor,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Weekly summary
              _buildWeeklySummary(),

              const SizedBox(height: 32),

              // Past Reports
              if (_reports.isNotEmpty) _buildReportHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setWeightMode(bool isGainMode) async {
    if (_isGainMode == isGainMode) return;

    setState(() => _isGainMode = isGainMode);

    // Save to Firestore
    try {
      final goals = UserGoals(
        dailyCalories: _calorieGoal,
        dailyProtein: _proteinGoal,
        dailyCarbs: _carbsGoal,
        dailyFat: _fatGoal,
        dailyFiber: 30,
        isGainMode: isGainMode,
        loseFat: _loseFat,
        gainMuscles: _gainMuscles,
        perMealProtein: _perMealProtein,
        perMealCarbs: _perMealCarbs,
        perMealFat: _perMealFat,
      );
      await MealRepository.saveUserGoals(goals);
    } catch (e) {
      debugPrint('Error saving weight mode: $e');
    }
  }

  Widget _buildWeightModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _setWeightMode(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isGainMode
                      ? AppTheme.primaryBlue.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: !_isGainMode
                      ? Border.all(color: AppTheme.primaryBlue, width: 1.5)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.trending_down,
                      size: 20,
                      color: !_isGainMode
                          ? AppTheme.primaryBlue
                          : AppTheme.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Lose Weight',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: !_isGainMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: !_isGainMode
                            ? AppTheme.primaryBlue
                            : AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _setWeightMode(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isGainMode
                      ? AppTheme.primaryBlue.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: _isGainMode
                      ? Border.all(color: AppTheme.primaryBlue, width: 1.5)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.trending_up,
                      size: 20,
                      color: _isGainMode ? AppTheme.primaryBlue : AppTheme.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gain Weight',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _isGainMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: _isGainMode
                            ? AppTheme.primaryBlue
                            : AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalChips() {
    return Row(
      children: [
        _buildGoalChip('Lose fat', _loseFat, (val) {
          setState(() => _loseFat = val);
          _saveGoalChips();
        }),
        const SizedBox(width: 8),
        _buildGoalChip('Gain muscles', _gainMuscles, (val) {
          setState(() => _gainMuscles = val);
          _saveGoalChips();
        }),
      ],
    );
  }

  Widget _buildGoalChip(String label, bool selected, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryBlue.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primaryBlue : AppTheme.textTertiary.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? AppTheme.primaryBlue : AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Future<void> _saveGoalChips() async {
    try {
      final goals = UserGoals(
        dailyCalories: _calorieGoal,
        dailyProtein: _proteinGoal,
        dailyCarbs: _carbsGoal,
        dailyFat: _fatGoal,
        dailyFiber: 30,
        isGainMode: _isGainMode,
        loseFat: _loseFat,
        gainMuscles: _gainMuscles,
        perMealProtein: _perMealProtein,
        perMealCarbs: _perMealCarbs,
        perMealFat: _perMealFat,
      );
      await MealRepository.saveUserGoals(goals);
    } catch (e) {
      debugPrint('Error saving goal chips: $e');
    }
  }

  Widget _buildCircularProgress(
    String label,
    int consumed,
    int goal,
    String unit,
    Color color,
  ) {
    final progress = goal > 0 ? consumed / goal : 0.0;
    final isOver = progress > 1;
    final percentage = (progress * 100).round();

    // Special handling for Calories based on weight mode
    final isCalories = label == 'Calories';
    Color displayColor;
    Color labelColor;

    if (isCalories) {
      // Calories: show red when goal is NOT met based on weight mode
      // Lose weight: red when over goal (progress >= 1.0)
      // Gain weight: red when under goal (progress < 1.0)
      final goalNotMet = _isGainMode ? (progress < 1.0) : (progress >= 1.0);
      if (goalNotMet) {
        displayColor = AppTheme.negativeColor;
        labelColor = AppTheme.negativeColor;
      } else {
        displayColor = Colors.white;
        labelColor = Colors.white;
      }
    } else {
      // Protein, Carbs, Fat: always use their original colors
      displayColor = color;
      labelColor = color;
    }

    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // White dotted background circle (full circle)
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: CircleProgressPainter(
                    progress: 1.0, // Full circle for background
                    progressColor: Colors.white,
                    backgroundColor: Colors.transparent,
                    strokeWidth: 2, // Thinner dots
                    isDotted: true, // Dotted background
                  ),
                ),
              ),
              // Solid colored progress arc
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: CircleProgressPainter(
                    progress: progress.clamp(0.0, 1.0),
                    progressColor: displayColor,
                    backgroundColor: Colors.transparent,
                    strokeWidth: 5,
                    isDotted: false, // Solid progress
                  ),
                ),
              ),
              // Center content
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.backgroundDark,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$consumed',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${isOver ? '+' : ''}$percentage%',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildWeeklySummary() {
    // Format calories with thousands separator
    final avgCaloriesStr = _weeklyAvgCalories.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This Week',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildWeekStat('Avg. Calories', avgCaloriesStr, 'kcal'),
            Container(
              width: 1,
              height: 50,
              color: Colors.white.withOpacity(0.3),
            ),
            _buildWeekStat('Days Tracked', '$_daysTracked', 'of 7'),
            Container(
              width: 1,
              height: 50,
              color: Colors.white.withOpacity(0.3),
            ),
            _buildWeekStat('Goal Met', '$_goalMetDays', 'days'),
          ],
        ),
      ],
    );
  }

  Widget _buildWeekStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          unit,
          style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildReportHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Past Reports',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._reports.map((report) => _buildReportCard(report)),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final score = (report['progressScore'] as num?)?.toInt() ?? 0;
    final evaluatedAt = report['evaluatedAt'] as String?;
    String dateStr = '';
    if (evaluatedAt != null) {
      final dt = DateTime.tryParse(evaluatedAt);
      if (dt != null) {
        dateStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      }
    }

    Color scoreColor;
    if (score >= 8) {
      scoreColor = AppTheme.positiveColor;
    } else if (score >= 5) {
      scoreColor = AppTheme.warningColor;
    } else {
      scoreColor = AppTheme.negativeColor;
    }

    return GestureDetector(
      onTap: () => _showReportDialog(report),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.assessment, size: 20, color: AppTheme.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scoreColor),
              ),
              child: Text(
                '$score/10',
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(Map<String, dynamic> evaluation) {
    final score = (evaluation['progressScore'] as num?)?.toInt() ?? 5;
    Color scoreColor;
    if (score >= 8) {
      scoreColor = AppTheme.positiveColor;
    } else if (score >= 5) {
      scoreColor = AppTheme.warningColor;
    } else {
      scoreColor = AppTheme.negativeColor;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Text(
              '20-Day Progress',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scoreColor),
              ),
              child: Text(
                '$score/10',
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (evaluation['overallProgress'] != null) ...[
                _buildReportSection(Icons.analytics, 'Overall', evaluation['overallProgress'] as String, AppTheme.primaryBlue),
                const SizedBox(height: 16),
              ],
              if (evaluation['strengths'] != null) ...[
                _buildReportSection(Icons.check_circle, 'Strengths', evaluation['strengths'] as String, AppTheme.positiveColor),
                const SizedBox(height: 16),
              ],
              if (evaluation['improvements'] != null) ...[
                _buildReportSection(Icons.trending_up, 'Improvements', evaluation['improvements'] as String, AppTheme.warningColor),
                const SizedBox(height: 16),
              ],
              if (evaluation['mealTimingFeedback'] != null)
                _buildReportSection(Icons.schedule, 'Meal Timing', evaluation['mealTimingFeedback'] as String, AppTheme.textSecondary),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection(IconData icon, String title, String content, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  void _showEditGoalsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EditGoalsSheet(
        calorieGoal: _calorieGoal,
        proteinGoal: _proteinGoal,
        carbsGoal: _carbsGoal,
        fatGoal: _fatGoal,
        perMealProtein: _perMealProtein,
        perMealCarbs: _perMealCarbs,
        perMealFat: _perMealFat,
        onSave: (calories, protein, carbs, fat, perMealProtein, perMealCarbs,
            perMealFat) {
          setState(() {
            _perMealProtein = perMealProtein;
            _perMealCarbs = perMealCarbs;
            _perMealFat = perMealFat;
          });
          _saveGoals(calories, protein, carbs, fat);
        },
      ),
    );
  }
}

class _EditGoalsSheet extends StatefulWidget {
  final int calorieGoal;
  final int proteinGoal;
  final int carbsGoal;
  final int fatGoal;
  final int perMealProtein;
  final int perMealCarbs;
  final int perMealFat;
  final Function(int, int, int, int, int, int, int) onSave;

  const _EditGoalsSheet({
    required this.calorieGoal,
    required this.proteinGoal,
    required this.carbsGoal,
    required this.fatGoal,
    required this.perMealProtein,
    required this.perMealCarbs,
    required this.perMealFat,
    required this.onSave,
  });

  @override
  State<_EditGoalsSheet> createState() => _EditGoalsSheetState();
}

class _EditGoalsSheetState extends State<_EditGoalsSheet> {
  late TextEditingController _caloriesController;
  late TextEditingController _proteinController;
  late TextEditingController _carbsController;
  late TextEditingController _fatController;
  late TextEditingController _perMealProteinController;
  late TextEditingController _perMealCarbsController;
  late TextEditingController _perMealFatController;

  // User's body weight (from Health or Settings)
  double _bodyWeightKg = 70.0;
  bool _isLoadingWeight = true;
  bool _weightFromHealth = false;

  // Protein preset: 0.8, 1.2, 2.0, or null for custom
  double? _selectedProteinPreset;

  // Track which field was last edited for auto-calculation
  String? _lastEditedMacroField;

  @override
  void initState() {
    super.initState();
    _caloriesController = TextEditingController(
      text: widget.calorieGoal.toString(),
    );
    _proteinController = TextEditingController(
      text: widget.proteinGoal.toString(),
    );
    _carbsController = TextEditingController(text: widget.carbsGoal.toString());
    _fatController = TextEditingController(text: widget.fatGoal.toString());
    _perMealProteinController =
        TextEditingController(text: widget.perMealProtein.toString());
    _perMealCarbsController =
        TextEditingController(text: widget.perMealCarbs.toString());
    _perMealFatController =
        TextEditingController(text: widget.perMealFat.toString());

    // Add listeners to detect manual protein changes
    _proteinController.addListener(_onProteinChanged);
    
    // Add listeners for auto-calculating 4th macro field
    _caloriesController.addListener(() => _onMacroFieldChanged('calories'));
    _proteinController.addListener(() => _onMacroFieldChanged('protein'));
    _carbsController.addListener(() => _onMacroFieldChanged('carbs'));
    _fatController.addListener(() => _onMacroFieldChanged('fat'));

    // Load user's body weight
    _loadBodyWeight();
  }

  Future<void> _loadBodyWeight() async {
    try {
      // First try to get weight from Apple Health if connected
      final hasHealth = await HealthService.hasPermissions();
      if (hasHealth) {
        final healthWeight = await HealthService.getLatestWeight();
        if (healthWeight != null && healthWeight > 0) {
          setState(() {
            _bodyWeightKg = healthWeight;
            _weightFromHealth = true;
            _isLoadingWeight = false;
          });
          return;
        }
      }

      // Fall back to weight from user settings
      final settings = await MealRepository.getUserSettings();
      setState(() {
        _bodyWeightKg = settings.weight;
        _weightFromHealth = false;
        _isLoadingWeight = false;
      });
    } catch (e) {
      debugPrint('Error loading weight: $e');
      setState(() => _isLoadingWeight = false);
    }
  }

  void _onProteinChanged() {
    // If user manually edits protein, switch to custom mode
    // Only trigger if not currently in a preset update
    if (_selectedProteinPreset != null) {
      final currentProtein = int.tryParse(_proteinController.text) ?? 0;
      final expectedProtein = (_bodyWeightKg * _selectedProteinPreset!).round();
      if (currentProtein != expectedProtein) {
        setState(() => _selectedProteinPreset = null);
      }
    }
  }

  void _selectProteinPreset(double? preset) {
    setState(() {
      _selectedProteinPreset = preset;
      if (preset != null) {
        final protein = (_bodyWeightKg * preset).round();
        _proteinController.text = protein.toString();
      }
    });
  }

  /// Track which macro was edited and auto-calculate the 4th
  void _onMacroFieldChanged(String field) {
    _lastEditedMacroField = field;
    _tryAutoCalculateMissingMacro();
  }

  /// Auto-calculate the missing macro when 3 of 4 are set
  /// Formula: calories = 4*protein + 4*carbs + 9*fat
  void _tryAutoCalculateMissingMacro() {
    final caloriesText = _caloriesController.text.trim();
    final proteinText = _proteinController.text.trim();
    final carbsText = _carbsController.text.trim();
    final fatText = _fatController.text.trim();

    final calories = caloriesText.isNotEmpty ? int.tryParse(caloriesText) : null;
    final protein = proteinText.isNotEmpty ? int.tryParse(proteinText) : null;
    final carbs = carbsText.isNotEmpty ? int.tryParse(carbsText) : null;
    final fat = fatText.isNotEmpty ? int.tryParse(fatText) : null;

    // Count how many fields have valid values (0 is valid, only null/empty is "not filled")
    int filledCount = 0;
    if (calories != null) filledCount++;
    if (protein != null) filledCount++;
    if (carbs != null) filledCount++;
    if (fat != null) filledCount++;

    // Only calculate if exactly 3 fields are filled
    if (filledCount != 3) return;

    // Determine which field is missing and calculate it
    // Don't auto-calculate into the field the user is currently editing
    if (calories == null && _lastEditedMacroField != 'calories') {
      // Calculate calories from macros
      final calculated = (protein! * 4) + (carbs! * 4) + (fat! * 9);
      _caloriesController.text = calculated.toString();
    } else if (protein == null && _lastEditedMacroField != 'protein') {
      // Calculate protein: protein = (calories - 4*carbs - 9*fat) / 4
      final proteinCalories = calories! - (carbs! * 4) - (fat! * 9);
      if (proteinCalories > 0) {
        final calculated = (proteinCalories / 4).round();
        _proteinController.removeListener(_onProteinChanged);
        _proteinController.text = calculated.toString();
        _proteinController.addListener(_onProteinChanged);
        _selectedProteinPreset = null;
      }
    } else if (carbs == null && _lastEditedMacroField != 'carbs') {
      // Calculate carbs: carbs = (calories - 4*protein - 9*fat) / 4
      final carbsCalories = calories! - (protein! * 4) - (fat! * 9);
      if (carbsCalories > 0) {
        final calculated = (carbsCalories / 4).round();
        _carbsController.text = calculated.toString();
      }
    } else if (fat == null && _lastEditedMacroField != 'fat') {
      // Calculate fat: fat = (calories - 4*protein - 4*carbs) / 9
      final fatCalories = calories! - (protein! * 4) - (carbs! * 4);
      if (fatCalories > 0) {
        final calculated = (fatCalories / 9).round();
        _fatController.text = calculated.toString();
      }
    }
  }

  /// Calculate calories from macros: 4*protein + 4*carbs + 9*fat
  int _calculateCaloriesFromMacros() {
    final protein = int.tryParse(_proteinController.text) ?? 0;
    final carbs = int.tryParse(_carbsController.text) ?? 0;
    final fat = int.tryParse(_fatController.text) ?? 0;
    return (protein * 4) + (carbs * 4) + (fat * 9);
  }

  @override
  void dispose() {
    _proteinController.removeListener(_onProteinChanged);
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _perMealProteinController.dispose();
    _perMealCarbsController.dispose();
    _perMealFatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calculatedCalories = _calculateCaloriesFromMacros();
    final enteredCalories = int.tryParse(_caloriesController.text) ?? 0;
    final caloriesDiff = (calculatedCalories - enteredCalories).abs();
    final hasSignificantDiff = caloriesDiff > 50;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Goals',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onSave(
                    int.tryParse(_caloriesController.text) ??
                        widget.calorieGoal,
                    int.tryParse(_proteinController.text) ?? widget.proteinGoal,
                    int.tryParse(_carbsController.text) ?? widget.carbsGoal,
                    int.tryParse(_fatController.text) ?? widget.fatGoal,
                    int.tryParse(_perMealProteinController.text) ??
                        widget.perMealProtein,
                    int.tryParse(_perMealCarbsController.text) ??
                        widget.perMealCarbs,
                    int.tryParse(_perMealFatController.text) ??
                        widget.perMealFat,
                  );
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'These are not recommendations. You can freely set your individual goals.',
            style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
          ),
          const SizedBox(height: 20),
          _buildGoalInput('Daily Calories', _caloriesController, 'kcal'),
          const SizedBox(height: 16),
          _buildGoalInput('Protein', _proteinController, 'g'),

          // Protein preset buttons
          const SizedBox(height: 12),
          _buildProteinPresets(),

          const SizedBox(height: 16),
          _buildGoalInput('Carbohydrates', _carbsController, 'g'),
          const SizedBox(height: 16),
          _buildGoalInput('Fat', _fatController, 'g'),

          // Macro formula info text
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasSignificantDiff
                  ? AppTheme.warningColor.withOpacity(0.1)
                  : AppTheme.cardDark,
              borderRadius: BorderRadius.circular(8),
              border: hasSignificantDiff
                  ? Border.all(color: AppTheme.warningColor.withOpacity(0.3))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: hasSignificantDiff
                      ? AppTheme.warningColor
                      : AppTheme.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calculated: $calculatedCalories kcal (4×protein + 4×carbs + 9×fat)',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasSignificantDiff
                          ? AppTheme.warningColor
                          : AppTheme.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Per meal targets',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'These are your nutrition goals per individual meal.',
            style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
          ),
          const SizedBox(height: 12),
          _buildGoalInput('Protein per meal', _perMealProteinController, 'g'),
          const SizedBox(height: 12),
          _buildGoalInput('Carbs per meal', _perMealCarbsController, 'g'),
          const SizedBox(height: 12),
          _buildGoalInput('Fat per meal', _perMealFatController, 'g'),
          ],
        ),
      ),
    );
  }

  Widget _buildProteinPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preset buttons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPresetButton(0.8, '0.8g/kg'),
              const SizedBox(width: 8),
              _buildPresetButton(1.2, '1.2g/kg'),
              const SizedBox(width: 8),
              _buildPresetButton(2.0, '2.0g/kg'),
              const SizedBox(width: 8),
              _buildPresetButton(null, 'Custom'),
            ],
          ),
        ),
        // Weight source info
        const SizedBox(height: 8),
        if (_isLoadingWeight)
          Text(
            'Loading body weight...',
            style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
          )
        else
          Text(
            'Based on ${_bodyWeightKg.toStringAsFixed(1)} kg${_weightFromHealth ? ' (from Health)' : ''}',
            style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
          ),
      ],
    );
  }

  Widget _buildPresetButton(double? preset, String label) {
    final isSelected = _selectedProteinPreset == preset;
    return GestureDetector(
      onTap: () => _selectProteinPreset(preset),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.proteinColor.withOpacity(0.2)
              : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.proteinColor
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.proteinColor : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGoalInput(
    String label,
    TextEditingController controller,
    String unit,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}), // Trigger rebuild for macro calc
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.cardDark,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            unit,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

