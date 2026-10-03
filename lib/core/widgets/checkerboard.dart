import 'package:flutter/material.dart';

import '../theme/cutout_colors.dart';

/// The classic transparency checkerboard.
class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key, this.cell = 12});

  final double cell;

  @override
  Widget build(BuildContext context) {
    final theme = CutoutTheme.of(context);
    return CustomPaint(
      painter: _CheckerPainter(theme.checkerA, theme.checkerB, cell),
      size: Size.infinite,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.a, this.b, this.cell);

  final Color a;
  final Color b;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final paint = Paint()..color = b;
    final path = Path();
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * cell < size.width; x += 2) {
        path.addRect(Rect.fromLTWH(x * cell, y * cell, cell, cell));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.a != a || old.b != b || old.cell != cell;
}
