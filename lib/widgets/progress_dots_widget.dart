import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/progress_service.dart';

/// A compact progress bar showing 20 dots for the 20-day cycle.
/// Active days are filled, inactive days are hollow.
/// Shows countdown text and an info icon.
class ProgressDotsWidget extends StatefulWidget {
  const ProgressDotsWidget({super.key});

  @override
  State<ProgressDotsWidget> createState() => ProgressDotsWidgetState();
}

class ProgressDotsWidgetState extends State<ProgressDotsWidget> {
  ProgressSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isEvaluating = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  /// Public method to refresh from outside.
  void refresh() => _loadProgress();

  Future<void> _loadProgress() async {
    try {
      final snapshot = await ProgressService.computeSnapshot();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading progress: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runEvaluation() async {
    if (_isEvaluating) return;
    setState(() => _isEvaluating = true);

    try {
      final result = await ProgressService.runProgressEvaluation(
        onRetry: (attempt, max) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Currently High Demand, retrying... ($attempt/$max)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      );
      if (mounted && result != null) {
        await _loadProgress();
        _showEvaluationDialog(result);
      }
    } catch (e) {
      debugPrint('Error running progress evaluation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get progress evaluation: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isEvaluating = false);
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Progress Feedback',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
        ),
        content: const Text(
          'You\'ll receive detailed AI feedback on your nutrition progress based on the goals you defined after 20 days.\n\n'
          'To unlock the evaluation, use the app for at least 18 out of 20 consecutive days. '
          'Each dot represents one day — filled dots mean you scanned at least one meal that day.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showEvaluationDialog(Map<String, dynamic> evaluation) {
    final score = (evaluation['progressScore'] as num?)?.toInt() ?? 5;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Text(
              '20-Day Progress',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _scoreColor(score).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _scoreColor(score)),
              ),
              child: Text(
                '$score/10',
                style: TextStyle(
                  color: _scoreColor(score),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (evaluation['overallProgress'] != null) ...[
                _buildSection(Icons.analytics, 'Overall', evaluation['overallProgress'], AppTheme.primaryBlue),
                const SizedBox(height: 16),
              ],
              if (evaluation['strengths'] != null) ...[
                _buildSection(Icons.check_circle, 'Strengths', evaluation['strengths'], AppTheme.positiveColor),
                const SizedBox(height: 16),
              ],
              if (evaluation['improvements'] != null) ...[
                _buildSection(Icons.trending_up, 'Improvements', evaluation['improvements'], AppTheme.warningColor),
                const SizedBox(height: 16),
              ],
              if (evaluation['mealTimingFeedback'] != null)
                _buildSection(Icons.schedule, 'Meal Timing', evaluation['mealTimingFeedback'], AppTheme.textSecondary),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(IconData icon, String title, String content, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Color _scoreColor(int score) {
    if (score >= 8) return AppTheme.positiveColor;
    if (score >= 5) return AppTheme.warningColor;
    return AppTheme.negativeColor;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _snapshot == null) {
      return const SizedBox.shrink();
    }

    final snap = _snapshot!;

    // Don't show if no cycle started yet
    if (snap.cycleStartDate == null) {
      return const SizedBox.shrink();
    }

    final canGenerate = snap.isEligibleForEvaluation;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with remaining days
          Text(
            'Feedback in ${20 - snap.totalDaysInCycle} days',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 8),
          // Dots row
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(20, (index) {
              final isActive = snap.activeDayFlags[index];
              final isPast = index < snap.totalDaysInCycle;
              final isToday = index == snap.totalDaysInCycle - 1;

              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppTheme.primaryBlue
                      : (isPast ? AppTheme.textTertiary.withOpacity(0.3) : Colors.transparent),
                  border: Border.all(
                    color: isToday
                        ? AppTheme.primaryBlue
                        : (isActive
                            ? AppTheme.primaryBlue
                            : AppTheme.textTertiary.withOpacity(0.4)),
                    width: isToday ? 2 : 1,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          // Bottom row: More info (left) + Get report (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _showInfoDialog,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppTheme.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'More info',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: canGenerate ? _runEvaluation : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: canGenerate
                        ? AppTheme.primaryBlue
                        : AppTheme.primaryBlue.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isEvaluating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Generate report',
                          style: TextStyle(
                            color: canGenerate
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
