import 'mask_ops.dart';

/// Describes an ONNX salient-object / matting model so the pipeline can feed
/// it and read its output. To try another model, add a config here and point
/// [SegmentationModelConfig.active] at it (see the README).
class SegmentationModelConfig {
  const SegmentationModelConfig({
    required this.id,
    required this.assetPath,
    required this.inputSize,
    required this.mean,
    required this.std,
    this.inputName,
    this.outputIndex = 0,
    this.normalization = MaskNormalization.minMax,
  });

  /// Short identifier, also used to name the cached model file on device.
  final String id;

  /// Flutter asset key of the `.onnx` file.
  final String assetPath;

  /// Square input edge in pixels; the model takes `[1, 3, inputSize, inputSize]`.
  final int inputSize;

  /// Per-channel RGB normalisation applied to 0..1 pixel values.
  final List<double> mean;
  final List<double> std;

  /// Input tensor name, or null to use the model's first input.
  final String? inputName;

  /// Which output holds the mask. U²-Net's first output is the fused map.
  final int outputIndex;

  /// How raw output values become 0..1 alpha.
  final MaskNormalization normalization;

  /// U²-Net small variant (4.4 MB, Apache-2.0). Fast and good on clear
  /// subjects; edges are soft because the mask is predicted at 320 x 320.
  static const u2netp = SegmentationModelConfig(
    id: 'u2netp',
    assetPath: 'assets/models/u2netp.onnx',
    inputSize: 320,
    mean: [0.485, 0.456, 0.406],
    std: [0.229, 0.224, 0.225],
  );

  /// The model the app ships with.
  static const active = u2netp;
}
