import 'dart:typed_data';

/// Steps of a cut, in order, for progress reporting.
enum SegmentationStage {
  decoding('Reading image', 0.05),
  preparing('Preparing pixels', 0.2),
  inferring('Finding the subject', 0.35),
  refining('Cutting along the edge', 0.8),
  finishing('Finishing up', 0.95);

  const SegmentationStage(this.label, this.progress);

  /// Short user-facing description.
  final String label;

  /// Approximate overall progress (0..1) when this stage starts.
  final double progress;
}

/// Why a cut failed, so the UI can show a specific message.
enum SegmentationErrorKind {
  tooLarge,
  unreadable,
  modelUnavailable,
  outOfMemory,
  unknown,
}

class SegmentationException implements Exception {
  const SegmentationException(this.kind, this.message);

  final SegmentationErrorKind kind;

  /// A sentence suitable for showing to the user.
  final String message;

  @override
  String toString() => 'SegmentationException(${kind.name}): $message';
}

/// Raw straight-alpha RGBA pixels plus their dimensions.
class RgbaImage {
  RgbaImage(this.pixels, this.width, this.height)
    : assert(pixels.length == width * height * 4);

  final Uint8List pixels;
  final int width;
  final int height;
}
