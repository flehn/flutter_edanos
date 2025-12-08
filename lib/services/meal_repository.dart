import 'dart:convert';
import 'dart:typed_data';
import '../models/meal.dart';
import '../gemini_service.dart';
import 'firestore_service.dart';
import 'storage_service.dart';

// Re-export FirestoreService types for convenience
export 'firestore_service.dart' show DailySummary, QuickAddItem, UserGoals, UserSettings;

/// Repository that combines Gemini analysis with Firestore persistence.
/// 
/// Single entry point for:
/// - Analyzing food images with Gemini
/// - Saving/loading meals to Firestore
/// - Managing daily summaries and user goals
class MealRepository {
  
  // ============================================
  // ANALYZE & CREATE MEAL
  // ============================================

  /// Analyze an image and create a Meal object (fast essential analysis - macros only)
  static Future<Meal> analyzeImage(Uint8List imageBytes, {String? customPrompt}) async {
    final resultJson = await GeminiService.analyzeImage(
      imageBytes,
      includeVitamins: false,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze image');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    return Meal.fromGeminiJson(data, imageBytes: imageBytes);
  }

  /// Analyze with comprehensive data (slower but includes vitamins/minerals)
  static Future<Meal> analyzeImageComplete(Uint8List imageBytes, {String? customPrompt}) async {
    final resultJson = await GeminiService.analyzeImage(
      imageBytes,
      includeVitamins: true,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze image');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    return Meal.fromGeminiJson(data, imageBytes: imageBytes);
  }

  /// Analyze multiple images (each image = one ingredient, combined into one dish)
  static Future<Meal> analyzeMultipleImages(
    List<Uint8List> imageBytesList, {
    bool includeVitamins = false,
    String? customPrompt,
  }) async {
    final resultJson = await GeminiService.analyzeImages(
      imageBytesList,
      includeVitamins: includeVitamins,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze images');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    // Use the first image as the meal image
    return Meal.fromGeminiJson(data, imageBytes: imageBytesList.isNotEmpty ? imageBytesList.first : null);
  }

  // ============================================
  // MEAL CRUD
  // ============================================

  /// Save a new meal to Firestore (uploads image to Storage first)
  static Future<String> saveMeal(Meal meal) async {
    if (meal.imageBytes != null) {
      meal.imageUrl = await StorageService.storeImage(meal.imageBytes!, meal.id);
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

  /// Stream meals for today (real-time updates)
  static Stream<List<Meal>> streamTodayMeals() {
    return FirestoreService.streamMealsForToday();
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
}
