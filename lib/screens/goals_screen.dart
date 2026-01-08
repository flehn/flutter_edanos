import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/meal_repository.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';

/// Goals Screen - User's daily calorie and macro targets
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  GoalsScreenState createState() => GoalsScreenState();
}

class GoalsScreenState extends State<GoalsScreen> {
  /// Public method to refresh data (called when tab becomes active)
  void refresh() {
    _loadData();
  }

  // Weight goal mode: true = gain weight, false = lose weight
  bool _isGainMode = false;

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

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load goals and today's summary in parallel
      final results = await Future.wait([
        MealRepository.getUserGoals(),
        MealRepository.getTodaySummary(),
        _loadWeeklyStats(),
      ]);

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
        isGainMode: _isGainMode, // Preserve the weight mode setting
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

              const SizedBox(height: 24),

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
                  painter: _CircleProgressPainter(
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
                  painter: _CircleProgressPainter(
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
          const SizedBox(height: 24),
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

/// Custom painter for circular progress with rounded ends and dotted support
class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color backgroundColor;
  final double strokeWidth;
  final bool isDotted;

  _CircleProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.backgroundColor,
    required this.strokeWidth,
    this.isDotted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    if (isDotted) {
      // Draw dotted circle
      _drawDottedCircle(canvas, center, radius);
    } else {
      // Draw solid progress arc
      if (progress > 0) {
        final progressPaint = Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        const startAngle = -90 * 3.14159 / 180; // Start from top
        final sweepAngle = progress * 2 * 3.14159;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          progressPaint,
        );
      }
    }
  }

  void _drawDottedCircle(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw dotted circle by drawing small arcs with visible gaps
    const dotCount = 20; // Number of dots around the circle
    const gapRatio = 0.9; // 90% of each segment is gap (smaller dots, bigger gaps)

    const fullCircle = 2 * 3.14159;
    final segmentAngle = fullCircle / dotCount;
    final dotAngle = segmentAngle * (1 - gapRatio);

    const startAngle = -90 * 3.14159 / 180; // Start from top

    for (int i = 0; i < dotCount; i++) {
      final angle = startAngle + (i * segmentAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dotAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.isDotted != isDotted;
  }
}
