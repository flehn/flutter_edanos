import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_edanos/theme/app_theme.dart';

void main() {
  testWidgets('EdanosAI theme is dark', (WidgetTester tester) async {
    // Verify the app theme is configured correctly
    final theme = AppTheme.darkTheme;
    expect(theme.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp renders with EdanosAI theme', (WidgetTester tester) async {
    // Build a minimal MaterialApp with the app's theme to verify it works
    await tester.pumpWidget(
      MaterialApp(
        title: 'EdanosAI Food Analyzer',
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: Text('EdanosAI')),
        ),
      ),
    );

    expect(find.text('EdanosAI'), findsOneWidget);
  });
}
