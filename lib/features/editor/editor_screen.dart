import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cutout_colors.dart';
import '../../core/widgets/cutting_mat.dart';
import '../export/export_service.dart';
import '../input/image_input_service.dart';
import 'editor_controller.dart';
import 'widgets/background_picker.dart';
import 'widgets/compare_slider.dart';
import 'widgets/processing_view.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller});

  final EditorController controller;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.warmUp();
  }

  Future<void> _export(ExportAction action, BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.of(context);
    Rect? origin;
    final box = buttonContext.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      final message = await _c.export(action, shareOrigin: origin);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on ExportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CallbackShortcuts(
      bindings: {
        if (_c.supportsClipboard) ...{
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
              _c.pick(ImageInputSource.clipboard),
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
              _c.pick(ImageInputSource.clipboard),
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: CuttingMat(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _WorkSurface(
                            child: ListenableBuilder(
                              listenable: _c,
                              builder: (context, _) => AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 250),
                                child: KeyedSubtree(
                                  key: ValueKey(_c.phase),
                                  child: switch (_c.phase) {
                                    EditorPhase.empty => _EmptyState(
                                      controller: _c,
                                    ),
                                    EditorPhase.processing => ProcessingView(
                                      stage: _c.stage,
                                    ),
                                    EditorPhase.ready => _ResultView(
                                      controller: _c,
                                      onExport: _export,
                                    ),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: CutoutColors.blade,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.content_cut,
              color: CutoutColors.onBlade,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cutout',
                  style: text.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Background removal that never leaves your device',
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkSurface extends StatelessWidget {
  const _WorkSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.error != null) ...[
                    _ErrorBanner(message: c.error!, onDismiss: c.clearError),
                    const SizedBox(height: 20),
                  ],
                  CustomPaint(
                    painter: _DashedFramePainter(scheme.outline),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 52,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cut out anything',
                    style: text.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a photo and Cutout lifts the subject off its '
                    'background. It all happens on this device; nothing is '
                    'uploaded.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => c.pick(ImageInputSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose a photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (c.supportsCamera)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => c.pick(ImageInputSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take photo'),
                          ),
                        ),
                      if (c.supportsCamera && c.supportsClipboard)
                        const SizedBox(width: 12),
                      if (c.supportsClipboard)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => c.pick(ImageInputSource.clipboard),
                            icon: const Icon(Icons.content_paste),
                            label: const Text('Paste'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.controller, required this.onExport});

  final EditorController controller;
  final Future<void> Function(ExportAction, BuildContext) onExport;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final result = c.result!;
    final preview = CompareSlider(
      original: result.original,
      cutout: result.cutout,
      background: c.background.color,
    );
    final controls = _Controls(controller: c, onExport: onExport);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: preview),
              const SizedBox(width: 20),
              SizedBox(
                width: 320,
                child: SingleChildScrollView(child: controls),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: preview),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.55,
              ),
              child: SingleChildScrollView(child: controls),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onExport});

  final EditorController controller;
  final Future<void> Function(ExportAction, BuildContext) onExport;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final busy = c.exporting != null;
    Widget spinnerOr(ExportAction action, IconData icon) =>
        c.exporting == action
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Icon(icon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BackgroundPicker(
          selected: c.background,
          customColor: c.customColor,
          onChanged: c.setBackground,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (bctx) => FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => onExport(ExportAction.save, bctx),
                  icon: spinnerOr(
                    ExportAction.save,
                    c.savesByDownload ? Icons.download : Icons.save_alt,
                  ),
                  label: Text(c.savesByDownload ? 'Download' : 'Save PNG'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Builder(
                builder: (bctx) => OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => onExport(ExportAction.share, bctx),
                  icon: spinnerOr(ExportAction.share, Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy ? null : c.reset,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('New photo'),
        ),
      ],
    );
  }
}

/// Dashed rounded square, echoing the cutting line.
class _DashedFramePainter extends CustomPainter {
  _DashedFramePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFramePainter old) => old.color != color;
}
