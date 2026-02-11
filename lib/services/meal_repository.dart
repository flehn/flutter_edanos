import 'dart:convert';
import 'dart:typed_data';
import '../models/meal.dart';
import '../gemini_service.dart';
import 'firestore_service.dart';
import 'storage_service.dart';
import 'image_processor.dart';

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
  /// 
  /// Image is preprocessed (converted to JPEG, resized to 768px max) before analysis.
  static Future<Meal> analyzeImage(Uint8List imageBytes, {String? customPrompt}) async {
    // Preprocess: convert to JPEG and resize to 768px max
    final processedBytes = await ImageProcessor.preprocessImage(imageBytes);
    
    final resultJson = await GeminiService.analyzeImage(
      processedBytes,
      includeVitamins: false,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze image');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    return Meal.fromGeminiJson(data, imageBytes: processedBytes);
  }

  /// Analyze with comprehensive data (slower but includes vitamins/minerals)
  /// 
  /// Image is preprocessed (converted to JPEG, resized to 768px max) before analysis.
  static Future<Meal> analyzeImageComplete(Uint8List imageBytes, {String? customPrompt}) async {
    // Preprocess: convert to JPEG and resize to 768px max
    final processedBytes = await ImageProcessor.preprocessImage(imageBytes);
    
    final resultJson = await GeminiService.analyzeImage(
      processedBytes,
      includeVitamins: true,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze image');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    return Meal.fromGeminiJson(data, imageBytes: processedBytes);
  }

  /// Analyze multiple images (each image = one ingredient, combined into one dish)
  /// 
  /// All images are preprocessed (converted to JPEG, resized to 768px max) before analysis.
  static Future<Meal> analyzeMultipleImages(
    List<Uint8List> imageBytesList, {
    bool includeVitamins = false,
    String? customPrompt,
  }) async {
    // Preprocess all images
    final processedImages = await Future.wait(
      imageBytesList.map((bytes) => ImageProcessor.preprocessImage(bytes)),
    );
    
    final resultJson = await GeminiService.analyzeImages(
      processedImages,
      includeVitamins: includeVitamins,
      additionalPrompt: customPrompt,
    );

    if (resultJson == null) {
      throw Exception('Failed to analyze images');
    }

    final data = jsonDecode(resultJson) as Map<String, dynamic>;
    // Use the first image as the meal image
    return Meal.fromGeminiJson(data, imageBytes: processedImages.isNotEmpty ? processedImages.first : null);
  }

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

  /// Upload a no-food image in background (for analytics/debugging)
  /// 
  /// Call this when catching NotFoodException to still upload the image.
  /// This runs without waiting for completion (fire-and-forget).
  static void uploadNoFoodImageInBackground(Uint8List imageBytes, {String? classification}) {
    final id = 'nofood_${DateTime.now().microsecondsSinceEpoch}';
    // Fire and forget - don't await
    StorageService.storeImage(
      imageBytes, 
      id,
      classification: classification ?? 'no_food_no_label',
    ).catchError((e) {
      // Silently ignore upload errors for rejected images
      return '';
    });
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
