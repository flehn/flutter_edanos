import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/meal.dart';
import 'firestore_service.dart';
import 'meal_repository.dart';
import '../gemini_service.dart';

/// Tracks the user's 20-day progress cycle.
///
/// - A cycle starts the day the user first scans a meal (or after the last cycle ended).
/// - Each day with at least 1 scanned meal counts as an "active day".
/// - When the user reaches 18 active days within 20 calendar days, the progress
///   evaluation is triggered.
/// - After evaluation (or after 20 calendar days pass), a new cycle begins.
class ProgressService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get _userId => _auth.currentUser!.uid;

  static DocumentReference<Map<String, dynamic>> get _progressRef =>
      _db.collection('users').doc(_userId).collection('settings').doc('progress');

  /// Get or create the current progress cycle data.
  /// Returns a map with: cycleStartDate, activeDays (list of date strings),
  /// lastEvaluation (map or null).
  static Future<ProgressData> getProgressData() async {
    final doc = await _progressRef.get();
    if (!doc.exists || doc.data() == null) {
      return ProgressData.fresh();
    }
    return ProgressData.fromFirestore(doc.data()!);
  }

  /// Save progress data to Firestore.
  static Future<void> saveProgressData(ProgressData data) async {
    await _progressRef.set(data.toFirestore());
  }

  /// Compute the current progress state by cross-referencing meal data.
  /// Returns a snapshot with active day count, days remaining, and eligibility.
  static Future<ProgressSnapshot> computeSnapshot() async {
    final data = await getProgressData();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cycleStart = data.cycleStartDate;

    // If no cycle exists yet, check if user has any meals at all
    if (cycleStart == null) {
      final firstMealDate = await MealRepository.getFirstMealDate();
      if (firstMealDate == null) {
        return ProgressSnapshot(
          cycleStartDate: null,
          totalDaysInCycle: 0,
          activeDays: 0,
          activeDayFlags: List.filled(20, false),
          daysRemaining: 20,
          isEligibleForEvaluation: false,
          lastEvaluation: data.lastEvaluation,
        );
      }
      // Start a new cycle from the first meal date
      final newStart = DateTime(firstMealDate.year, firstMealDate.month, firstMealDate.day);
      final newData = ProgressData(
        cycleStartDate: newStart,
        activeDays: [],
        lastEvaluation: null,
      );
      await saveProgressData(newData);
      return _buildSnapshot(newData, today);
    }

    // Check if cycle has expired (more than 20 days)
    final daysSinceStart = today.difference(cycleStart).inDays;
    if (daysSinceStart >= 20 && data.lastEvaluation != null) {
      // Start a new cycle from today
      final newData = ProgressData(
        cycleStartDate: today,
        activeDays: [],
        lastEvaluation: null,
      );
      await saveProgressData(newData);
      return _buildSnapshot(newData, today);
    }

    return _buildSnapshot(data, today);
  }

  /// Build the snapshot by checking which days in the cycle had meals.
  static Future<ProgressSnapshot> _buildSnapshot(ProgressData data, DateTime today) async {
    final cycleStart = data.cycleStartDate!;
    final daysSinceStart = today.difference(cycleStart).inDays;
    final totalDays = (daysSinceStart + 1).clamp(0, 20);

    // Fetch meals for the 20-day window
    final cycleEnd = cycleStart.add(const Duration(days: 20));
    final meals = await FirestoreService.getMealsForDateRange(cycleStart, cycleEnd);

    // Determine which days have meals
    final activeDayFlags = List.filled(20, false);
    final activeDayDates = <String>{};

    for (final meal in meals) {
      final mealDay = DateTime(meal.scannedAt.year, meal.scannedAt.month, meal.scannedAt.day);
      final dayIndex = mealDay.difference(cycleStart).inDays;
      if (dayIndex >= 0 && dayIndex < 20) {
        activeDayFlags[dayIndex] = true;
        activeDayDates.add(_dateKey(mealDay));
      }
    }

    // Update stored active days
    if (activeDayDates.length != data.activeDays.length ||
        !activeDayDates.containsAll(data.activeDays.toSet())) {
      final updatedData = ProgressData(
        cycleStartDate: cycleStart,
        activeDays: activeDayDates.toList()..sort(),
        lastEvaluation: data.lastEvaluation,
      );
      await saveProgressData(updatedData);
    }

    final activeDayCount = activeDayFlags.where((f) => f).length;
    final daysRemaining = 20 - totalDays;

    return ProgressSnapshot(
      cycleStartDate: cycleStart,
      totalDaysInCycle: totalDays,
      activeDays: activeDayCount,
      activeDayFlags: activeDayFlags,
      daysRemaining: daysRemaining.clamp(0, 20),
      isEligibleForEvaluation: activeDayCount >= 18 && data.lastEvaluation == null,
      lastEvaluation: data.lastEvaluation,
    );
  }

  /// Run the 20-day progress evaluation using Gemini + Google Search.
  static Future<Map<String, dynamic>?> runProgressEvaluation() async {
    final data = await getProgressData();
    if (data.cycleStartDate == null) return null;

    final cycleStart = data.cycleStartDate!;
    final cycleEnd = cycleStart.add(const Duration(days: 20));

    // Fetch all meals in the 20-day window
    final meals = await FirestoreService.getMealsForDateRange(cycleStart, cycleEnd);

    // Build daily summaries with meal details and timing
    final dailySummaries = <Map<String, dynamic>>[];
    for (var i = 0; i < 20; i++) {
      final day = cycleStart.add(Duration(days: i));
      final dayMeals = meals.where((m) {
        final md = DateTime(m.scannedAt.year, m.scannedAt.month, m.scannedAt.day);
        return md.year == day.year && md.month == day.month && md.day == day.day;
      }).toList();

      final mealDetails = dayMeals.map((m) {
        final time = '${m.scannedAt.hour.toString().padLeft(2, '0')}:${m.scannedAt.minute.toString().padLeft(2, '0')}';
        final ingredients = m.ingredients.map((i) => i.name).join(', ');
        return '$time ${m.name} ($ingredients)';
      }).join('; ');

      dailySummaries.add({
        'date': _dateKey(day),
        'mealCount': dayMeals.length,
        'calories': dayMeals.fold(0.0, (sum, m) => sum + m.totalCalories).round(),
        'protein': dayMeals.fold(0.0, (sum, m) => sum + m.totalProtein).round(),
        'carbs': dayMeals.fold(0.0, (sum, m) => sum + m.totalCarbs).round(),
        'fat': dayMeals.fold(0.0, (sum, m) => sum + m.totalFat).round(),
        'fiber': dayMeals.fold(0.0, (sum, m) => sum + m.totalFiber).round(),
        'sugar': dayMeals.fold(0.0, (sum, m) => sum + m.totalSugar).round(),
        'mealDetails': mealDetails.isEmpty ? 'No meals' : mealDetails,
      });
    }

    // Get user profile
    final settings = await MealRepository.getUserSettings();
    final goals = await MealRepository.getUserGoals();
    final goalDesc = goals.isGainMode ? 'gain weight / build muscle' : 'lose weight / lose fat';

    final activeDayCount = data.activeDays.length;

    // Call Gemini
    final result = await GeminiService.evaluateProgress(
      gender: settings.gender,
      age: settings.age,
      weightKg: settings.weight,
      goal: goalDesc,
      activeDays: activeDayCount,
      dailySummaries: dailySummaries,
    );

    if (result == null) return null;

    // Parse response
    Map<String, dynamic> evaluation;
    try {
      // Try to extract JSON from response (may have markdown fences)
      final jsonStr = _extractJson(result);
      evaluation = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to parse progress evaluation: $e');
      evaluation = {
        'overallProgress': result,
        'strengths': '',
        'improvements': '',
        'mealTimingFeedback': '',
        'progressScore': 5,
      };
    }

    evaluation['evaluatedAt'] = DateTime.now().toIso8601String();
    evaluation['activeDays'] = activeDayCount;

    // Save evaluation
    final updatedData = ProgressData(
      cycleStartDate: data.cycleStartDate,
      activeDays: data.activeDays,
      lastEvaluation: evaluation,
    );
    await saveProgressData(updatedData);

    return evaluation;
  }

  /// Mark today as an active day (call after a meal is scanned).
  static Future<void> markTodayActive() async {
    final data = await getProgressData();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = _dateKey(today);

    if (data.cycleStartDate == null) {
      // Start a new cycle
      await saveProgressData(ProgressData(
        cycleStartDate: today,
        activeDays: [todayKey],
        lastEvaluation: null,
      ));
      return;
    }

    if (!data.activeDays.contains(todayKey)) {
      data.activeDays.add(todayKey);
      await saveProgressData(data);
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _extractJson(String text) {
    final fenceMatch = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(text);
    if (fenceMatch != null) return fenceMatch.group(1)!.trim();
    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (braceMatch != null) return braceMatch.group(0)!;
    return text;
  }
}

/// Persisted progress cycle data.
class ProgressData {
  DateTime? cycleStartDate;
  List<String> activeDays;
  Map<String, dynamic>? lastEvaluation;

  ProgressData({
    this.cycleStartDate,
    required this.activeDays,
    this.lastEvaluation,
  });

  factory ProgressData.fresh() => ProgressData(activeDays: []);

  factory ProgressData.fromFirestore(Map<String, dynamic> data) {
    return ProgressData(
      cycleStartDate: data['cycleStartDate'] != null
          ? DateTime.parse(data['cycleStartDate'] as String)
          : null,
      activeDays: (data['activeDays'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastEvaluation: data['lastEvaluation'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'cycleStartDate': cycleStartDate?.toIso8601String(),
      'activeDays': activeDays,
      if (lastEvaluation != null) 'lastEvaluation': lastEvaluation,
    };
  }
}

/// A snapshot of the current progress state (computed, not persisted).
class ProgressSnapshot {
  final DateTime? cycleStartDate;
  final int totalDaysInCycle;
  final int activeDays;
  final List<bool> activeDayFlags; // 20 booleans, one per day
  final int daysRemaining;
  final bool isEligibleForEvaluation;
  final Map<String, dynamic>? lastEvaluation;

  ProgressSnapshot({
    required this.cycleStartDate,
    required this.totalDaysInCycle,
    required this.activeDays,
    required this.activeDayFlags,
    required this.daysRemaining,
    required this.isEligibleForEvaluation,
    this.lastEvaluation,
  });
}
