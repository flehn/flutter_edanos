import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meal.dart';
import '../models/ingredient.dart';

/// Firestore service for persisting meals and user data.
///
/// Data is stored per-user in: users/{userId}/...
/// Works with both anonymous and authenticated users.
/// When an anonymous user links to an email account, their UID stays the same,
/// so all their data is automatically preserved.
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user ID (guaranteed after AuthService.ensureSignedIn)
  static String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception(
        'User not authenticated. Call AuthService.ensureSignedIn() first.',
      );
    }
    return user.uid;
  }

  /// Reference to user's meals collection
  static CollectionReference<Map<String, dynamic>> get _mealsRef {
    return _db.collection('users').doc(_userId).collection('meals');
  }

  // ============================================
  // MEAL OPERATIONS
  // ============================================

  /// Save a new meal to Firestore
  /// Uses the meal's internal ID as the Firestore document ID for consistency
  static Future<String> saveMeal(Meal meal) async {
    // Note: Image bytes should be saved to Firebase Storage separately
    // and the URL stored in the meal document
    // Use the meal's internal ID as document ID so updates work correctly
    await _mealsRef.doc(meal.id).set(meal.toFirestore());
    return meal.id;
  }

  /// Update an existing meal
  /// Handles both new meals (doc ID = internal ID) and legacy meals (random doc ID)
  static Future<void> updateMeal(String mealId, Meal meal) async {
    // First try direct update (for new meals where doc ID = internal ID)
    final docRef = _mealsRef.doc(mealId);
    final docSnapshot = await docRef.get();
    
    if (docSnapshot.exists) {
      await docRef.update(meal.toFirestore());
      return;
    }
    
    // For legacy meals, find by internal ID field
    final querySnapshot = await _mealsRef
        .where('id', isEqualTo: mealId)
        .limit(1)
        .get();
    
    if (querySnapshot.docs.isNotEmpty) {
      final actualDocId = querySnapshot.docs.first.id;
      await _mealsRef.doc(actualDocId).update(meal.toFirestore());
    } else {
      // Document doesn't exist, create it with the correct ID
      await _mealsRef.doc(mealId).set(meal.toFirestore());
    }
  }

  /// Delete a meal
  /// Handles both new meals (doc ID = internal ID) and legacy meals (random doc ID)
  static Future<void> deleteMeal(String mealId) async {
    // First try direct delete (for new meals where doc ID = internal ID)
    final docRef = _mealsRef.doc(mealId);
    final docSnapshot = await docRef.get();
    
    if (docSnapshot.exists) {
      await docRef.delete();
      return;
    }
    
    // For legacy meals, find by internal ID field and delete all matches
    final querySnapshot = await _mealsRef
        .where('id', isEqualTo: mealId)
        .get();
    
    if (querySnapshot.docs.isNotEmpty) {
      // Delete all documents with this internal ID (handles duplicates)
      final batch = _db.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Get a single meal by ID
  static Future<Meal?> getMeal(String mealId) async {
    final doc = await _mealsRef.doc(mealId).get();
    if (!doc.exists) return null;
    return Meal.fromFirestore(doc.data()!);
  }

  /// Get all meals for a specific date
  static Future<List<Meal>> getMealsForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _mealsRef
        .where(
          'scannedAt',
          isGreaterThanOrEqualTo: startOfDay.toIso8601String(),
        )
        .where('scannedAt', isLessThan: endOfDay.toIso8601String())
        .orderBy('scannedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => Meal.fromFirestore(doc.data())).toList();
  }

  /// Get meals for a date range (e.g., a week)
  static Future<List<Meal>> getMealsForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final snapshot = await _mealsRef
        .where('scannedAt', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('scannedAt', isLessThan: end.toIso8601String())
        .orderBy('scannedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => Meal.fromFirestore(doc.data())).toList();
  }

  /// Stream of meals for today (real-time updates)
  static Stream<List<Meal>> streamMealsForToday() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _mealsRef
        .where(
          'scannedAt',
          isGreaterThanOrEqualTo: startOfDay.toIso8601String(),
        )
        .where('scannedAt', isLessThan: endOfDay.toIso8601String())
        .orderBy('scannedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Meal.fromFirestore(doc.data()))
              .toList(),
        );
  }

  /// Stream of all meals (real-time updates)
  static Stream<List<Meal>> streamAllMeals({int limit = 50}) {
    return _mealsRef
        .orderBy('scannedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Meal.fromFirestore(doc.data()))
              .toList(),
        );
  }

  // ============================================
  // DAILY SUMMARY
  // ============================================

  /// Get daily summary (totals for a specific date)
  static Future<DailySummary> getDailySummary(DateTime date) async {
    final meals = await getMealsForDate(date);
    return DailySummary.fromMeals(meals, date);
  }

  /// Get weekly summaries - OPTIMIZED: single query for entire week
  static Future<List<DailySummary>> getWeeklySummaries(
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Single query for all meals in the week
    final allMeals = await getMealsForDateRange(weekStart, weekEnd);

    // Group meals by day
    final mealsByDay = <int, List<Meal>>{};
    for (final meal in allMeals) {
      final dayIndex = meal.scannedAt.difference(weekStart).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        mealsByDay.putIfAbsent(dayIndex, () => []).add(meal);
      }
    }

    // Create summaries for each day
    final summaries = <DailySummary>[];
    for (var i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dayMeals = mealsByDay[i] ?? [];
      summaries.add(DailySummary.fromMeals(dayMeals, date));
    }

    return summaries;
  }

  // ============================================
  // USER GOALS & SETTINGS
  // ============================================

  /// Reference to user's goals document
  static DocumentReference<Map<String, dynamic>> get _goalsRef {
    return _db.collection('users').doc(_userId).collection('settings').doc('goals');
  }

  /// Reference to user's settings document
  static DocumentReference<Map<String, dynamic>> get _settingsRef {
    return _db.collection('users').doc(_userId).collection('settings').doc('preferences');
  }

  /// Get user goals from settings collection
  static Future<UserGoals> getUserGoals() async {
    final doc = await _goalsRef.get();
    if (!doc.exists || doc.data() == null) {
      return UserGoals.defaults();
    }
    return UserGoals.fromFirestore(doc.data()!);
  }

  /// Save user goals to settings collection
  static Future<void> saveUserGoals(UserGoals goals) async {
    await _goalsRef.set(goals.toFirestore());
  }

  /// Get user settings (preferences)
  static Future<UserSettings> getUserSettings() async {
    final doc = await _settingsRef.get();
    if (!doc.exists || doc.data() == null) {
      return UserSettings.defaults();
    }
    return UserSettings.fromFirestore(doc.data()!);
  }

  /// Save user settings (preferences)
  static Future<void> saveUserSettings(UserSettings settings) async {
    await _settingsRef.set(settings.toFirestore());
  }

  // ============================================
  // QUICK ADD ITEMS
  // ============================================

  /// Get user's quick add items
  static Future<List<QuickAddItem>> getQuickAddItems() async {
    final snapshot = await _db
        .collection('users')
        .doc(_userId)
        .collection('quickAdd')
        .orderBy('usageCount', descending: true)
        .limit(10)
        .get();

    return snapshot.docs
        .map((doc) => QuickAddItem.fromFirestore(doc.data()))
        .toList();
  }

  /// Save/update a quick add item
  static Future<void> saveQuickAddItem(QuickAddItem item) async {
    await _db
        .collection('users')
        .doc(_userId)
        .collection('quickAdd')
        .doc(item.id)
        .set(item.toFirestore(), SetOptions(merge: true));
  }

  /// Increment usage count for a quick add item
  static Future<void> incrementQuickAddUsage(String itemId) async {
    await _db
        .collection('users')
        .doc(_userId)
        .collection('quickAdd')
        .doc(itemId)
        .update({'usageCount': FieldValue.increment(1)});
  }
}

// ============================================
// SUPPORTING DATA CLASSES
// ============================================

/// Daily summary with totals
class DailySummary {
  final DateTime date;
  final int mealCount;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final double totalFiber;
  final double totalSugar;

  DailySummary({
    required this.date,
    required this.mealCount,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.totalFiber,
    required this.totalSugar,
  });

  factory DailySummary.fromMeals(List<Meal> meals, DateTime date) {
    return DailySummary(
      date: date,
      mealCount: meals.length,
      totalCalories: meals.fold(0, (sum, meal) => sum + meal.totalCalories),
      totalProtein: meals.fold(0, (sum, meal) => sum + meal.totalProtein),
      totalCarbs: meals.fold(0, (sum, meal) => sum + meal.totalCarbs),
      totalFat: meals.fold(0, (sum, meal) => sum + meal.totalFat),
      totalFiber: meals.fold(0, (sum, meal) => sum + meal.totalFiber),
      totalSugar: meals.fold(0, (sum, meal) => sum + meal.totalSugar),
    );
  }

  /// Empty summary for days with no meals
  factory DailySummary.empty(DateTime date) {
    return DailySummary(
      date: date,
      mealCount: 0,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbs: 0,
      totalFat: 0,
      totalFiber: 0,
      totalSugar: 0,
    );
  }
}

/// User's nutrition goals
class UserGoals {
  final int dailyCalories;
  final int dailyProtein;
  final int dailyCarbs;
  final int dailyFat;
  final int dailyFiber;
  final bool isGainMode; // true = gain weight, false = lose weight
  final int perMealProtein;
  final int perMealCarbs;
  final int perMealFat;

  UserGoals({
    required this.dailyCalories,
    required this.dailyProtein,
    required this.dailyCarbs,
    required this.dailyFat,
    required this.dailyFiber,
    this.isGainMode = false,
    required this.perMealProtein,
    required this.perMealCarbs,
    required this.perMealFat,
  });

  factory UserGoals.defaults() {
    return UserGoals(
      dailyCalories: 2000,
      dailyProtein: 150,
      dailyCarbs: 250,
      dailyFat: 67,
      dailyFiber: 30,
      isGainMode: false,
      perMealProtein: 40,
      perMealCarbs: 40,
      perMealFat: 20,
    );
  }

  factory UserGoals.fromFirestore(Map<String, dynamic> data) {
    return UserGoals(
      dailyCalories: data['dailyCalories'] ?? 2000,
      dailyProtein: data['dailyProtein'] ?? 150,
      dailyCarbs: data['dailyCarbs'] ?? 250,
      dailyFat: data['dailyFat'] ?? 67,
      dailyFiber: data['dailyFiber'] ?? 30,
      isGainMode: data['isGainMode'] ?? false,
      perMealProtein: data['perMealProtein'] ?? 40,
      perMealCarbs: data['perMealCarbs'] ?? 40,
      perMealFat: data['perMealFat'] ?? 20,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dailyCalories': dailyCalories,
      'dailyProtein': dailyProtein,
      'dailyCarbs': dailyCarbs,
      'dailyFat': dailyFat,
      'dailyFiber': dailyFiber,
      'isGainMode': isGainMode,
      'perMealProtein': perMealProtein,
      'perMealCarbs': perMealCarbs,
      'perMealFat': perMealFat,
    };
  }
  
  /// Create a copy with updated values
  UserGoals copyWith({
    int? dailyCalories,
    int? dailyProtein,
    int? dailyCarbs,
    int? dailyFat,
    int? dailyFiber,
    bool? isGainMode,
    int? perMealProtein,
    int? perMealCarbs,
    int? perMealFat,
  }) {
    return UserGoals(
      dailyCalories: dailyCalories ?? this.dailyCalories,
      dailyProtein: dailyProtein ?? this.dailyProtein,
      dailyCarbs: dailyCarbs ?? this.dailyCarbs,
      dailyFat: dailyFat ?? this.dailyFat,
      dailyFiber: dailyFiber ?? this.dailyFiber,
      isGainMode: isGainMode ?? this.isGainMode,
      perMealProtein: perMealProtein ?? this.perMealProtein,
      perMealCarbs: perMealCarbs ?? this.perMealCarbs,
      perMealFat: perMealFat ?? this.perMealFat,
    );
  }
}

/// Quick add item for frequently logged foods
class QuickAddItem {
  final String id;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int usageCount;
  final String? imageUrl;

  QuickAddItem({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.usageCount = 0,
    this.imageUrl,
  });

  factory QuickAddItem.fromFirestore(Map<String, dynamic> data) {
    return QuickAddItem(
      id: data['id'],
      name: data['name'],
      calories: (data['calories'] as num).toDouble(),
      protein: (data['protein'] as num).toDouble(),
      carbs: (data['carbs'] as num).toDouble(),
      fat: (data['fat'] as num).toDouble(),
      usageCount: data['usageCount'] ?? 0,
      imageUrl: data['imageUrl'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'usageCount': usageCount,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  /// Create a Meal from this quick add item
  Meal toMeal() {
    return Meal(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      scannedAt: DateTime.now(),
      ingredients: [
        Ingredient(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          amount: 1,
          originalAmount: 1,
          unit: 'serving',
          originalCalories: calories,
          originalProtein: protein,
          originalCarbs: carbs,
          originalFat: fat,
        ),
      ],
    );
  }
}

/// User's app settings/preferences
class UserSettings {
  final bool notificationsEnabled;
  final bool mealRemindersEnabled;
  final bool useDetailedAnalysis;
  final bool syncToHealth;
  final String units; // 'Metric' or 'Imperial'
  final List<int> reminderTimesMinutes; // Minutes from midnight for each reminder
  final DateTime? lastUpdated;

  UserSettings({
    required this.notificationsEnabled,
    required this.mealRemindersEnabled,
    required this.useDetailedAnalysis,
    required this.syncToHealth,
    required this.units,
    required this.reminderTimesMinutes,
    this.lastUpdated,
  });

  factory UserSettings.defaults() {
    return UserSettings(
      notificationsEnabled: true,
      mealRemindersEnabled: true,
      useDetailedAnalysis: false,
      syncToHealth: false,
      units: 'Metric',
      reminderTimesMinutes: [480, 750, 1110], // 8:00, 12:30, 18:30 in minutes
      lastUpdated: DateTime.now(),
    );
  }

  factory UserSettings.fromFirestore(Map<String, dynamic> data) {
    return UserSettings(
      notificationsEnabled: data['notificationsEnabled'] ?? true,
      mealRemindersEnabled: data['mealRemindersEnabled'] ?? true,
      useDetailedAnalysis: data['useDetailedAnalysis'] ?? false,
      syncToHealth: data['syncToHealth'] ?? false,
      units: data['units'] ?? 'Metric',
      reminderTimesMinutes: (data['reminderTimesMinutes'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [480, 750, 1110],
      lastUpdated: data['lastUpdated'] != null
          ? DateTime.parse(data['lastUpdated'] as String)
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'notificationsEnabled': notificationsEnabled,
      'mealRemindersEnabled': mealRemindersEnabled,
      'useDetailedAnalysis': useDetailedAnalysis,
      'syncToHealth': syncToHealth,
      'units': units,
      'reminderTimesMinutes': reminderTimesMinutes,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }

  UserSettings copyWith({
    bool? notificationsEnabled,
    bool? mealRemindersEnabled,
    bool? useDetailedAnalysis,
    bool? syncToHealth,
    String? units,
    List<int>? reminderTimesMinutes,
  }) {
    return UserSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      mealRemindersEnabled: mealRemindersEnabled ?? this.mealRemindersEnabled,
      useDetailedAnalysis: useDetailedAnalysis ?? this.useDetailedAnalysis,
      syncToHealth: syncToHealth ?? this.syncToHealth,
      units: units ?? this.units,
      reminderTimesMinutes: reminderTimesMinutes ?? this.reminderTimesMinutes,
      lastUpdated: DateTime.now(),
    );
  }

  /// Convert reminder times from minutes to TimeOfDay list
  List<Map<String, int>> get reminderTimesAsTimeOfDay {
    return reminderTimesMinutes.map((minutes) {
      return {
        'hour': minutes ~/ 60,
        'minute': minutes % 60,
      };
    }).toList();
  }

  /// Create from TimeOfDay list
  static List<int> timeOfDayListToMinutes(List<Map<String, int>> times) {
    return times.map((t) => (t['hour'] ?? 0) * 60 + (t['minute'] ?? 0)).toList();
  }
}
