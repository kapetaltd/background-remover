import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/imaging/image_codec.dart';
import 'data/segmentation_runner_io.dart'
    if (dart.library.js_interop) 'data/segmentation_runner_web.dart';
import 'domain/segmentation_model_config.dart';
import 'domain/segmentation_types.dart';

/// The result of a cut: the original and the cutout, both at full resolution.
class CutResult {
  CutResult({
    required this.original,
    required this.cutout,
    required this.cutoutPixels,
  });

  final ui.Image original;

  /// The original with the background made transparent.
  final ui.Image cutout;

  /// Straight-alpha pixels of [cutout], used for export.
  final RgbaImage cutoutPixels;

  void dispose() {
    original.dispose();
    cutout.dispose();
  }
}

/// On-device background removal. Images never leave the device: decoding uses
/// the platform's codecs and inference runs locally with ONNX Runtime.
class SegmentationService {
  SegmentationService({this.config = SegmentationModelConfig.active});

  final SegmentationModelConfig config;
  Future<SegmentationRunner>? _runner;

  /// Loads the model ahead of the first cut. Safe to call more than once.
  Future<void> warmUp() async {
    await _ensureRunner();
  }

  /// Removes the background from the encoded image in [bytes].
  ///
  /// Throws [SegmentationException] with a user-facing message on failure.
  Future<CutResult> cut(
    Uint8List bytes, {
    void Function(SegmentationStage stage)? onStage,
  }) async {
    onStage?.call(SegmentationStage.decoding);
    final runnerFuture = _ensureRunner();
    final decoded = await decodeImage(bytes);
    try {
      final runner = await runnerFuture;
      final cutoutPixels = await runner.cut(
        decoded.rgba,
        onStage: (stage) => onStage?.call(stage),
      );
      onStage?.call(SegmentationStage.finishing);
      final rgba = RgbaImage(
        cutoutPixels,
        decoded.rgba.width,
        decoded.rgba.height,
      );
      final cutout = await imageFromRgba(rgba);
      return CutResult(
        original: decoded.image,
        cutout: cutout,
        cutoutPixels: rgba,
      );
    } on OutOfMemoryError {
      decoded.image.dispose();
      throw const SegmentationException(
        SegmentationErrorKind.outOfMemory,
        'Your device ran out of memory on this image. Try a smaller photo.',
      );
    } catch (_) {
      decoded.image.dispose();
      rethrow;
    }
  }

  Future<SegmentationRunner> _ensureRunner() {
    final existing = _runner;
    if (existing != null) return existing;
    final started = SegmentationRunner.start(config);
    _runner = started;
    // Allow a retry if loading failed (e.g. low memory at launch).
    started.then<void>((_) {}, onError: (Object _) => _runner = null);
    return started;
  }

  Future<void> dispose() async {
    final runner = _runner;
    _runner = null;
    if (runner != null) await (await runner).dispose();
  }
}
