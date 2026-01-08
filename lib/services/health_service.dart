import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for accessing health data from Apple Health (iOS) and Health Connect (Android).
///
/// Provides access to:
/// - Burned calories (active energy)
/// - Workouts
/// - Weight
/// - Age (date of birth)
/// - Gender (biological sex)
class HealthService {
  static final Health _health = Health();
  static bool _isInitialized = false;
  static bool _hasPermissions = false;
  
  // SharedPreferences key for persisting permission state
  static const String _permissionKey = 'health_permission_granted';

  // Health data types we need to read
  static final List<HealthDataType> _readTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.STEPS,
    // Demographics (iOS only)
    if (Platform.isIOS) HealthDataType.GENDER,
    if (Platform.isIOS) HealthDataType.BIRTH_DATE,
  ];

  // Health data types we might write (e.g., sync nutrition data)
  static final List<HealthDataType> _writeTypes = [
    HealthDataType.DIETARY_ENERGY_CONSUMED,
    HealthDataType.DIETARY_PROTEIN_CONSUMED,
    HealthDataType.DIETARY_CARBS_CONSUMED,
    HealthDataType.DIETARY_FATS_CONSUMED,
  ];

  // ============================================
  // INITIALIZATION & PERMISSIONS
  // ============================================

  /// Check if health data is available on this platform
  static bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  /// Initialize the health service
  static Future<void> initialize() async {
    if (_isInitialized || !isAvailable) return;

    await _health.configure();
    
    // Load persisted permission state
    await _loadPersistedPermission();
    
    _isInitialized = true;
  }
  
  /// Load persisted permission state from SharedPreferences
  static Future<void> _loadPersistedPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasPermissions = prefs.getBool(_permissionKey) ?? false;
      debugPrint('[HealthService] Loaded persisted permission: $_hasPermissions');
    } catch (e) {
      debugPrint('[HealthService] Error loading persisted permission: $e');
    }
  }
  
  /// Save permission state to SharedPreferences
  static Future<void> _savePermissionState(bool granted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionKey, granted);
      debugPrint('[HealthService] Saved permission state: $granted');
    } catch (e) {
      debugPrint('[HealthService] Error saving permission state: $e');
    }
  }

  /// Check if we have health permissions
  static Future<bool> hasPermissions() async {
    if (!isAvailable) return false;

    try {
      // Check permissions for read types
      final status = await _health.hasPermissions(_readTypes);
      _hasPermissions = status ?? false;
      
      // Persist the permission state
      await _savePermissionState(_hasPermissions);
      
      return _hasPermissions;
    } catch (e) {
      debugPrint('Error checking health permissions: $e');
      return false;
    }
  }

  /// Request health permissions from the user
  static Future<bool> requestPermissions() async {
    if (!isAvailable) return false;

    try {
      await initialize();

      // Request both read and write permissions
      final permissions = <HealthDataAccess>[];
      for (var _ in _readTypes) {
        permissions.add(HealthDataAccess.READ);
      }
      for (var _ in _writeTypes) {
        permissions.add(HealthDataAccess.READ_WRITE);
      }

      final allTypes = [..._readTypes, ..._writeTypes];

      _hasPermissions = await _health.requestAuthorization(
        allTypes,
        permissions: permissions,
      );
      
      // Persist the permission state
      await _savePermissionState(_hasPermissions);

      return _hasPermissions;
    } catch (e) {
      debugPrint('Error requesting health permissions: $e');
      return false;
    }
  }

  /// Check if Health Connect is installed (Android only)
  static Future<bool> isHealthConnectInstalled() async {
    if (!Platform.isAndroid) return true; // iOS doesn't need this check

    try {
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (e) {
      debugPrint('Error checking Health Connect status: $e');
      // If we can't check, assume it might be available and let the request fail
      return true;
    }
  }

  /// Open Health Connect app settings (Android only)
  static Future<void> openHealthConnectSettings() async {
    if (!Platform.isAndroid) return;

    try {
      // Try to use the health package method if available
      await _health.revokePermissions();
      // The revokePermissions call will open Health Connect app on Android
    } catch (e) {
      debugPrint('Error opening Health Connect settings: $e');
    }
  }

  /// Open Health Connect in Play Store (Android only)
  static Future<void> openHealthConnectPlayStore() async {
    if (!Platform.isAndroid) return;

    try {
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('Error opening Play Store: $e');
    }
  }

  // ============================================
  // BURNED CALORIES
  // ============================================

  /// Get total active energy burned for today
  static Future<double> getTodayBurnedCalories() async {
    if (!_hasPermissions) return 0;

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: startOfDay,
        endTime: now,
      );

      // Sum all active energy values
      double totalCalories = 0;
      for (final point in data) {
        if (point.value is NumericHealthValue) {
          totalCalories += (point.value as NumericHealthValue).numericValue;
        }
      }

      return totalCalories;
    } catch (e) {
      debugPrint('Error getting burned calories: $e');
      return 0;
    }
  }

  /// Get burned calories for a specific date
  static Future<double> getBurnedCaloriesForDate(DateTime date) async {
    if (!_hasPermissions) {
      debugPrint('[HealthService] No permissions for burned calories');
      return 0;
    }

    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: startOfDay,
        endTime: endOfDay,
      );

      double totalCalories = 0;
      for (final point in data) {
        if (point.value is NumericHealthValue) {
          totalCalories += (point.value as NumericHealthValue).numericValue;
        }
      }

      debugPrint('[HealthService] Burned calories for $date: ${totalCalories.round()} kcal (${data.length} points)');
      return totalCalories;
    } catch (e) {
      debugPrint('Error getting burned calories for date: $e');
      return 0;
    }
  }

  /// Get burned calories for the past week (for chart)
  /// OPTIMIZED: Single query for entire week instead of 7 separate queries
  static Future<Map<DateTime, double>> getWeeklyBurnedCalories(
    DateTime weekStart,
  ) async {
    if (!_hasPermissions) return {};

    try {
      final weekEnd = weekStart.add(const Duration(days: 7));

      // Single query for entire week
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: weekStart,
        endTime: weekEnd,
      );

      // Group by day
      final weeklyData = <DateTime, double>{};
      for (var i = 0; i < 7; i++) {
        final date = weekStart.add(Duration(days: i));
        weeklyData[DateTime(date.year, date.month, date.day)] = 0;
      }

      for (final point in data) {
        if (point.value is NumericHealthValue) {
          final dayKey = DateTime(
            point.dateFrom.year,
            point.dateFrom.month,
            point.dateFrom.day,
          );
          final value = (point.value as NumericHealthValue).numericValue
              .toDouble();
          weeklyData[dayKey] = (weeklyData[dayKey] ?? 0) + value;
        }
      }

      return weeklyData;
    } catch (e) {
      debugPrint('Error getting weekly burned calories: $e');
      return {};
    }
  }

  // ============================================
  // WORKOUTS
  // ============================================

  /// Get workouts for today
  static Future<List<WorkoutData>> getTodayWorkouts() async {
    if (!_hasPermissions) return [];

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    return getWorkoutsForDateRange(startOfDay, now);
  }

  /// Get workouts for a date range
  static Future<List<WorkoutData>> getWorkoutsForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    if (!_hasPermissions) return [];

    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );

      final workouts = <WorkoutData>[];
      for (final point in data) {
        if (point.value is WorkoutHealthValue) {
          final workout = point.value as WorkoutHealthValue;
          workouts.add(
            WorkoutData(
              type: workout.workoutActivityType.name,
              startTime: point.dateFrom,
              endTime: point.dateTo,
              calories: workout.totalEnergyBurned?.toDouble() ?? 0,
              duration: point.dateTo.difference(point.dateFrom),
            ),
          );
        }
      }

      return workouts;
    } catch (e) {
      debugPrint('Error getting workouts: $e');
      return [];
    }
  }

  // ============================================
  // WEIGHT
  // ============================================

  /// Get the latest weight measurement (in kg)
  static Future<double?> getLatestWeight() async {
    if (!_hasPermissions) return null;

    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: thirtyDaysAgo,
        endTime: now,
      );

      if (data.isEmpty) return null;

      // Get the most recent measurement
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final latest = data.first;

      if (latest.value is NumericHealthValue) {
        return (latest.value as NumericHealthValue).numericValue.toDouble();
      }

      return null;
    } catch (e) {
      debugPrint('Error getting weight: $e');
      return null;
    }
  }

  /// Get weight history for the past N days
  static Future<List<WeightRecord>> getWeightHistory({int days = 30}) async {
    if (!_hasPermissions) return [];

    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: startDate,
        endTime: now,
      );

      final records = <WeightRecord>[];
      for (final point in data) {
        if (point.value is NumericHealthValue) {
          records.add(
            WeightRecord(
              date: point.dateTo,
              weightKg: (point.value as NumericHealthValue).numericValue
                  .toDouble(),
            ),
          );
        }
      }

      // Sort by date
      records.sort((a, b) => a.date.compareTo(b.date));
      return records;
    } catch (e) {
      debugPrint('Error getting weight history: $e');
      return [];
    }
  }

  // ============================================
  // HEIGHT
  // ============================================

  /// Get the latest height measurement (in cm)
  static Future<double?> getLatestHeight() async {
    if (!_hasPermissions) return null;

    try {
      final now = DateTime.now();
      final yearAgo = now.subtract(const Duration(days: 365));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEIGHT],
        startTime: yearAgo,
        endTime: now,
      );

      if (data.isEmpty) return null;

      // Get the most recent measurement
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final latest = data.first;

      if (latest.value is NumericHealthValue) {
        // Convert meters to cm if needed
        double heightM = (latest.value as NumericHealthValue).numericValue
            .toDouble();
        return heightM < 3 ? heightM * 100 : heightM; // Assume meters if < 3
      }

      return null;
    } catch (e) {
      debugPrint('Error getting height: $e');
      return null;
    }
  }

  // ============================================
  // STEPS
  // ============================================

  /// Get total steps for today
  static Future<int> getTodaySteps() async {
    if (!_hasPermissions) return 0;

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final steps = await _health.getTotalStepsInInterval(startOfDay, now);
      return steps ?? 0;
    } catch (e) {
      debugPrint('Error getting steps: $e');
      return 0;
    }
  }

  // ============================================
  // WRITE NUTRITION DATA
  // ============================================

  /// Write consumed calories to health app
  static Future<bool> writeConsumedCalories(
    double calories,
    DateTime time,
  ) async {
    if (!_hasPermissions) return false;

    try {
      return await _health.writeHealthData(
        value: calories,
        type: HealthDataType.DIETARY_ENERGY_CONSUMED,
        startTime: time,
        endTime: time.add(const Duration(minutes: 1)),
        unit: HealthDataUnit.KILOCALORIE,
      );
    } catch (e) {
      debugPrint('Error writing calories: $e');
      return false;
    }
  }

  /// Write meal nutrition to health app
  static Future<bool> writeMealNutrition({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required DateTime time,
  }) async {
    if (!_hasPermissions) return false;

    try {
      final results = await Future.wait([
        _health.writeHealthData(
          value: calories,
          type: HealthDataType.DIETARY_ENERGY_CONSUMED,
          startTime: time,
          endTime: time.add(const Duration(minutes: 1)),
          unit: HealthDataUnit.KILOCALORIE,
        ),
        _health.writeHealthData(
          value: protein,
          type: HealthDataType.DIETARY_PROTEIN_CONSUMED,
          startTime: time,
          endTime: time.add(const Duration(minutes: 1)),
          unit: HealthDataUnit.GRAM,
        ),
        _health.writeHealthData(
          value: carbs,
          type: HealthDataType.DIETARY_CARBS_CONSUMED,
          startTime: time,
          endTime: time.add(const Duration(minutes: 1)),
          unit: HealthDataUnit.GRAM,
        ),
        _health.writeHealthData(
          value: fat,
          type: HealthDataType.DIETARY_FATS_CONSUMED,
          startTime: time,
          endTime: time.add(const Duration(minutes: 1)),
          unit: HealthDataUnit.GRAM,
        ),
      ]);

      return results.every((success) => success);
    } catch (e) {
      debugPrint('Error writing meal nutrition: $e');
      return false;
    }
  }

  // ============================================
  // USER PROFILE
  // ============================================

  /// Get biological sex from HealthKit (iOS only)
  static Future<String?> getGender() async {
    if (!_hasPermissions || !Platform.isIOS) return null;

    try {
      final now = DateTime.now();
      final yearAgo = now.subtract(const Duration(days: 365));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.GENDER],
        startTime: yearAgo,
        endTime: now,
      );

      if (data.isEmpty) return null;

      // Gender is stored as a string value
      final genderData = data.first;
      return genderData.value.toString();
    } catch (e) {
      debugPrint('Error getting gender: $e');
      return null;
    }
  }

  /// Get date of birth from HealthKit (iOS only)
  static Future<DateTime?> getDateOfBirth() async {
    if (!_hasPermissions || !Platform.isIOS) return null;

    try {
      final now = DateTime.now();
      final yearAgo = now.subtract(const Duration(days: 365));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.BIRTH_DATE],
        startTime: yearAgo,
        endTime: now,
      );

      if (data.isEmpty) return null;

      // Parse date of birth - value is typically a string or DateTime
      final dobData = data.first;
      final value = dobData.value;
      
      // Try to parse as DateTime from the value
      if (value is NumericHealthValue) {
        // Some implementations return timestamp
        return DateTime.fromMillisecondsSinceEpoch(value.numericValue.toInt());
      }
      
      // Try parsing from string representation
      final valueStr = value.toString();
      return DateTime.tryParse(valueStr);
    } catch (e) {
      debugPrint('Error getting date of birth: $e');
      return null;
    }
  }

  /// Calculate age from date of birth
  static Future<int?> getAge() async {
    final dob = await getDateOfBirth();
    if (dob == null) return null;

    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  /// Get comprehensive user health profile
  static Future<HealthProfile> getUserProfile() async {
    final weight = await getLatestWeight();
    final height = await getLatestHeight();
    final steps = await getTodaySteps();
    final burnedCalories = await getTodayBurnedCalories();
    final gender = await getGender();
    final age = await getAge();

    return HealthProfile(
      weightKg: weight,
      heightCm: height,
      todaySteps: steps,
      todayBurnedCalories: burnedCalories,
      gender: gender,
      age: age,
    );
  }
}

// ============================================
// DATA MODELS
// ============================================

/// Workout data from health app
class WorkoutData {
  final String type;
  final DateTime startTime;
  final DateTime endTime;
  final double calories;
  final Duration duration;

  WorkoutData({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.calories,
    required this.duration,
  });

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get formattedType {
    // Convert WORKOUT_TYPE to readable format
    return type
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '',
        )
        .join(' ');
  }
}

/// Weight record from health app
class WeightRecord {
  final DateTime date;
  final double weightKg;

  WeightRecord({required this.date, required this.weightKg});

  double get weightLbs => weightKg * 2.20462;
}

/// User health profile
class HealthProfile {
  final double? weightKg;
  final double? heightCm;
  final int todaySteps;
  final double todayBurnedCalories;
  final String? gender;
  final int? age;

  HealthProfile({
    this.weightKg,
    this.heightCm,
    required this.todaySteps,
    required this.todayBurnedCalories,
    this.gender,
    this.age,
  });

  /// Calculate BMI if height and weight are available
  double? get bmi {
    if (weightKg == null || heightCm == null) return null;
    final heightM = heightCm! / 100;
    return weightKg! / (heightM * heightM);
  }

  /// Get BMI category
  String? get bmiCategory {
    final bmiValue = bmi;
    if (bmiValue == null) return null;

    if (bmiValue < 18.5) return 'Underweight';
    if (bmiValue < 25) return 'Normal';
    if (bmiValue < 30) return 'Overweight';
    return 'Obese';
  }
}
