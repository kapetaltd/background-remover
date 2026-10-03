import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import '../domain/segmentation_model_config.dart';
import '../domain/segmentation_types.dart';
import 'segmentation_pipeline.dart';

/// Web has no Dart isolates for plugin code, so the pipeline runs on the main
/// thread. Inference itself is asynchronous in ONNX Runtime Web; the pixel
/// steps are synchronous, so the runner yields a frame between stages to let
/// the progress indicator paint.
class SegmentationRunner {
  SegmentationRunner._(this._pipeline);

  final SegmentationPipeline _pipeline;

  static Future<SegmentationRunner> start(
    SegmentationModelConfig config,
  ) async {
    try {
      final url = ui_web.assetManager.getAssetUrl(config.assetPath);
      final session = await openSession(config, url);
      return SegmentationRunner._(SegmentationPipeline(session, config));
    } catch (e) {
      throw SegmentationException(
        SegmentationErrorKind.modelUnavailable,
        'The background-removal model could not be loaded. $e',
      );
    }
  }

  Future<Uint8List> cut(
    RgbaImage image, {
    required void Function(SegmentationStage stage) onStage,
  }) {
    return _pipeline.cut(
      image,
      onStage: (stage) async {
        onStage(stage);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      },
    );
  }

  Future<void> dispose() async {}
}
