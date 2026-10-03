import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/editor/editor_controller.dart';
import 'features/editor/editor_screen.dart';
import 'features/export/export_service.dart';
import 'features/input/image_input_service.dart';
import 'features/segmentation/segmentation_service.dart';

class CutoutApp extends StatefulWidget {
  const CutoutApp({super.key, this.controller});

  /// Injected in tests; otherwise the app builds its own.
  final EditorController? controller;

  @override
  State<CutoutApp> createState() => _CutoutAppState();
}

class _CutoutAppState extends State<CutoutApp> {
  late final EditorController _controller =
      widget.controller ??
      EditorController(
        segmentation: SegmentationService(),
        input: ImageInputService(),
        export: ExportService(),
      );

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cutout',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: EditorScreen(controller: _controller),
    );
  }
}
