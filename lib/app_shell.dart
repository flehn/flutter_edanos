import 'package:flutter/material.dart';
import 'screens/food_log_screen.dart';
import 'screens/add_food_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/settings_screen.dart';

/// Main app shell with bottom navigation
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  // Keys to access screen states for refresh
  final _foodLogKey = GlobalKey<FoodLogScreenState>();
  final _addFoodKey = GlobalKey<AddFoodScreenState>();
  final _goalsKey = GlobalKey<GoalsScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      FoodLogScreen(key: _foodLogKey),
      AddFoodScreen(key: _addFoodKey),
      GoalsScreen(key: _goalsKey),
      const SettingsScreen(),
    ];
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
    
    // Refresh data when switching to certain tabs
    if (index == 0) {
      // Food Log tab - refresh meals
      _foodLogKey.currentState?.refresh();
    } else if (index == 1) {
      // Add Food tab - refresh quick add items
      _addFoodKey.currentState?.refresh();
    } else if (index == 2) {
      // Goals tab - refresh progress
      _goalsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted),
              activeIcon: Icon(Icons.format_list_bulleted),
              label: 'Food Log',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Add Food',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.track_changes_outlined),
              activeIcon: Icon(Icons.track_changes),
              label: 'Goals',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
