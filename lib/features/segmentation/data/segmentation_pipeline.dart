import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/mask_ops.dart';
import '../domain/segmentation_model_config.dart';
import '../domain/segmentation_types.dart';

/// Opens an ONNX Runtime session for [config] from [modelLocation]: a file
/// path on native platforms, or a URL on web.
Future<OrtSession> openSession(
  SegmentationModelConfig config,
  String modelLocation,
) async {
  return OnnxRuntime().createSession(
    modelLocation,
    options: OrtSessionOptions(providers: const [OrtProvider.CPU]),
  );
}

/// One full cut: pre-process, infer, then turn the low-res mask into alpha on
/// the full-resolution image. Shared by the isolate (native) and in-process
/// (web) runners.
class SegmentationPipeline {
  SegmentationPipeline(this._session, this._config);

  final OrtSession _session;
  final SegmentationModelConfig _config;

  Future<Uint8List> cut(
    RgbaImage image, {
    required Future<void> Function(SegmentationStage stage) onStage,
  }) async {
    final size = _config.inputSize;

    await onStage(SegmentationStage.preparing);
    final input = preprocessRgba(
      image.pixels,
      image.width,
      image.height,
      targetSize: size,
      mean: _config.mean,
      std: _config.std,
    );

    await onStage(SegmentationStage.inferring);
    final raw = await _infer(input, size);

    await onStage(SegmentationStage.refining);
    final mask = normalizeMask(raw, _config.normalization);
    final alpha = upscaleMask(mask, size, size, image.width, image.height);
    return applyAlpha(image.pixels, alpha);
  }

  Future<Float32List> _infer(Float32List input, int size) async {
    final inputName = _config.inputName ?? _session.inputNames.first;
    final tensor = await OrtValue.fromList(input, [1, 3, size, size]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({inputName: tensor});
      final output = outputs[_session.outputNames[_config.outputIndex]];
      if (output == null) {
        throw const SegmentationException(
          SegmentationErrorKind.modelUnavailable,
          'The model returned no mask.',
        );
      }
      final values = await output.asFlattenedList();
      if (values.length != size * size) {
        throw SegmentationException(
          SegmentationErrorKind.modelUnavailable,
          'The model returned ${values.length} mask values; expected ${size * size}.',
        );
      }
      final mask = Float32List(values.length);
      for (var i = 0; i < values.length; i++) {
        mask[i] = (values[i] as num).toDouble();
      }
      return mask;
    } finally {
      await tensor.dispose();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
    }
  }
}
