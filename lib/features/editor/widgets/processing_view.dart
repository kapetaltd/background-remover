import 'package:flutter/material.dart';

import '../../../core/theme/cutout_colors.dart';
import '../../segmentation/domain/segmentation_types.dart';

/// Shown while a cut runs: a blade travelling along a dashed line, the
/// current step, and a progress bar. Static when reduced motion is on.
class ProcessingView extends StatefulWidget {
  const ProcessingView({super.key, required this.stage});

  final SegmentationStage stage;

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView>
    with SingleTickerProviderStateMixin {
  late final _blade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blade
        ..stop()
        ..value = 0.5;
    } else if (!_blade.isAnimating) {
      _blade.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final percent = (widget.stage.progress * 100).round();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _blade,
                builder: (context, _) => CustomPaint(
                  painter: _BladeTrackPainter(
                    Curves.easeInOut.transform(_blade.value),
                    Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Removing background', style: text.headlineSmall),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              label: '${widget.stage.label}, $percent percent',
              excludeSemantics: true,
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.stage.progress),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 400),
                    builder: (context, value, _) =>
                        LinearProgressIndicator(value: value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.stage.label}…',
                          style: text.bodyLarge,
                        ),
                      ),
                      Text('$percent%', style: text.bodyLarge),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Processing on this device.',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BladeTrackPainter extends CustomPainter {
  _BladeTrackPainter(this.t, this.lineColor);

  final double t;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dash = Paint()
      ..color = lineColor
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, y), Offset(x + 8, y), dash);
    }
    // The cut so far: a solid yellow line up to the blade.
    final bx = 24 + (size.width - 48) * t;
    canvas.drawLine(
      Offset(0, y),
      Offset(bx, y),
      Paint()
        ..color = CutoutColors.bladeDeep
        ..strokeWidth = 3,
    );
    // Blade: a yellow trapezoid like a craft-knife tip.
    final blade = Path()
      ..moveTo(bx - 18, y - 16)
      ..lineTo(bx + 10, y - 16)
      ..lineTo(bx + 20, y)
      ..lineTo(bx - 18, y)
      ..close();
    canvas.drawPath(blade, Paint()..color = CutoutColors.blade);
    canvas.drawPath(
      blade,
      Paint()
        ..color = CutoutColors.onBlade
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BladeTrackPainter old) =>
      old.t != t || old.lineColor != lineColor;
}
