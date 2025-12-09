import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/meal.dart';
import '../services/meal_repository.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';
import 'meal_detail_screen.dart';

/// Food Log Screen - Daily overview with weekly chart
class FoodLogScreen extends StatefulWidget {
  const FoodLogScreen({super.key});

  @override
  FoodLogScreenState createState() => FoodLogScreenState();
}

class FoodLogScreenState extends State<FoodLogScreen> {
  /// Public method to refresh data (called when tab becomes active)
  void refresh() {
    _loadWeekData();
  }
  int _currentWeek = 0;
  List<DailySummary> _weekData = [];
  List<Meal> _selectedDayMeals = [];
  int _selectedDayIndex = 6; // Sunday selected
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  
  // Health data
  double _burnedCalories = 0;
  Map<DateTime, double> _weeklyBurnedCalories = {};

  @override
  void initState() {
    super.initState();
    _initializeWeek();
  }

  void _initializeWeek() {
    final now = DateTime.now();
    _currentWeek = _getWeekNumber(now);
    _selectedDayIndex = now.weekday - 1; // 0 = Monday
    _selectedDate = now;
    _loadWeekData();
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysDiff = date.difference(firstDayOfYear).inDays;
    return ((daysDiff + firstDayOfYear.weekday) / 7).ceil();
  }

  DateTime _getWeekStart(int weekNumber, int year) {
    final jan1 = DateTime(year, 1, 1);
    final daysToMonday = (jan1.weekday - 1) % 7;
    final week1Monday = jan1.subtract(Duration(days: daysToMonday));
    return week1Monday.add(Duration(days: (weekNumber - 1) * 7));
  }

  Future<void> _loadWeekData() async {
    setState(() => _isLoading = true);
    
    try {
      final now = DateTime.now();
      final weekStart = _getWeekStart(_currentWeek, now.year);
      
      // Load weekly summaries
      final summaries = await MealRepository.getWeeklySummaries(weekStart);
      
      // Create a full week of summaries (fill in empty days)
      final fullWeek = <DailySummary>[];
      for (var i = 0; i < 7; i++) {
        final date = weekStart.add(Duration(days: i));
        final existing = summaries.firstWhere(
          (s) => s.date.day == date.day && s.date.month == date.month,
          orElse: () => DailySummary.empty(date),
        );
        fullWeek.add(existing);
      }
      
      setState(() {
        _weekData = fullWeek;
      });
      
      // Load meals for selected day
      await _loadMealsForSelectedDay();
      
      // Load burned calories from health data (if available)
      await _loadHealthData(weekStart);
    } catch (e) {
      debugPrint('Error loading week data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHealthData(DateTime weekStart) async {
    if (!HealthService.isAvailable) return;
    
    try {
      // Check if we have permissions
      final hasPerms = await HealthService.hasPermissions();
      if (!hasPerms) return;
      
      // Load burned calories for selected day
      final todayBurned = await HealthService.getBurnedCaloriesForDate(_selectedDate);
      
      // Load weekly burned calories
      final weeklyBurned = await HealthService.getWeeklyBurnedCalories(weekStart);
      
      setState(() {
        _burnedCalories = todayBurned;
        _weeklyBurnedCalories = weeklyBurned;
      });
    } catch (e) {
      debugPrint('Error loading health data: $e');
    }
  }

  Future<void> _loadMealsForSelectedDay() async {
    try {
      final meals = await MealRepository.getMealsForDate(_selectedDate);
      setState(() => _selectedDayMeals = meals);
      
      // Get burned calories from cached weekly data if available
      // This avoids duplicate API calls - weekly data is already loaded
      final dayKey = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final cachedBurned = _weeklyBurnedCalories[dayKey];
      
      if (cachedBurned != null) {
        setState(() => _burnedCalories = cachedBurned);
      } else if (HealthService.isAvailable) {
        // Only fetch if not in cache (e.g., viewing a different week)
        final burned = await HealthService.getBurnedCaloriesForDate(_selectedDate);
        setState(() => _burnedCalories = burned);
      }
    } catch (e) {
      debugPrint('Error loading meals: $e');
    }
  }

  void _onDaySelected(int index) {
    final now = DateTime.now();
    final weekStart = _getWeekStart(_currentWeek, now.year);
    final selectedDate = weekStart.add(Duration(days: index));
    
    setState(() {
      _selectedDayIndex = index;
      _selectedDate = selectedDate;
    });
    
    _loadMealsForSelectedDay();
  }

  void _changeWeek(int delta) {
    setState(() {
      _currentWeek += delta;
    });
    _loadWeekData();
  }

  @override
  Widget build(BuildContext context) {
    // Handle loading state or empty data
    if (_isLoading && _weekData.isEmpty) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }
    
    // Safely get selected day data
    final selectedDay = _weekData.isNotEmpty && _selectedDayIndex < _weekData.length
        ? _weekData[_selectedDayIndex]
        : DailySummary.empty(DateTime.now());
    
    final totalConsumed = selectedDay.totalCalories.round();
    final burned = _burnedCalories.round(); // From Apple Health / Health Connect
    final netCalories = totalConsumed - burned;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Calories summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Calories Today label
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Calories',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Stats
                  _buildCalorieBox(
                    'Consumed',
                    totalConsumed,
                    AppTheme.calorieOrange,
                  ),
                  const SizedBox(width: 12),
                  _buildCalorieBox('Burned', burned, AppTheme.positiveColor),
                  const SizedBox(width: 12),
                  _buildCalorieBox(
                    'Net Calories',
                    netCalories,
                    netCalories < 0
                        ? AppTheme.negativeColor
                        : AppTheme.positiveColor,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Macros summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMacroDot(
                    AppTheme.proteinColor,
                    'Protein',
                    selectedDay.totalProtein.round(),
                  ),
                  const SizedBox(width: 24),
                  _buildMacroDot(
                    AppTheme.carbsColor,
                    'Carbs',
                    selectedDay.totalCarbs.round(),
                  ),
                  const SizedBox(width: 24),
                  _buildMacroDot(AppTheme.fatColor, 'Fat', selectedDay.totalFat.round()),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Weekly chart
            Container(
              height: 160,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _weekData.isEmpty
                  ? const Center(child: Text('No data', style: TextStyle(color: AppTheme.textTertiary)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(_weekData.length, (index) {
                        return _buildDayBarFromSummary(index, _weekData[index]);
                      }),
                    ),
            ),

            // Week navigation
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.textTertiary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    onPressed: () => _changeWeek(-1),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'WEEK: $_currentWeek',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.textTertiary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    onPressed: () => _changeWeek(1),
                  ),
                ],
              ),
            ),

            // Date label
            Text(
              _formatDateLabel(_selectedDate),
              style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
            ),

            const SizedBox(height: 16),

            // Meals list
            Expanded(
              child: _selectedDayMeals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restaurant_menu,
                            size: 64,
                            color: AppTheme.textTertiary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No meals logged',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _selectedDayMeals.length,
                      itemBuilder: (context, index) {
                        return _buildMealCardFromMeal(_selectedDayMeals[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieBox(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value < 0
                ? '${value.abs()}'
                : value.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]}.',
                  ),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMacroDot(Color color, String label, int value) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $value',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  String _formatDateLabel(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return 'Scanned on ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getDayName(int index) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[index];
  }

  Widget _buildDayBarFromSummary(int index, DailySummary day) {
    final isSelected = index == _selectedDayIndex;
    final calories = day.totalCalories.round();
    final protein = day.totalProtein.round();
    final carbs = day.totalCarbs.round();
    final fat = day.totalFat.round();
    
    final maxCalories = _weekData
        .map((d) => d.totalCalories.round())
        .reduce((a, b) => a > b ? a : b);
    final barHeight = maxCalories > 0
        ? (calories / maxCalories) * 100
        : 0.0;

    return GestureDetector(
      onTap: () => _onDaySelected(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Stacked bar or three dots for empty days
          if (calories > 0)
            Container(
              width: 36,
              height: barHeight,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              child: Column(
                children: [
                  // Protein (top)
                  Expanded(
                    flex: protein,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.proteinColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  // Carbs (middle)
                  Expanded(
                    flex: carbs,
                    child: Container(color: AppTheme.carbsColor),
                  ),
                  // Fat (bottom)
                  Expanded(
                    flex: fat,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.fatColor,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            // Three colored dots for empty days
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.proteinColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.carbsColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.fatColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Day label
          Text(
            _getDayName(index),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          // Calorie count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryBlue.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isSelected
                  ? Border.all(color: AppTheme.primaryBlue)
                  : null,
            ),
            child: Text(
              calories > 0
                  ? calories.toString().replaceAllMapped(
                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                      (Match m) => '${m[1]}.',
                    )
                  : '0',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppTheme.primaryBlue
                    : AppTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealCardFromMeal(Meal meal) {
    return Dismissible(
      key: Key(meal.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _deleteMeal(meal),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.negativeColor,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      child: GestureDetector(
        onTap: () async {
          final result = await Navigator.of(context).push<Meal>(
            MaterialPageRoute(
              builder: (context) => MealDetailScreen(meal: meal),
            ),
          );
          // If a meal was returned, its date changed - refresh the data
          if (result != null) {
            _loadWeekData();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.textTertiary.withOpacity(0.2)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                // Meal image
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildMealThumbnail(meal),
                ),
                const SizedBox(width: 16),
                // Meal info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${meal.totalCalories.round()} calories',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.calorieOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatMealTime(meal.scannedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMeal(Meal meal) async {
    // Store the meal and its index in case we need to restore it
    final mealIndex = _selectedDayMeals.indexWhere((m) => m.id == meal.id);
    final deletedMeal = meal;
    final mealId = meal.id;
    
    debugPrint('🗑️ Attempting to delete meal: $mealId (${meal.name})');
    
    // Immediately remove from local state to satisfy Dismissible requirement
    setState(() {
      _selectedDayMeals.removeWhere((m) => m.id == meal.id);
      
      // Also update the week data locally to reflect the deletion in charts
      if (_selectedDayIndex < _weekData.length) {
        final currentSummary = _weekData[_selectedDayIndex];
        _weekData[_selectedDayIndex] = DailySummary(
          date: currentSummary.date,
          mealCount: currentSummary.mealCount - 1,
          totalCalories: currentSummary.totalCalories - meal.totalCalories,
          totalProtein: currentSummary.totalProtein - meal.totalProtein,
          totalCarbs: currentSummary.totalCarbs - meal.totalCarbs,
          totalFat: currentSummary.totalFat - meal.totalFat,
          totalFiber: currentSummary.totalFiber - meal.totalFiber,
          totalSugar: currentSummary.totalSugar - meal.totalSugar,
        );
      }
    });
    
    try {
      debugPrint('🗑️ Calling MealRepository.deleteMeal for: $mealId');
      await MealRepository.deleteMeal(mealId);
      debugPrint('✅ Successfully deleted meal from Firebase: $mealId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${meal.name} deleted'),
            backgroundColor: AppTheme.textSecondary,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to delete meal: $mealId');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      
      if (mounted) {
        // Restore the meal if delete failed
        setState(() {
          // Restore the meal at its original position
          if (mealIndex >= 0 && mealIndex <= _selectedDayMeals.length) {
            _selectedDayMeals.insert(mealIndex, deletedMeal);
          } else {
            _selectedDayMeals.add(deletedMeal);
          }
          
          // Restore the week data summary
          if (_selectedDayIndex < _weekData.length) {
            final currentSummary = _weekData[_selectedDayIndex];
            _weekData[_selectedDayIndex] = DailySummary(
              date: currentSummary.date,
              mealCount: currentSummary.mealCount + 1,
              totalCalories: currentSummary.totalCalories + deletedMeal.totalCalories,
              totalProtein: currentSummary.totalProtein + deletedMeal.totalProtein,
              totalCarbs: currentSummary.totalCarbs + deletedMeal.totalCarbs,
              totalFat: currentSummary.totalFat + deletedMeal.totalFat,
              totalFiber: currentSummary.totalFiber + deletedMeal.totalFiber,
              totalSugar: currentSummary.totalSugar + deletedMeal.totalSugar,
            );
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _addToQuickAdd(Meal meal) async {
    try {
      final quickAddItem = MealRepository.mealToQuickAdd(meal);
      await MealRepository.saveQuickAddItem(quickAddItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${meal.name} added to Quick Add!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Widget _buildMealThumbnail(Meal meal) {
    // First try imageBytes (available for newly scanned meals in memory)
    if (meal.imageBytes != null) {
      return Image.memory(
        meal.imageBytes!,
        fit: BoxFit.cover,
        width: 64,
        height: 64,
      );
    }
    
    // Then try imageUrl (available for meals loaded from Firestore)
    if (meal.imageUrl != null && meal.imageUrl!.isNotEmpty) {
      return Image.network(
        meal.imageUrl!,
        fit: BoxFit.cover,
        width: 64,
        height: 64,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryBlue,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.restaurant,
              color: AppTheme.textTertiary,
              size: 28,
            ),
          );
        },
      );
    }
    
    // Fallback: no image available
    return const Center(
      child: Icon(
        Icons.restaurant,
        color: AppTheme.textTertiary,
        size: 28,
      ),
    );
  }

  String _formatMealTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}, '
           '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
