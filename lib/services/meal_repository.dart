import '../models/meal.dart';
import 'firestore_service.dart';
import 'storage_service.dart';

// Re-export FirestoreService types for convenience
export 'firestore_service.dart' show DailySummary, QuickAddItem, UserGoals, UserSettings;

/// Repository that combines Firestore persistence with Storage.
/// 
/// Single entry point for:
/// - Saving/loading meals to Firestore
/// - Managing daily summaries and user goals
class MealRepository {
  
  // ============================================
  // MEAL CRUD
  // ============================================

  /// Save a new meal to Firestore (uploads image to Storage first)
  static Future<String> saveMeal(Meal meal) async {
    if (meal.imageBytes != null) {
      meal.imageUrl = await StorageService.storeImage(
        meal.imageBytes!, 
        meal.id, 
        classification: meal.imageClassification,
      );
    }
    return await FirestoreService.saveMeal(meal);
  }

  /// Update an existing meal
  static Future<void> updateMeal(String mealId, Meal meal) async {
    await FirestoreService.updateMeal(mealId, meal);
  }

  /// Delete a meal and its image
  static Future<void> deleteMeal(String mealId) async {
    // Delete from Firestore first (most important)
    await FirestoreService.deleteMeal(mealId);
    
    // Then delete image from storage (can fail silently if image doesn't exist)
    await StorageService.deleteImage(mealId);
  }

  // ============================================
  // MEAL QUERIES
  // ============================================

  /// Get meals for a specific date
  static Future<List<Meal>> getMealsForDate(DateTime date) async {
    return FirestoreService.getMealsForDate(date);
  }

  // ============================================
  // DAILY SUMMARIES
  // ============================================

  /// Get today's summary
  static Future<DailySummary> getTodaySummary() async {
    return FirestoreService.getDailySummary(DateTime.now());
  }

  /// Get weekly summaries (optimized: single query)
  static Future<List<DailySummary>> getWeeklySummaries(DateTime weekStart) async {
    return FirestoreService.getWeeklySummaries(weekStart);
  }

  /// Get the date of the first logged meal
  static Future<DateTime?> getFirstMealDate() async {
    return FirestoreService.getFirstMealDate();
  }

  // ============================================
  // QUICK ADD
  // ============================================

  /// Get quick add items
  static Future<List<QuickAddItem>> getQuickAddItems() async {
    return FirestoreService.getQuickAddItems();
  }

  /// Save a quick add item
  static Future<void> saveQuickAddItem(QuickAddItem item) async {
    await FirestoreService.saveQuickAddItem(item);
  }

  /// Add meal from quick add (increments usage, saves meal)
  static Future<Meal> addMealFromQuickAdd(QuickAddItem quickAdd) async {
    await FirestoreService.incrementQuickAddUsage(quickAdd.id);
    final meal = quickAdd.toMeal();
    await saveMeal(meal);
    return meal;
  }

  /// Convert meal to quick add item
  static QuickAddItem mealToQuickAdd(Meal meal) {
    return QuickAddItem(
      id: meal.id,
      name: meal.name,
      calories: meal.totalCalories,
      protein: meal.totalProtein,
      carbs: meal.totalCarbs,
      fat: meal.totalFat,
      imageUrl: meal.imageUrl,
    );
  }

  // ============================================
  // USER GOALS
  // ============================================

  /// Get user goals
  static Future<UserGoals> getUserGoals() async {
    return FirestoreService.getUserGoals();
  }

  /// Save user goals
  static Future<void> saveUserGoals(UserGoals goals) async {
    await FirestoreService.saveUserGoals(goals);
  }

  // ============================================
  // USER SETTINGS
  // ============================================

  /// Get user settings
  static Future<UserSettings> getUserSettings() async {
    return FirestoreService.getUserSettings();
  }

  /// Save user settings
  static Future<void> saveUserSettings(UserSettings settings) async {
    await FirestoreService.saveUserSettings(settings);
  }

  // ============================================
  // DAILY EVALUATIONS
  // ============================================

  /// Save a daily AI evaluation (overwrites if already exists for that date)
  static Future<void> saveDailyEvaluation(DateTime date, Map<String, dynamic> evaluation) async {
    await FirestoreService.saveDailyEvaluation(date, evaluation);
  }

  /// Get a saved daily evaluation for a specific date
  static Future<Map<String, dynamic>?> getDailyEvaluation(DateTime date) async {
    return FirestoreService.getDailyEvaluation(date);
  }

  // ============================================
  // DATA MANAGEMENT
  // ============================================

  /// Clear all user data (meals, quick add items, settings)
  static Future<void> clearAllData() async {
    await FirestoreService.deleteAllUserData();
  }

  /// Export all meals as CSV
  static Future<String> exportMealsAsCSV() async {
    final meals = await FirestoreService.getAllMeals();
    
    final buffer = StringBuffer();
    // CSV header
    buffer.writeln('Date,Time,Name,Calories,Protein (g),Carbs (g),Fat (g),Fiber (g),Sugar (g)');
    
    for (final meal in meals) {
      final date = '${meal.scannedAt.year}-${meal.scannedAt.month.toString().padLeft(2, '0')}-${meal.scannedAt.day.toString().padLeft(2, '0')}';
      final time = '${meal.scannedAt.hour.toString().padLeft(2, '0')}:${meal.scannedAt.minute.toString().padLeft(2, '0')}';
      // Escape commas and quotes in name
      final name = meal.name.replaceAll('"', '""');
      buffer.writeln(
        '$date,$time,"$name",${meal.totalCalories.round()},${meal.totalProtein.round()},${meal.totalCarbs.round()},${meal.totalFat.round()},${meal.totalFiber.round()},${meal.totalSugar.round()}'
      );
    }
    
    return buffer.toString();
  }
}
