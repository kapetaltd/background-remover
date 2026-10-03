import 'package:flutter/material.dart';

import '../theme/cutout_colors.dart';

/// A green self-healing cutting mat: a fine grid with a heavier line every
/// fifth cell, like the printed guides on a real mat.
class CuttingMat extends StatelessWidget {
  const CuttingMat({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = CutoutTheme.of(context);
    return CustomPaint(painter: _MatPainter(theme), child: child);
  }
}

class _MatPainter extends CustomPainter {
  _MatPainter(this.theme);

  final CutoutTheme theme;
  static const cell = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.mat);
    final minor = Paint()
      ..color = theme.matLine
      ..strokeWidth = 1;
    final major = Paint()
      ..color = theme.matLineMajor
      ..strokeWidth = 1.5;
    var i = 0;
    for (var x = 0.0; x <= size.width; x += cell, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % 5 == 0 ? major : minor,
      );
    }
    i = 0;
    for (var y = 0.0; y <= size.height; y += cell, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % 5 == 0 ? major : minor,
      );
    }
  }

  @override
  bool shouldRepaint(_MatPainter old) => old.theme != theme;
}
