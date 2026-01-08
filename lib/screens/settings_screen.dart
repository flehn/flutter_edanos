import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../services/meal_repository.dart';

/// Settings Screen - App preferences and user account
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _mealReminders = true;
  bool _useDetailedAnalysis = false;
  bool _syncToHealth = false;
  String _units = 'Metric';
  
  // Personal profile
  String _gender = 'male';
  int _age = 30;
  double _weight = 70.0;

  // Health data
  bool _healthAvailable = false;
  bool _healthPermissionsGranted = false;
  bool _isRequestingHealthPermissions = false;
  HealthProfile? _healthProfile;

  // Meal reminder times (stored as TimeOfDay)
  List<TimeOfDay> _reminderTimes = [
    const TimeOfDay(hour: 8, minute: 0), // Breakfast
    const TimeOfDay(hour: 12, minute: 30), // Lunch
    const TimeOfDay(hour: 18, minute: 30), // Dinner
  ];

  /// User has an account (not anonymous)
  bool get _hasAccount => AuthService.hasAccount;

  /// User is anonymous (using app without account)
  bool get _isAnonymous => AuthService.isAnonymous;

  String? get _userEmail => AuthService.userEmail;

  @override
  void initState() {
    super.initState();
    _checkHealthStatus();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    try {
      // Load from Firebase
      final settings = await MealRepository.getUserSettings();

      // Also load notification times from local (NotificationService handles scheduling)
      final times = await NotificationService.loadReminderTimes();

      if (mounted) {
        setState(() {
          _notifications = settings.notificationsEnabled;
          _mealReminders = settings.mealRemindersEnabled;
          _useDetailedAnalysis = settings.useDetailedAnalysis;
          _syncToHealth = settings.syncToHealth;
          _units = settings.units;
          _reminderTimes = times;
          _gender = settings.gender;
          _age = settings.age;
          _weight = settings.weight;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      // Fall back to loading just notification settings locally
      _loadReminderSettingsLocal();
    }
  }

  Future<void> _loadReminderSettingsLocal() async {
    try {
      final enabled = await NotificationService.areRemindersEnabled();
      final times = await NotificationService.loadReminderTimes();

      if (mounted) {
        setState(() {
          _mealReminders = enabled;
          _reminderTimes = times;
        });
      }
    } catch (e) {
      debugPrint('Error loading reminder settings: $e');
    }
  }

  Future<void> _saveSettingsToFirebase() async {
    try {
      final settings = UserSettings(
        notificationsEnabled: _notifications,
        mealRemindersEnabled: _mealReminders,
        useDetailedAnalysis: _useDetailedAnalysis,
        syncToHealth: _syncToHealth,
        units: _units,
        reminderTimesMinutes: _reminderTimes
            .map((t) => t.hour * 60 + t.minute)
            .toList(),
        gender: _gender,
        age: _age,
        weight: _weight,
      );
      await MealRepository.saveUserSettings(settings);
    } catch (e) {
      debugPrint('Error saving settings to Firebase: $e');
    }
  }

  Future<void> _checkHealthStatus() async {
    if (kIsWeb) {
      setState(() => _healthAvailable = false);
      return;
    }

    final available = Platform.isIOS || Platform.isAndroid;
    if (!available) {
      setState(() => _healthAvailable = false);
      return;
    }

    setState(() => _healthAvailable = true);

    // Check if we already have permissions
    final hasPerms = await HealthService.hasPermissions();
    setState(() => _healthPermissionsGranted = hasPerms);

    if (hasPerms) {
      _loadHealthProfile();
    }
  }

  Future<void> _loadHealthProfile() async {
    final profile = await HealthService.getUserProfile();
    setState(() => _healthProfile = profile);
  }

  Future<void> _requestHealthPermissions() async {
    setState(() => _isRequestingHealthPermissions = true);

    try {
      // On Android, check if Health Connect is installed
      if (Platform.isAndroid) {
        final isInstalled = await HealthService.isHealthConnectInstalled();
        if (!isInstalled) {
          if (mounted) {
            _showHealthConnectInstallDialog();
          }
          setState(() => _isRequestingHealthPermissions = false);
          return;
        }
      }

      // Request permissions - this will show the system permission dialog
      final granted = await HealthService.requestPermissions();
      setState(() => _healthPermissionsGranted = granted);

      if (granted) {
        _loadHealthProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Health access granted!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          // Show a more helpful message
          _showHealthPermissionDeniedDialog();
        }
      }
    } catch (e) {
      debugPrint('Error requesting health permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request health access: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRequestingHealthPermissions = false);
      }
    }
  }

  void _showHealthConnectInstallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.monitor_heart, color: AppTheme.positiveColor),
            SizedBox(width: 12),
            Text(
              'Health Connect Required',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: const Text(
          'To sync your health data, you need to install Health Connect from the Google Play Store.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              HealthService.openHealthConnectPlayStore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.positiveColor,
            ),
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  void _showHealthPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Platform.isIOS ? Icons.favorite : Icons.monitor_heart,
              color: AppTheme.warningColor,
            ),
            const SizedBox(width: 12),
            const Text(
              'Permission Denied',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Text(
          Platform.isIOS
              ? 'Health access was denied. To enable it:\n\n1. Open the Settings app\n2. Tap Privacy & Security\n3. Tap Health\n4. Find EdanosAI and enable permissions'
              : 'Health Connect access was denied. To enable it:\n\n1. Open Health Connect app\n2. Tap App permissions\n3. Find EdanosAI and enable permissions',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          if (Platform.isAndroid)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                HealthService.openHealthConnectSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
              ),
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account section
            _buildSectionHeader('Account'),
            if (_isAnonymous) ...[
              // Anonymous user - show create account option
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.cloud_off,
                          color: AppTheme.primaryBlue,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Guest Mode',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your data is stored locally. Create an account to sync across devices and keep your data safe.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _showCreateAccountDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Create Account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _showSignInDialog,
                        child: const Text(
                          'Already have an account? Sign In',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Authenticated user - show account info
              _buildSettingsTile(
                icon: Icons.person_outline,
                title: _userEmail ?? 'Account',
                subtitle: 'Signed in',
                trailing: const SizedBox(), // Non-tappable
              ),
              // Account management options
              _buildSettingsTile(
                icon: Icons.email_outlined,
                title: 'Change Email',
                subtitle: 'Update your email address',
                onTap: _showChangeEmailDialog,
              ),
              // Account management options
              _buildSettingsTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                subtitle: 'Update your password',
                onTap: _showChangePasswordDialog,
              ),
              _buildSettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Delete Account',
                subtitle: 'Permanently remove your account',
                textColor: AppTheme.negativeColor,
                onTap: _showDeleteAccountDialog,
              ),
              _buildSettingsTile(
                icon: Icons.logout,
                title: 'Sign Out',
                textColor: AppTheme.negativeColor,
                onTap: _showSignOutDialog,
              ),
            ],


            const SizedBox(height: 24),

            // Personal Profile section
            _buildSectionHeader('Personal Profile'),
            _buildSettingsTile(
              icon: Icons.person_outline,
              title: 'Gender',
              subtitle: _gender == 'male' ? 'Male' : 'Female',
              trailing: DropdownButton<String>(
                value: _gender,
                dropdownColor: AppTheme.cardDark,
                underline: const SizedBox(),
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textTertiary,
                ),
                items: ['male', 'female'].map((g) {
                  return DropdownMenuItem(
                    value: g,
                    child: Text(
                      g == 'male' ? 'Male' : 'Female',
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _gender = value);
                    _saveSettingsToFirebase();
                  }
                },
              ),
            ),
            _buildSettingsTile(
              icon: Icons.cake_outlined,
              title: 'Age',
              subtitle: '$_age years',
              onTap: () => _showAgeDialog(),
            ),
            _buildSettingsTile(
              icon: Icons.monitor_weight_outlined,
              title: 'Weight',
              subtitle: _units == 'Metric'
                  ? '${_weight.toStringAsFixed(1)} kg'
                  : '${(_weight * 2.205).toStringAsFixed(1)} lbs',
              onTap: () => _showWeightDialog(),
            ),

            const SizedBox(height: 24),

            // Preferences section
            _buildSectionHeader('Preferences'),

            _buildSwitchTile(
              icon: Icons.schedule_outlined,
              title: 'Meal Reminders',
              subtitle: 'Get reminded to log meals',
              value: _mealReminders,
              onChanged: (value) async {
                setState(() => _mealReminders = value);
                await NotificationService.setRemindersEnabled(value);
                _saveSettingsToFirebase();
                if (value && mounted) {
                  // Request notification permissions when enabling
                  final granted =
                      await NotificationService.requestPermissions();
                  if (!granted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enable notifications in Settings',
                        ),
                        backgroundColor: AppTheme.warningColor,
                      ),
                    );
                  }
                }
              },
            ),
            // Show reminder times when enabled
            if (_mealReminders) ...[_buildReminderTimesSection()],
            _buildSettingsTile(
              icon: Icons.straighten_outlined,
              title: 'Units',
              subtitle: _units,
              trailing: DropdownButton<String>(
                value: _units,
                dropdownColor: AppTheme.cardDark,
                underline: const SizedBox(),
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textTertiary,
                ),
                items: ['Metric', 'Imperial'].map((unit) {
                  return DropdownMenuItem(
                    value: unit,
                    child: Text(
                      unit,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _units = value);
                    _saveSettingsToFirebase();
                  }
                },
              ),
            ),

            const SizedBox(height: 24),

            // Health section (Apple Health / Health Connect)
            if (_healthAvailable) ...[
              _buildSectionHeader('Health'),
              if (!_healthPermissionsGranted) ...[
                // Not connected - show connect button
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.positiveColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.positiveColor.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Platform.isIOS
                                ? Icons.favorite
                                : Icons.monitor_heart,
                            color: AppTheme.positiveColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            Platform.isIOS ? 'Apple Health' : 'Health Connect',
                            style: const TextStyle(
                              color: AppTheme.positiveColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect to sync burned calories, workouts, and weight data.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isRequestingHealthPermissions
                              ? null
                              : _requestHealthPermissions,
                          icon: _isRequestingHealthPermissions
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.link, size: 18),
                          label: Text(
                            _isRequestingHealthPermissions
                                ? 'Connecting...'
                                : 'Connect',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.positiveColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Connected - show health data and settings
                _buildSettingsTile(
                  icon: Platform.isIOS ? Icons.favorite : Icons.monitor_heart,
                  title: Platform.isIOS ? 'Apple Health' : 'Health Connect',
                  subtitle: 'Connected',
                  trailing: const Icon(
                    Icons.check_circle,
                    color: AppTheme.positiveColor,
                  ),
                  onTap: () {},
                ),
                if (_healthProfile != null) ...[
                  if (_healthProfile!.weightKg != null)
                    _buildSettingsTile(
                      icon: Icons.monitor_weight_outlined,
                      title: 'Weight',
                      subtitle:
                          '${_healthProfile!.weightKg!.toStringAsFixed(1)} kg',
                      onTap: () {},
                    ),
                  _buildSettingsTile(
                    icon: Icons.local_fire_department_outlined,
                    title: 'Burned Today',
                    subtitle:
                        '${_healthProfile!.todayBurnedCalories.round()} kcal',
                    onTap: () {},
                  ),
                ],
                _buildSwitchTile(
                  icon: Icons.sync,
                  title: 'Sync Nutrition to Health',
                  subtitle:
                      'Write meal data to ${Platform.isIOS ? "Apple Health" : "Health Connect"}',
                  value: _syncToHealth,
                  onChanged: (value) {
                    setState(() => _syncToHealth = value);
                    _saveSettingsToFirebase();
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],

            // AI Analysis section
            _buildSectionHeader('AI Analysis'),
            _buildSwitchTile(
              icon: Icons.science_outlined,
              title: 'Detailed Analysis',
              subtitle: 'Include vitamins & minerals (slower)',
              value: _useDetailedAnalysis,
              onChanged: (value) {
                setState(() => _useDetailedAnalysis = value);
                _saveSettingsToFirebase();
              },
            ),


            const SizedBox(height: 24),

            // Data section
            _buildSectionHeader('Data'),
            _buildSettingsTile(
              icon: Icons.cloud_download_outlined,
              title: 'Export Data',
              subtitle: 'Download your food log as CSV',
              onTap: _exportDataAsCSV,
            ),
            _buildSettingsTile(
              icon: Icons.delete_outline,
              title: 'Clear Data',
              subtitle: 'Remove all stored meals',
              textColor: AppTheme.negativeColor,
              onTap: _showClearDataDialog,
            ),

            const SizedBox(height: 24),

            // About section
            _buildSectionHeader('About'),
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: 'About EdanosAI',
              subtitle: 'Version 1.0.0',
              onTap: () async {
                final url = Uri.parse('https://www.edanos.com');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            _buildSettingsTile(
              icon: Icons.article_outlined,
              title: 'Terms of Service',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.email_outlined,
              title: 'Contact Support',
              subtitle: 'hello@edanos.com',
              trailing: const SizedBox(), // Non-tappable, just displays info
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? AppTheme.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: textColor ?? AppTheme.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
            )
          : null,
      trailing:
          trailing ??
          const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.primaryBlue,
        inactiveTrackColor: AppTheme.textTertiary.withOpacity(0.3),
      ),
    );
  }

  Widget _buildReminderTimesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, color: AppTheme.primaryBlue, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Reminder Times',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Add time button
              IconButton(
                onPressed: _addReminderTime,
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: AppTheme.primaryBlue,
                ),
                tooltip: 'Add reminder time',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_reminderTimes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No reminders set. Tap + to add one.',
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reminderTimes.asMap().entries.map((entry) {
                final index = entry.key;
                final time = entry.value;
                return _buildReminderTimeChip(index, time);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReminderTimeChip(int index, TimeOfDay time) {
    final formattedTime = _formatTime(time);
    final mealLabel = _getMealLabel(time);

    return GestureDetector(
      onTap: () => _editReminderTime(index, time),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time,
              size: 16,
              color: AppTheme.primaryBlue,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formattedTime,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  mealLabel,
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _removeReminderTime(index),
              child: Icon(Icons.close, size: 16, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _getMealLabel(TimeOfDay time) {
    final hour = time.hour;
    if (hour >= 5 && hour < 11) return 'Breakfast';
    if (hour >= 11 && hour < 15) return 'Lunch';
    if (hour >= 15 && hour < 18) return 'Snack';
    if (hour >= 18 && hour < 22) return 'Dinner';
    return 'Late night';
  }

  Future<void> _addReminderTime() async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryBlue,
              surface: AppTheme.surfaceDark,
            ),
            dialogBackgroundColor: AppTheme.surfaceDark,
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null) {
      // Check if time already exists
      final exists = _reminderTimes.any(
        (t) => t.hour == selectedTime.hour && t.minute == selectedTime.minute,
      );

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time is already set'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
        return;
      }

      setState(() {
        _reminderTimes.add(selectedTime);
        _reminderTimes.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
        );
      });

      // TODO: Schedule notification for this time
      _saveReminderSettings();
    }
  }

  Future<void> _editReminderTime(int index, TimeOfDay currentTime) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryBlue,
              surface: AppTheme.surfaceDark,
            ),
            dialogBackgroundColor: AppTheme.surfaceDark,
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null) {
      setState(() {
        _reminderTimes[index] = selectedTime;
        _reminderTimes.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
        );
      });

      _saveReminderSettings();
    }
  }

  void _removeReminderTime(int index) {
    setState(() {
      _reminderTimes.removeAt(index);
    });

    _saveReminderSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder removed'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveReminderSettings() async {
    try {
      // Schedule notifications at the new times
      await NotificationService.scheduleMealReminders(_reminderTimes);

      debugPrint(
        'Reminder times saved: ${_reminderTimes.map(_formatTime).join(", ")}',
      );
    } catch (e) {
      debugPrint('Error saving reminder settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save reminders: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  /// Show dialog to input age
  void _showAgeDialog() {
    final controller = TextEditingController(text: _age.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Enter Your Age',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Age in years',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.cardDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixText: 'years',
            suffixStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final age = int.tryParse(controller.text);
              if (age != null && age > 0 && age < 150) {
                setState(() => _age = age);
                _saveSettingsToFirebase();
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to input weight
  void _showWeightDialog() {
    final isMetric = _units == 'Metric';
    final displayWeight = isMetric ? _weight : _weight * 2.205;
    final controller = TextEditingController(text: displayWeight.toStringAsFixed(1));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Enter Your Weight',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: isMetric ? 'Weight in kg' : 'Weight in lbs',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.cardDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixText: isMetric ? 'kg' : 'lbs',
            suffixStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final input = double.tryParse(controller.text);
              if (input != null && input > 0) {
                // Convert to kg if imperial
                final weightKg = isMetric ? input : input / 2.205;
                setState(() => _weight = weightKg);
                _saveSettingsToFirebase();
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Export data as CSV and share
  Future<void> _exportDataAsCSV() async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing export...')),
      );

      final csvData = await MealRepository.exportMealsAsCSV();
      
      if (csvData.isEmpty || csvData.split('\n').length <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No meals to export'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
        return;
      }

      // Share the CSV data
      await Share.share(
        csvData,
        subject: 'EdanosAI Food Log Export',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export data: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  /// Show dialog to change email
  void _showChangeEmailDialog() {
    final emailController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Change Email',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A verification email will be sent to your new address.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'New Email',
                  labelStyle: TextStyle(color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: AppTheme.cardDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (emailController.text.isEmpty) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Please enter an email')),
                        );
                        return;
                      }

                      setDialogState(() => isLoading = true);

                      try {
                        await AuthService.updateEmail(emailController.text);
                        Navigator.of(context).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Verification email sent. Please check your inbox.',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          setState(() {}); // Refresh UI
                        }
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update email: $e'),
                              backgroundColor: AppTheme.negativeColor,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All Data?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This will permanently delete all your stored meals and settings. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await MealRepository.clearAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All data cleared successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to clear data: $e'),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign Out?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await AuthService.signOut();
                if (mounted) {
                  setState(() {}); // Refresh UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sign out failed: $e'),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignInDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign In',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isAnonymous)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '⚠️ Signing into an existing account will replace your current data.',
                  style: TextStyle(color: AppTheme.warningColor, fontSize: 12),
                ),
              ),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showForgotPasswordDialog();
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await AuthService.signInWithEmail(
                  email: emailController.text.trim(),
                  password: passwordController.text,
                );
                if (mounted) {
                  setState(() {}); // Refresh UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Signed in successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sign in failed: $e'),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Sign In',
              style: TextStyle(color: AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog to create an account (links anonymous user to email/password)
  void _showCreateAccountDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create Account',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '✓ Your existing data will be kept',
              style: TextStyle(color: AppTheme.positiveColor, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              decoration: InputDecoration(
                hintText: 'Confirm Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Validate passwords match
              if (passwordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Passwords do not match'),
                    backgroundColor: AppTheme.negativeColor,
                  ),
                );
                return;
              }

              if (passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password must be at least 6 characters'),
                    backgroundColor: AppTheme.negativeColor,
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop();
              try {
                // Link anonymous account to email/password
                await AuthService.createAccount(
                  email: emailController.text.trim(),
                  password: passwordController.text,
                );
                if (mounted) {
                  setState(() {}); // Refresh UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Account created! Your data has been saved.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Account creation failed: $e'),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Create Account',
              style: TextStyle(color: AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// Show forgot password dialog - sends reset email
  void _showForgotPasswordDialog() {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your email address and we\'ll send you a link to reset your password.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter your email'),
                    backgroundColor: AppTheme.warningColor,
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop();
              try {
                await AuthService.sendPasswordResetEmail(email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset email sent! Check your inbox.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to send reset email: $e'),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Send Reset Link',
              style: TextStyle(color: AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// Show change password dialog - requires current password for re-authentication
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Change Password',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              decoration: InputDecoration(
                hintText: 'Current Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              decoration: InputDecoration(
                hintText: 'New Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              decoration: InputDecoration(
                hintText: 'Confirm New Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Validate
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('New passwords do not match'),
                    backgroundColor: AppTheme.negativeColor,
                  ),
                );
                return;
              }

              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password must be at least 6 characters'),
                    backgroundColor: AppTheme.negativeColor,
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop();
              try {
                // Re-authenticate first
                await AuthService.reauthenticate(
                  email: _userEmail!,
                  password: currentPasswordController.text,
                );

                // Update password
                await AuthService.updatePassword(newPasswordController.text);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password changed successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  String errorMessage = 'Failed to change password';
                  if (e.toString().contains('wrong-password')) {
                    errorMessage = 'Current password is incorrect';
                  } else if (e.toString().contains('requires-recent-login')) {
                    errorMessage = 'Please sign out and sign in again';
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Change Password',
              style: TextStyle(color: AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// Show delete account dialog - requires password confirmation
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.negativeColor),
            const SizedBox(width: 8),
            const Text(
              'Delete Account',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is permanent and cannot be undone.',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Deleting your account will:\n'
              '• Remove all your saved meals\n'
              '• Delete your settings and preferences\n'
              '• Remove all your data permanently',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showDeleteAccountConfirmDialog();
            },
            child: const Text(
              'Continue',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Show delete account confirmation dialog - requires password
  void _showDeleteAccountConfirmDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Account Deletion',
          style: TextStyle(color: AppTheme.negativeColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your password to confirm account deletion:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter your password'),
                    backgroundColor: AppTheme.warningColor,
                  ),
                );
                return;
              }

              Navigator.of(context).pop();
              try {
                // Re-authenticate first
                await AuthService.reauthenticate(
                  email: _userEmail!,
                  password: passwordController.text,
                );

                // Delete account
                await AuthService.deleteAccount();

                if (mounted) {
                  setState(() {}); // Refresh UI
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Account deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  String errorMessage = 'Failed to delete account';
                  if (e.toString().contains('wrong-password')) {
                    errorMessage = 'Incorrect password';
                  } else if (e.toString().contains('requires-recent-login')) {
                    errorMessage = 'Please sign out and sign in again';
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: AppTheme.negativeColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Delete Account',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ),
        ],
      ),
    );
  }
}
