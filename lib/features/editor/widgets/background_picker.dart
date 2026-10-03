import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../../core/theme/cutout_colors.dart';
import '../../../core/widgets/checkerboard.dart';
import '../editor_controller.dart';

/// A row of background swatches: the presets plus a custom colour.
class BackgroundPicker extends StatelessWidget {
  const BackgroundPicker({
    super.key,
    required this.selected,
    required this.customColor,
    required this.onChanged,
  });

  final BackgroundChoice selected;
  final Color customColor;
  final ValueChanged<BackgroundChoice> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => _CustomColorDialog(initial: customColor),
    );
    if (color != null) onChanged(BackgroundChoice.custom(color));
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = selected.label == 'Custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Background', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final choice in BackgroundChoice.presets)
              _Swatch(
                label: choice.label,
                color: choice.color,
                selected: choice == selected,
                onTap: () => onChanged(choice),
              ),
            _Swatch(
              label: 'Custom',
              color: isCustom ? selected.color : null,
              rainbow: !isCustom,
              selected: isCustom,
              onTap: () => _pickCustom(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.rainbow = false,
  });

  final String label;
  final Color? color;
  final bool selected;
  final bool rainbow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget fill;
    if (rainbow) {
      fill = const DecoratedBox(
        decoration: BoxDecoration(
          gradient: SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
        ),
      );
    } else if (color == null) {
      fill = const Checkerboard(cell: 7);
    } else {
      fill = ColoredBox(color: color!);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '$label background',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? CutoutColors.bladeDeep
                          : scheme.outlineVariant,
                      width: selected ? 3 : 1.5,
                    ),
                  ),
                  child: ClipOval(child: fill),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});
  final Color initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom background'),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: _color,
          onColorChanged: (c) => setState(() => _color = c),
          enableAlpha: false,
          hexInputBar: true,
          labelTypes: const [],
          pickerAreaHeightPercent: 0.7,
          portraitOnly: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color.withValues(alpha: 1)),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}
