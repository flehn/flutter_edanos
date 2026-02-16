import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/meal.dart';
import '../services/meal_repository.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';
import '../gemini_service.dart';
import 'meal_detail_screen.dart';

/// Food Log Screen - Daily overview with weekly chart
class FoodLogScreen extends StatefulWidget {
  final VoidCallback? onAddFood;
  
  const FoodLogScreen({
    super.key,
    this.onAddFood,
  });

  @override
  FoodLogScreenState createState() => FoodLogScreenState();
}

class FoodLogScreenState extends State<FoodLogScreen> {
  // Pre-compiled regex for number formatting (thousands separator)
  static final _thousandsSepRegex = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

  /// Public method to refresh data (called when tab becomes active or after meal changes)
  void refresh() {
    _weekCache.clear(); // Clear all cache to ensure fresh data if changes happened in other tabs
    _refreshCurrentWeek();
  }

  /// Force refresh the current week's data (invalidates cache)
  /// Set clearEvaluation to true only when dishes are added/deleted
  /// If affectedDate is provided, also invalidates cache for that date's week
  Future<void> _refreshCurrentWeek({bool clearEvaluation = true, DateTime? affectedDate}) async {
    final weekKey = _getWeekKey(_selectedDate);
    _weekCache.remove(weekKey); // Invalidate cache for current week
    
    // If an affected date is provided and it's in a different week, invalidate that week too
    if (affectedDate != null) {
      final affectedWeekKey = _getWeekKey(affectedDate);
      if (affectedWeekKey != weekKey) {
        _weekCache.remove(affectedWeekKey);
      }
    }
    
    // Only clear AI evaluation when dishes are added/deleted
    if (clearEvaluation) {
      _skipEvaluationReload = true;
      setState(() {
        _dailyEvaluation = null;
        _isEvaluationExpanded = false;
      });
    }
    
    await _loadWeekDataForDate(_selectedDate);
    
    // Also load the affected week if it's different
    if (affectedDate != null) {
      final affectedWeekKey = _getWeekKey(affectedDate);
      if (affectedWeekKey != weekKey) {
        await _loadWeekDataForDate(affectedDate);
      }
    }
    
    await _loadMealsForSelectedDay();
  }
  DateTime? _firstMealDate;
  final ScrollController _chartScrollController = ScrollController();
  final Map<int, List<DailySummary>> _weekCache = {}; // Cache by week number (since epoch)
  
  List<Meal> _selectedDayMeals = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isChartReady = false;
  
  // Health data
  double _burnedCalories = 0;
  Map<DateTime, double> _weeklyBurnedCalories = {};

  // AI Daily Evaluation (parsed JSON with 'good' and 'critical' fields)
  Map<String, dynamic>? _dailyEvaluation;
  bool _isEvaluationLoading = false;
  bool _isEvaluationExpanded = false;
  UserSettings? _userSettings;
  
  // Flag to prevent duplicate health data loading
  bool _healthDataLoaded = false;
  
  // Flag to skip evaluation reload (after meals added/deleted)
  bool _skipEvaluationReload = false;

  // Week range overlay state (shown while user scrolls the chart)
  bool _showWeekRange = false;
  String _weekRangeText = '';
  Timer? _scrollEndTimer;

  @override
  void initState() {
    super.initState();
    _initializeHistory();
  }

  @override
  void dispose() {
    _scrollEndTimer?.cancel();
    _chartScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeHistory() async {
    // 1. Load today's data immediately
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    
    try {
      await _loadWeekDataForDate(_selectedDate);
      
      // 2. Fetch the start date of history
      final firstDate = await MealRepository.getFirstMealDate();
      
      // 3. Load health data ONCE on init
      await _loadHealthDataOnce();
      
      if (mounted) {
        setState(() {
          _firstMealDate = firstDate != null
              ? DateTime(firstDate.year, firstDate.month, firstDate.day)
              : DateTime(now.year, now.month, now.day);
          _isChartReady = true;
        });
        
        // Scroll to end (today) after frame build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chartScrollController.hasClients) {
            _chartScrollController.jumpTo(_chartScrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing history: $e');
      // Still mark chart as ready with default values to avoid infinite loading
      if (mounted) {
        setState(() {
          _firstMealDate = DateTime(now.year, now.month, now.day);
          _isChartReady = true;
        });
      }
    }
  }

  int _getWeekKey(DateTime date) {
    // Calculate week number since epoch to use as cache key
    // Using Monday as start of week
    final daysSinceEpoch = date.difference(DateTime(1970, 1, 1)).inDays;
    final mondayOffset = (DateTime(1970, 1, 1).weekday - 1);
    return ((daysSinceEpoch + mondayOffset) / 7).floor();
  }

  DateTime _getWeekStartFromKey(int weekKey) {
    // Reverse of _getWeekKey
    final mondayOffset = (DateTime(1970, 1, 1).weekday - 1);
    final daysSinceEpoch = (weekKey * 7) - mondayOffset;
    final weekStart = DateTime(1970, 1, 1).add(Duration(days: daysSinceEpoch));
    // Ensure the date is normalized to midnight to avoid timezone issues
    return DateTime(weekStart.year, weekStart.month, weekStart.day);
  }

  Future<void> _loadWeekDataForDate(DateTime date) async {
    final weekKey = _getWeekKey(date);
    
    // Return early if already loaded
    if (_weekCache.containsKey(weekKey)) {
      if (!_isLoading) return; // Only verify we're not stuck in loading state
    }

    // Only set loading if we don't have this week's data
    if (!_weekCache.containsKey(weekKey)) {
      setState(() => _isLoading = true);
    }
    
    try {
      final weekStart = _getWeekStartFromKey(weekKey);
      
      // Load weekly summaries
      final summaries = await MealRepository.getWeeklySummaries(weekStart);
      
      setState(() {
        _weekCache[weekKey] = summaries;
        _isLoading = false;
      });
      
      // If this is the currently selected week, refresh meal details only
      if (_getWeekKey(_selectedDate) == weekKey) {
        await _loadMealsForSelectedDay();
        // Health data is loaded separately in _loadHealthDataOnce()
      }
    } catch (e) {
      debugPrint('Error loading week data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Load health data only once when screen initializes
  Future<void> _loadHealthDataOnce() async {
    if (_healthDataLoaded) return;
    _healthDataLoaded = true;
    
    if (!HealthService.isAvailable) return;
    
    try {
      // Check if we have permissions
      final hasPerms = await HealthService.hasPermissions();
      if (!hasPerms) {
        _healthDataLoaded = false; // Allow retry if no permissions
        return;
      }
      
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      
      // Load burned calories for today
      final todayBurned = await HealthService.getBurnedCaloriesForDate(_selectedDate);
      
      // Load weekly burned calories
      final weeklyBurned = await HealthService.getWeeklyBurnedCalories(weekStart);
      
      if (mounted) {
        setState(() {
          _burnedCalories = todayBurned;
          _weeklyBurnedCalories = weeklyBurned;
        });
      }
      
      // Health data loaded successfully
    } catch (e) {
      debugPrint('Error loading health data once: $e');
      _healthDataLoaded = false; // Allow retry on error
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
      } else if (_healthDataLoaded && HealthService.isAvailable) {
        // Only fetch if health permissions were granted and data not in cache
        final burned = await HealthService.getBurnedCaloriesForDate(_selectedDate);
        setState(() => _burnedCalories = burned);
      }
      
      // Load saved evaluation for this day
      await _loadSavedEvaluation();
    } catch (e) {
      debugPrint('Error loading meals: $e');
    }
  }

  /// Load a previously saved evaluation for the selected date
  Future<void> _loadSavedEvaluation() async {
    // Skip reload if evaluation was deliberately cleared (meals changed)
    if (_skipEvaluationReload) {
      _skipEvaluationReload = false;
      return;
    }
    
    try {
      final saved = await MealRepository.getDailyEvaluation(_selectedDate);
      if (mounted) {
        setState(() {
          _dailyEvaluation = saved;
          _isEvaluationExpanded = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved evaluation: $e');
    }
  }

  void _onDaySelected(DateTime date) {
    // Immediately update selected date and show cached burned calories
    final dayKey = DateTime(date.year, date.month, date.day);
    final cachedBurned = _weeklyBurnedCalories[dayKey] ?? _burnedCalories;
    
    setState(() {
      _selectedDate = date;
      _burnedCalories = cachedBurned;
      // Reset evaluation state - will be loaded from Firestore in _loadMealsForSelectedDay
      _dailyEvaluation = null;
      _isEvaluationExpanded = false;
    });
    
    // Load meals for new day (this will also update burned calories if cache miss and load saved evaluation)
    _loadMealsForSelectedDay();
    
    // Only load week data if not cached (to avoid re-triggering meal loads)
    final weekKey = _getWeekKey(date);
    if (!_weekCache.containsKey(weekKey)) {
      _loadWeekDataForDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle loading state
    if (!_isChartReady) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }
    
    // Safely get selected day data
    final selectedDay = _getSummaryForDate(_selectedDate);
    
    final totalConsumed = selectedDay.totalCalories.round();
    final burned = _burnedCalories.round();
    final netCalories = totalConsumed - burned;



    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
         child: CustomScrollView(
           slivers: [
             // 1. Calories Summary
             SliverToBoxAdapter(
               child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
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
                      _buildCalorieBox('Consumed', totalConsumed, AppTheme.calorieOrange),
                      const SizedBox(width: 12),
                      _buildCalorieBox('Burned', burned, AppTheme.positiveColor),
                      const SizedBox(width: 12),
                      _buildCalorieBox(
                        'Net Calories',
                        netCalories,
                        netCalories < 0 ? AppTheme.negativeColor : AppTheme.positiveColor,
                      ),
                    ],
                  ),
               ),
             ),
             
             const SliverToBoxAdapter(child: SizedBox(height: 16)),

             // 2. Macros Summary
             SliverToBoxAdapter(
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 16),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     _buildMacroDot(AppTheme.proteinColor, 'Protein', selectedDay.totalProtein.round()),
                     const SizedBox(width: 24),
                     _buildMacroDot(AppTheme.carbsColor, 'Carbs', selectedDay.totalCarbs.round()),
                     const SizedBox(width: 24),
                     _buildMacroDot(AppTheme.fatColor, 'Fat', selectedDay.totalFat.round()),
                   ],
                 ),
               ),
             ),
             
              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // 3. Scrollable History Chart  
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 140,
                  child: Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollStartNotification &&
                              notification.dragDetails != null) {
                            _scrollEndTimer?.cancel();
                            _onChartScrollUpdate();
                          } else if (notification is ScrollUpdateNotification) {
                            if (_showWeekRange) _onChartScrollUpdate();
                          } else if (notification is ScrollEndNotification) {
                            // Fade out after scrolling stops
                            _scrollEndTimer?.cancel();
                            _scrollEndTimer = Timer(
                              const Duration(milliseconds: 800),
                              () {
                                if (mounted) {
                                  setState(() => _showWeekRange = false);
                                }
                              },
                            );
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _chartScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: _getTotalDays(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final date = _getDateForIndex(index);
                            // Defer data loading to avoid setState during build
                            final weekKey = _getWeekKey(date);
                            if (!_weekCache.containsKey(weekKey)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _loadWeekDataForDate(date);
                              });
                            }
                            final summary = _getSummaryForDate(date);
                            return _buildDayBarFromSummary(date, summary);
                          },
                        ),
                      ),
                      // Week range overlay (fades in while user scrolls)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 4,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _showWeekRange ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceDark.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppTheme.textTertiary.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _weekRangeText,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

             const SliverToBoxAdapter(child: SizedBox(height: 16)),

             // 4. Date Label with optional Today button
             SliverToBoxAdapter(
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 16),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Text(
                       _formatDateLabel(_selectedDate),
                       style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
                     ),
                     if (!_isToday()) ...[
                       const SizedBox(width: 12),
                       GestureDetector(
                         onTap: _jumpToToday,
                         child: Container(
                           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                           decoration: BoxDecoration(
                             color: AppTheme.primaryBlue,
                             borderRadius: BorderRadius.circular(12),
                           ),
                           child: const Text(
                             'Go to today',
                             style: TextStyle(
                               color: Colors.white,
                               fontSize: 11,
                               fontWeight: FontWeight.w600,
                             ),
                           ),
                         ),
                       ),
                     ],
                   ],
                 ),
               ),
             ),
             
             const SliverToBoxAdapter(child: SizedBox(height: 16)),

             // 5. AI Evaluation (Now scrollable part of the page)
             SliverToBoxAdapter(
               child: _buildDailyEvaluationSection(),
             ),
             
             // 6. Meals List (Using SliverList)
             _selectedDayMeals.isEmpty
                 ? SliverFillRemaining(
                     hasScrollBody: false,
                     child: Center(
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
                           const SizedBox(height: 24),
                           GestureDetector(
                             onTap: widget.onAddFood,
                             child: Container(
                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                               decoration: BoxDecoration(
                                 color: AppTheme.primaryBlue,
                                 borderRadius: BorderRadius.circular(12),
                               ),
                               child: const Text(
                                 'Scan a meal',
                                 style: TextStyle(
                                   color: Colors.white,
                                   fontSize: 14,
                                   fontWeight: FontWeight.w600,
                                 ),
                               ),
                             ),
                           ),
                         ],
                       ),
                     ),
                   )
                 : SliverList(
                     delegate: SliverChildBuilderDelegate(
                       (context, index) {
                         return Padding(
                           padding: const EdgeInsets.symmetric(horizontal: 16),
                           child: _buildMealCardFromMeal(_selectedDayMeals[index]),
                         );
                       },
                       childCount: _selectedDayMeals.length,
                     ),
                   ),
                   
              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
                    _thousandsSepRegex,
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
    final displayValue = value < 0 ? 0 : value;
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
          '$label $displayValue',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  /// Check if selected date is today
  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  /// Get total number of days from first meal to today (minimum 7 days for current week)
  int _getTotalDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Get start of current week (Monday)
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final start = _firstMealDate != null && _firstMealDate!.isBefore(weekStart)
        ? _firstMealDate!
        : weekStart;
    final days = today.difference(start).inDays + 1;
    return days < 7 ? 7 : days; // Minimum 7 days
  }

  /// Get date for a specific index in the chart (0 = oldest)
  DateTime _getDateForIndex(int index) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Get start of current week (Monday)
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final start = _firstMealDate != null && _firstMealDate!.isBefore(weekStart)
        ? _firstMealDate!
        : weekStart;
    return start.add(Duration(days: index));
  }

  /// Jump to today's date and scroll chart to end
  void _jumpToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _onDaySelected(today);
    
    // Scroll to end (today) after frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chartScrollController.hasClients) {
        _chartScrollController.jumpTo(_chartScrollController.position.maxScrollExtent);
      }
    });
  }

  bool _hasMinimumMeals() {
    return _selectedDayMeals.length >= 3;
  }

  /// Build the daily AI evaluation section
  Widget _buildDailyEvaluationSection() {
    final canEvaluate = _hasMinimumMeals();
    final hasMeals = _selectedDayMeals.isNotEmpty;
    final hasExistingEvaluation = _dailyEvaluation != null;

    // Build status message
    String statusMessage;
    if (hasExistingEvaluation) {
      statusMessage = 'Tap to ${_isEvaluationExpanded ? 'collapse' : 'expand'}';
    } else if (!hasMeals) {
      statusMessage = 'Log a meal to enable evaluation';
    } else if (!canEvaluate) {
      statusMessage = 'Log at least 3 meals to enable';
    } else {
      statusMessage = 'Ready to evaluate';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: hasExistingEvaluation
                ? () => setState(() => _isEvaluationExpanded = !_isEvaluationExpanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: canEvaluate || hasExistingEvaluation ? AppTheme.primaryBlue : AppTheme.textTertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily AI Evaluation',
                          style: TextStyle(
                            color: canEvaluate || hasExistingEvaluation ? AppTheme.textPrimary : AppTheme.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          statusMessage,
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasExistingEvaluation)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Re-evaluate button (only if enough meals)
                        if (canEvaluate && !_isEvaluationLoading)
                          GestureDetector(
                            onTap: _runDailyEvaluation,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.refresh,
                                color: AppTheme.primaryBlue,
                                size: 20,
                              ),
                            ),
                          ),
                        Icon(
                          _isEvaluationExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppTheme.textTertiary,
                        ),
                      ],
                    )
                  else if (_isEvaluationLoading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryBlue,
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: canEvaluate ? _runDailyEvaluation : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canEvaluate ? AppTheme.primaryBlue : AppTheme.textTertiary.withOpacity(0.3),
                        foregroundColor: canEvaluate ? Colors.white : AppTheme.textTertiary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Get Evaluation',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (hasExistingEvaluation && _isEvaluationExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppTheme.textTertiary),
                  const SizedBox(height: 12),
                  
                  // Good section
                  if (_dailyEvaluation!['good'] != null && 
                      _dailyEvaluation!['good'].toString().isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, color: AppTheme.positiveColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dailyEvaluation!['good'],
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Critical section
                  if (_dailyEvaluation!['critical'] != null && 
                      _dailyEvaluation!['critical'].toString().isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber, color: AppTheme.warningColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dailyEvaluation!['critical'],
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Processed food feedback section
                  if (_dailyEvaluation!['processedFoodFeedback'] != null && 
                      _dailyEvaluation!['processedFoodFeedback'].toString().isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _getProcessedFoodIcon(),
                          color: _getProcessedFoodColor(),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dailyEvaluation!['processedFoodFeedback'],
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Consumed vs Recommended comparison
                  const SizedBox(height: 8),
                  _buildNutrientComparison(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Get icon for processed food feedback based on stored counts
  IconData _getProcessedFoodIcon() {
    final processedCount = _dailyEvaluation?['processedMealCount'] as int? ?? 0;
    if (processedCount == 0) return Icons.eco;
    final totalCount = _dailyEvaluation?['totalMealCount'] as int? ?? 1;
    if (totalCount > 0 && processedCount / totalCount > 0.5) return Icons.warning_amber;
    return Icons.info_outline;
  }

  /// Get color for processed food feedback based on stored counts
  Color _getProcessedFoodColor() {
    final processedCount = _dailyEvaluation?['processedMealCount'] as int? ?? 0;
    if (processedCount == 0) return AppTheme.positiveColor;
    final totalCount = _dailyEvaluation?['totalMealCount'] as int? ?? 1;
    if (totalCount > 0 && processedCount / totalCount > 0.5) return AppTheme.warningColor;
    return AppTheme.primaryBlue;
  }

  /// Run the daily AI evaluation
  Future<void> _runDailyEvaluation() async {
    if (_isEvaluationLoading) return;

    setState(() => _isEvaluationLoading = true);

    try {
      // Load user settings if not already loaded
      _userSettings ??= await MealRepository.getUserSettings();
      final settings = _userSettings!;

      // Get selected day's summary
      final selectedDay = _getSummaryForDate(_selectedDate);

      // Determine user goal
      final goals = await MealRepository.getUserGoals();
      final goalDescription = goals.isGainMode ? 'gain weight/muscle' : 'lose weight/maintain';

      // Count processed foods
      final totalMealCount = _selectedDayMeals.length;
      final processedMealCount = _selectedDayMeals
          .where((meal) => meal.isHighlyProcessed == true)
          .length;

      // Build meals list with ingredients and processed status
      final mealDescriptions = _selectedDayMeals.map((meal) {
        final ingredients = meal.ingredients.map((i) => i.name).join(', ');
        final processedTag = meal.isHighlyProcessed == true ? ' [PROCESSED]' : '';
        return '${meal.name}$processedTag: $ingredients';
      }).toList();

      // Call evaluation
      final evaluation = await GeminiService.evaluateDailyHealth(
        gender: settings.gender,
        age: settings.age,
        weightKg: settings.weight,
        goal: goalDescription,
        burnedCalories: _burnedCalories,
        totalCalories: selectedDay.totalCalories,
        totalProtein: selectedDay.totalProtein,
        totalCarbs: selectedDay.totalCarbs,
        totalFat: selectedDay.totalFat,
        totalFiber: selectedDay.totalFiber,
        totalSugar: selectedDay.totalSugar,
        meals: mealDescriptions,
        totalMealCount: totalMealCount,
        processedMealCount: processedMealCount,
      );

      if (mounted && evaluation != null) {
        // Parse JSON response
        Map<String, dynamic> evaluationData;
        try {
          evaluationData = jsonDecode(evaluation) as Map<String, dynamic>;
        } catch (parseError) {
          debugPrint('JSON parse error: $parseError');
          // Fallback: wrap raw response
          evaluationData = {
            'good': evaluation,
            'critical': '',
            'processedFoodFeedback': '',
          };
        }
        
        // Add processed food counts to the evaluation data for persistence
        evaluationData['totalMealCount'] = totalMealCount;
        evaluationData['processedMealCount'] = processedMealCount;
        
        setState(() {
          _dailyEvaluation = evaluationData;
          _isEvaluationExpanded = true;
          _isEvaluationLoading = false;
        });
        
        // Save to Firestore (overwrites any existing evaluation for this date)
        // Done separately so a save error doesn't affect the display
        try {
          await MealRepository.saveDailyEvaluation(_selectedDate, evaluationData);
        } catch (saveError) {
          debugPrint('Failed to save evaluation to Firestore: $saveError');
        }
      }
    } catch (e) {
      debugPrint('Error running daily evaluation: $e');
      if (mounted) {
        setState(() => _isEvaluationLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get evaluation: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  String _formatDateLabel(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return 'Scanned on ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  /// Build nutrient comparison showing consumed vs recommended values
  Widget _buildNutrientComparison() {
    final selectedDay = _getSummaryForDate(_selectedDate);
    final gender = _userSettings?.gender ?? 'male';
    final weightKg = _userSettings?.weight ?? 70.0;

    // Get consumed values
    final sugar = selectedDay.totalSugar;
    final fiber = selectedDay.totalFiber;
    final saturatedFat = selectedDay.totalSaturatedFat;
    final protein = selectedDay.totalProtein;
    final calories = selectedDay.totalCalories;

    // Calculate recommendations based on gender/weight
    final maxSugar = gender == 'female' ? 22.0 : 37.0;
    final minFiber = gender == 'female' ? 25.0 : 30.0;
    final maxSaturatedFatPercent = 10.0; // 10% of total calories
    final maxSaturatedFat = (calories * maxSaturatedFatPercent / 100) / 9; // Convert to grams
    final minProtein = weightKg * 0.8; // 0.8g per kg body weight
    final saturatedFatPercent = calories > 0 ? (saturatedFat * 9 / calories * 100) : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consumed vs Recommended',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _buildNutrientRow('Sugar', sugar, maxSugar, 'g', isMax: true),
          _buildNutrientRow('Fiber', fiber, minFiber, 'g', isMax: false),
          _buildNutrientRow('Sat. Fat', saturatedFat, maxSaturatedFat, 'g (${saturatedFatPercent.toStringAsFixed(0)}%)', isMax: true),
          _buildNutrientRow('Protein', protein, minProtein, 'g', isMax: false),
        ],
      ),
    );
  }

  /// Build a single nutrient comparison row
  Widget _buildNutrientRow(String label, double consumed, double target, String unit, {required bool isMax}) {
    final isOk = isMax ? consumed <= target : consumed >= target;
    final displayColor = isOk ? AppTheme.positiveColor : AppTheme.warningColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              '${consumed.toStringAsFixed(0)}$unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: displayColor,
              ),
            ),
          ),
          Text(
            '${isMax ? '≤' : '≥'} ${target.toStringAsFixed(0)}$unit',
            style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  String _getDayName(int index) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[index];
  }

  /// Update the week range overlay based on current scroll position
  void _onChartScrollUpdate() {
    if (!_chartScrollController.hasClients) return;

    final offset = _chartScrollController.offset;
    final viewportWidth = _chartScrollController.position.viewportDimension;
    const itemWidth = 52.0; // 48 width + 4 margin

    final centerOffset = offset + viewportWidth / 2;
    final centerIndex =
        (centerOffset / itemWidth).floor().clamp(0, _getTotalDays() - 1);

    final centerDate = _getDateForIndex(centerIndex);

    // Get Monday and Sunday of that week
    final monday = centerDate.subtract(Duration(days: centerDate.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final rangeText =
        '${_formatShortDate(monday)} - ${_formatShortDate(sunday)}';

    if (_weekRangeText != rangeText || !_showWeekRange) {
      setState(() {
        _weekRangeText = rangeText;
        _showWeekRange = true;
      });
    }
  }

  /// Format date as DD.MM.YY
  String _formatShortDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = (date.year % 100).toString().padLeft(2, '0');
    return '$d.$m.$y';
  }

  DailySummary _getSummaryForDate(DateTime date) {
    // Check if we have this week loaded
    final weekKey = _getWeekKey(date);
    final weekSummaries = _weekCache[weekKey];
    
    if (weekSummaries == null) {
      return DailySummary.empty(date);
    }
    
    // Find the summary for this specific date
    return weekSummaries.firstWhere(
      (s) => s.date.day == date.day && s.date.month == date.month && s.date.year == date.year,
      orElse: () => DailySummary.empty(date),
    );
  }

  Widget _buildDayBarFromSummary(DateTime date, DailySummary day) {
    final isSelected = date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
            
    final calories = day.totalCalories.round();
    final protein = day.totalProtein.round();
    final carbs = day.totalCarbs.round();
    final fat = day.totalFat.round();
    
    const double maxCalories = 2500;
    
    final barHeight = (calories / maxCalories) * 80;

    return GestureDetector(
      onTap: () => _onDaySelected(date),
      child: Container(
        width: 48, // Fixed width for scrollable list - fits 4-digit calories
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
          // Stacked bar or three dots for empty days
          if (calories > 0)
            Container(
              width: 28,
              height: barHeight.clamp(10.0, 80.0),
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
            _getDayName(date.weekday - 1), // 0-based index for Mon-Sun
            style: TextStyle(
              fontSize: 10,
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
                      _thousandsSepRegex,
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
            _refreshCurrentWeek(affectedDate: result.scannedAt);
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
    final deletedMealDate = meal.scannedAt; // Store the date for cache invalidation
    
    debugPrint('🗑️ Attempting to delete meal: $mealId (${meal.name})');
    
    // Immediately remove from local state to satisfy Dismissible requirement
    setState(() {
      _selectedDayMeals.removeWhere((m) => m.id == meal.id);
      
      // Also update the week data locally to reflect the deletion in charts
      
      // Update cache logic would go here. For now, trusting the reload or eventual consistency.
      // We removed the old _weekData update logic since _weekData no longer exists.
    });
    
    try {
      debugPrint('🗑️ Calling MealRepository.deleteMeal for: $mealId');
      await MealRepository.deleteMeal(mealId);
      debugPrint('✅ Successfully deleted meal from Firebase: $mealId');
      
      // Invalidate cache for the week containing the deleted meal
      _refreshCurrentWeek(affectedDate: deletedMealDate, clearEvaluation: true);
      
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
          
          // No need to restore week data summary manually as we didn't optimistic update it.
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

  Widget _buildMealThumbnail(Meal meal) {
    // Cache dimensions for thumbnails (2x for retina displays)
    const int cacheSize = 128; // 64px * 2 for high-DPI

    // First try imageBytes (available for newly scanned meals in memory)
    if (meal.imageBytes != null) {
      return Image.memory(
        meal.imageBytes!,
        fit: BoxFit.cover,
        width: 64,
        height: 64,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
      );
    }
    
    // Then try imageUrl (available for meals loaded from Firestore)
    if (meal.imageUrl != null && meal.imageUrl!.isNotEmpty) {
      return Image.network(
        meal.imageUrl!,
        fit: BoxFit.cover,
        width: 64,
        height: 64,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
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
