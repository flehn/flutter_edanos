import 'package:flutter/material.dart';

/// Custom painter for circular progress with rounded ends and dotted support.
///
/// Used by Goals screen and Meal Detail screen for macro progress rings.
class CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color backgroundColor;
  final double strokeWidth;
  final bool isDotted;

  CircleProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.backgroundColor,
    required this.strokeWidth,
    this.isDotted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    if (isDotted) {
      _drawDottedCircle(canvas, center, radius);
    } else {
      if (progress > 0) {
        final progressPaint = Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        const startAngle = -90 * 3.14159 / 180; // Start from top
        final sweepAngle = progress * 2 * 3.14159;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          progressPaint,
        );
      }
    }
  }

  void _drawDottedCircle(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dotCount = 20;
    const gapRatio = 0.9;

    const fullCircle = 2 * 3.14159;
    final segmentAngle = fullCircle / dotCount;
    final dotAngle = segmentAngle * (1 - gapRatio);

    const startAngle = -90 * 3.14159 / 180;

    for (int i = 0; i < dotCount; i++) {
      final angle = startAngle + (i * segmentAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dotAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.isDotted != isDotted;
  }
}
