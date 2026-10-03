import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cutout_colors.dart';
import '../../../core/widgets/checkerboard.dart';

/// Before/after comparison: the original on the left of the handle, the
/// cutout (over [background], or a checkerboard when null) on the right.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.original,
    required this.cutout,
    required this.background,
    this.initialPosition = 0.5,
  });

  final ui.Image original;
  final ui.Image cutout;
  final Color? background;
  final double initialPosition;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  late double _position = widget.initialPosition;
  final _focusNode = FocusNode(debugLabel: 'compare-slider');
  bool _focused = false;

  static const _keyStep = 0.05;
  static const _handleSize = 52.0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setPosition(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next != _position) setState(() => _position = next);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.original.width / widget.original.height;
    final percent = (_position * 100).round();

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Semantics(
          slider: true,
          label: 'Before and after comparison',
          value: '$percent% original',
          increasedValue: '${(percent + 5).clamp(0, 100)}% original',
          decreasedValue: '${(percent - 5).clamp(0, 100)}% original',
          onIncrease: () => _setPosition(_position + _keyStep),
          onDecrease: () => _setPosition(_position - _keyStep),
          child: FocusableActionDetector(
            focusNode: _focusNode,
            onShowFocusHighlight: (v) => setState(() => _focused = v),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft): _NudgeIntent(-1),
              SingleActivator(LogicalKeyboardKey.arrowRight): _NudgeIntent(1),
            },
            actions: {
              _NudgeIntent: CallbackAction<_NudgeIntent>(
                onInvoke: (i) =>
                    _setPosition(_position + i.direction * _keyStep),
              ),
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void track(Offset local) => _setPosition(local.dx / width);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => track(d.localPosition),
                  onHorizontalDragStart: (d) => track(d.localPosition),
                  onHorizontalDragUpdate: (d) => track(d.localPosition),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ExcludeSemantics(
                          child: widget.background == null
                              ? const Checkerboard()
                              : ColoredBox(color: widget.background!),
                        ),
                        RawImage(
                          image: widget.cutout,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                        ClipRect(
                          clipper: _LeftClipper(_position),
                          child: RawImage(
                            image: widget.original,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const Positioned(
                          left: 10,
                          top: 10,
                          child: _CornerLabel('Before'),
                        ),
                        const Positioned(
                          right: 10,
                          top: 10,
                          child: _CornerLabel('After'),
                        ),
                        Positioned(
                          left: width * _position - _handleSize / 2,
                          top: 0,
                          bottom: 0,
                          width: _handleSize,
                          child: _Handle(focused: _focused),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.direction);
  final int direction;
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}

/// The cutting line: a dashed yellow/black rule with a round blade knob.
class _Handle extends StatelessWidget {
  const _Handle({required this.focused});

  final bool focused;

  @override
  Widget build(BuildContext context) {
    final theme = CutoutTheme.of(context);
    return ExcludeSemantics(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DashedLinePainter(theme.blade)),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.blade,
              shape: BoxShape.circle,
              border: Border.all(
                color: focused ? Colors.white : CutoutColors.onBlade,
                width: focused ? 3 : 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.content_cut, color: theme.onBlade, size: 22),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  static const dash = 9.0;
  static const gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    // A dark underlay keeps the line visible on both light and yellow images.
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = const Color(0x99000000)
        ..strokeWidth = 4,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dash), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

class _CornerLabel extends StatelessWidget {
  const _CornerLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC13201A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
