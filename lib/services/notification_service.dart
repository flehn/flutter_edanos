import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for scheduling and managing local notifications.
/// Used for meal reminders.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  // Notification channel ID for meal reminders
  static const String _channelId = 'meal_reminders';
  static const String _channelName = 'Meal Reminders';
  static const String _channelDescription = 'Reminders to log your meals';

  // Preference keys
  static const String _keyRemindersEnabled = 'reminders_enabled';
  static const String _keyReminderTimes = 'reminder_times';

  // ============================================
  // INITIALIZATION
  // ============================================

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize timezone
    tz_data.initializeTimeZones();

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    // Handle when user taps on a notification
    debugPrint('Notification tapped: ${response.payload}');
    // You can navigate to a specific screen here
  }

  // ============================================
  // PERMISSION MANAGEMENT
  // ============================================

  /// Request notification permissions
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        return granted ?? false;
      }
      return true; // Older Android versions don't need permission
    }

    if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    }

    return false;
  }

  // ============================================
  // REMINDER SCHEDULING
  // ============================================

  /// Schedule meal reminders at specified times
  static Future<void> scheduleMealReminders(List<TimeOfDay> times) async {
    await initialize();

    // Cancel existing reminders first
    await cancelAllReminders();

    // Request permissions if needed
    await requestPermissions();

    // Schedule each reminder
    for (var i = 0; i < times.length; i++) {
      await _scheduleDaily(
        id: i,
        time: times[i],
        title: 'Time to log your meal! 🍽️',
        body: _getMealMessage(times[i]),
      );
    }

    // Save the reminder times
    await _saveReminderTimes(times);
  }

  /// Schedule a daily notification at a specific time
  static Future<void> _scheduleDaily({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If the time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
      payload: 'meal_reminder_$id',
    );

    debugPrint('Scheduled reminder #$id at ${time.hour}:${time.minute}');
  }

  /// Get a contextual message based on the time of day
  static String _getMealMessage(TimeOfDay time) {
    final hour = time.hour;
    if (hour >= 5 && hour < 11) {
      return "Don't forget to log your breakfast!";
    } else if (hour >= 11 && hour < 15) {
      return "How was lunch? Log it to track your nutrition!";
    } else if (hour >= 15 && hour < 18) {
      return "Had a snack? Log it to stay on track!";
    } else if (hour >= 18 && hour < 22) {
      return "Dinner time! Remember to log your meal.";
    } else {
      return "Remember to log your food intake!";
    }
  }

  /// Cancel all scheduled reminders
  static Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();
  }

  /// Cancel a specific reminder
  static Future<void> cancelReminder(int id) async {
    await _notifications.cancel(id);
  }

  // ============================================
  // PERSISTENCE
  // ============================================

  /// Save reminder times to local storage
  static Future<void> _saveReminderTimes(List<TimeOfDay> times) async {
    final prefs = await SharedPreferences.getInstance();

    // Convert TimeOfDay to string list (e.g., "8:30", "12:0", "18:30")
    final timeStrings = times.map((t) => '${t.hour}:${t.minute}').toList();
    await prefs.setStringList(_keyReminderTimes, timeStrings);
  }

  /// Load reminder times from local storage
  static Future<List<TimeOfDay>> loadReminderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStrings = prefs.getStringList(_keyReminderTimes);

    if (timeStrings == null || timeStrings.isEmpty) {
      // Default times: Breakfast, Lunch, Dinner
      return [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 12, minute: 30),
        const TimeOfDay(hour: 18, minute: 30),
      ];
    }

    return timeStrings.map((s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
  }

  /// Save reminders enabled state
  static Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemindersEnabled, enabled);

    if (!enabled) {
      await cancelAllReminders();
    } else {
      final times = await loadReminderTimes();
      await scheduleMealReminders(times);
    }
  }

  /// Check if reminders are enabled
  static Future<bool> areRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRemindersEnabled) ?? true;
  }

  // ============================================
  // TESTING / DEBUG
  // ============================================

  /// Show an immediate test notification
  static Future<void> showTestNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      999, // Test notification ID
      'Test Notification',
      'This is a test meal reminder!',
      notificationDetails,
    );
  }
}
