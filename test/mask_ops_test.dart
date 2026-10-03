import 'dart:typed_data';

import 'package:cutout/features/segmentation/domain/mask_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [width] x [height] RGBA buffer where every pixel is [px].
Uint8List solid(int width, int height, List<int> px) {
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < out.length; i += 4) {
    out.setRange(i, i + 4, px);
  }
  return out;
}

const identityMean = [0.0, 0.0, 0.0];
const identityStd = [1.0, 1.0, 1.0];

void main() {
  group('preprocessRgba', () {
    test('produces a planar NCHW tensor of the target size', () {
      final input = solid(10, 6, [255, 0, 51, 255]);
      final out = preprocessRgba(
        input,
        10,
        6,
        targetSize: 4,
        mean: identityMean,
        std: identityStd,
      );
      expect(out.length, 3 * 4 * 4);
      expect(out.sublist(0, 16), everyElement(closeTo(1.0, 1e-6)));
      expect(out.sublist(16, 32), everyElement(closeTo(0.0, 1e-6)));
      expect(out.sublist(32, 48), everyElement(closeTo(0.2, 1e-6)));
    });

    test('applies (x - mean) / std per channel', () {
      final input = solid(2, 2, [128, 128, 128, 255]);
      final out = preprocessRgba(
        input,
        2,
        2,
        targetSize: 1,
        mean: const [0.485, 0.456, 0.406],
        std: const [0.229, 0.224, 0.225],
      );
      const v = 128 / 255;
      expect(out[0], closeTo((v - 0.485) / 0.229, 1e-5));
      expect(out[1], closeTo((v - 0.456) / 0.224, 1e-5));
      expect(out[2], closeTo((v - 0.406) / 0.225, 1e-5));
    });

    test('area-averages when shrinking instead of point sampling', () {
      // Columns alternate black and white; any point sample would be 0 or 1.
      final input = Uint8List(4 * 1 * 4);
      for (var x = 0; x < 4; x++) {
        final v = x.isEven ? 0 : 255;
        input.setRange(x * 4, x * 4 + 4, [v, v, v, 255]);
      }
      final out = preprocessRgba(
        input,
        4,
        1,
        targetSize: 2,
        mean: identityMean,
        std: identityStd,
      );
      // Each output pixel covers one black and one white column.
      expect(out.sublist(0, 4), everyElement(closeTo(0.5, 1e-6)));
    });

    test('handles images smaller than the target', () {
      final out = preprocessRgba(
        solid(1, 1, [0, 255, 0, 255]),
        1,
        1,
        targetSize: 3,
        mean: identityMean,
        std: identityStd,
      );
      expect(out.sublist(9, 18), everyElement(closeTo(1.0, 1e-6)));
    });

    test('rejects a buffer that does not match the dimensions', () {
      expect(
        () => preprocessRgba(
          Uint8List(10),
          2,
          2,
          targetSize: 2,
          mean: identityMean,
          std: identityStd,
        ),
        throwsArgumentError,
      );
    });
  });

  group('normalizeMask', () {
    test('minMax stretches the observed range to 0..1', () {
      final out = normalizeMask(
        Float32List.fromList([2, 4, 6]),
        MaskNormalization.minMax,
      );
      expect(out, [0.0, 0.5, 1.0]);
    });

    test('minMax on a flat mask clamps instead of dividing by zero', () {
      final out = normalizeMask(
        Float32List.fromList([0.7, 0.7]),
        MaskNormalization.minMax,
      );
      expect(out, everyElement(closeTo(0.7, 1e-6)));
      expect(out.any((v) => v.isNaN), isFalse);
    });

    test('sigmoid maps logits into 0..1', () {
      final out = normalizeMask(
        Float32List.fromList([-20, 0, 20]),
        MaskNormalization.sigmoid,
      );
      expect(out[0], closeTo(0, 1e-6));
      expect(out[1], closeTo(0.5, 1e-6));
      expect(out[2], closeTo(1, 1e-6));
    });

    test('clamp limits values to 0..1', () {
      final out = normalizeMask(
        Float32List.fromList([-1, 0.25, 3]),
        MaskNormalization.clamp,
      );
      expect(out, [0.0, 0.25, 1.0]);
    });
  });

  group('upscaleMask', () {
    test('a 1:1 resize returns the mask as bytes', () {
      final mask = Float32List.fromList([0, 0.5, 1, 0.25]);
      expect(upscaleMask(mask, 2, 2, 2, 2), [0, 128, 255, 64]);
    });

    test('a constant mask stays constant at any size', () {
      final mask = Float32List.fromList(List.filled(9, 0.6));
      final out = upscaleMask(mask, 3, 3, 17, 11);
      expect(out.length, 17 * 11);
      expect(out, everyElement(153));
    });

    test('interpolates smoothly between mask cells', () {
      // Left half background, right half foreground.
      final mask = Float32List.fromList([0, 1]);
      final out = upscaleMask(mask, 2, 1, 8, 1);
      expect(out.first, 0);
      expect(out.last, 255);
      for (var i = 1; i < out.length; i++) {
        expect(out[i], greaterThanOrEqualTo(out[i - 1]));
      }
      // Values strictly between 0 and 255 exist: a soft edge, not a step.
      expect(out.where((v) => v > 0 && v < 255), isNotEmpty);
    });

    test('supports non-uniform scaling (squashed model input)', () {
      final mask = Float32List.fromList([1, 0, 0, 0]); // only top-left on
      final out = upscaleMask(mask, 2, 2, 6, 2);
      expect(out[0], 255); // top-left corner
      expect(out[5], 0); // top-right corner
      expect(out[11], 0); // bottom-right corner
    });

    test('rejects a mask whose length does not match its size', () {
      expect(
        () => upscaleMask(Float32List(3), 2, 2, 4, 4),
        throwsArgumentError,
      );
    });
  });

  group('applyAlpha', () {
    test('sets alpha from the mask and keeps colour channels', () {
      final rgba = Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255]);
      final out = applyAlpha(rgba, Uint8List.fromList([0, 200]));
      expect(out, [10, 20, 30, 0, 40, 50, 60, 200]);
    });

    test('multiplies with existing transparency', () {
      final rgba = Uint8List.fromList([1, 2, 3, 128]);
      final out = applyAlpha(rgba, Uint8List.fromList([255]));
      expect(out[3], 128);
      final half = applyAlpha(rgba, Uint8List.fromList([128]));
      expect(half[3], 64);
    });

    test('does not modify the input buffer', () {
      final rgba = Uint8List.fromList([1, 2, 3, 255]);
      applyAlpha(rgba, Uint8List.fromList([0]));
      expect(rgba[3], 255);
    });

    test('rejects a mask with the wrong pixel count', () {
      expect(() => applyAlpha(Uint8List(8), Uint8List(3)), throwsArgumentError);
    });
  });

  group('compositeOverColor', () {
    const white = 0xFFFFFFFF;
    const black = 0xFF000000;
    const yellow = 0xFFFFD23F;

    test('opaque pixels are unchanged', () {
      final rgba = Uint8List.fromList([12, 34, 56, 255]);
      expect(compositeOverColor(rgba, black), rgba);
    });

    test('transparent pixels take the background colour', () {
      final rgba = Uint8List.fromList([12, 34, 56, 0]);
      expect(compositeOverColor(rgba, yellow), [0xFF, 0xD2, 0x3F, 255]);
    });

    test('half-transparent pixels blend evenly over an opaque colour', () {
      final rgba = Uint8List.fromList([0, 0, 0, 128]);
      final out = compositeOverColor(rgba, white);
      // 0 * 128/255 + 255 * 127/255 = 127
      expect(out, [127, 127, 127, 255]);
    });

    test('an opaque background always yields an opaque image', () {
      final rgba = Uint8List.fromList([
        for (var a = 0; a < 256; a += 15) ...[200, 100, 50, a],
      ]);
      final out = compositeOverColor(rgba, black);
      for (var i = 3; i < out.length; i += 4) {
        expect(out[i], 255);
      }
    });

    test('a transparent background returns the input unchanged', () {
      final rgba = Uint8List.fromList([12, 34, 56, 77, 1, 2, 3, 0]);
      final out = compositeOverColor(rgba, 0x00FFFFFF);
      expect(out, rgba);
      expect(identical(out, rgba), isFalse);
    });

    test('a translucent background follows Porter-Duff source-over', () {
      // Fully transparent source over 50% red: result is 50% red.
      final out = compositeOverColor(
        Uint8List.fromList([0, 0, 0, 0]),
        0x80FF0000,
      );
      expect(out, [255, 0, 0, 128]);

      // Half-opaque blue over half-opaque red: alpha = .5 + .5 * .5 = .75,
      // colour = (blue * .5 + red * .25) / .75.
      final mixed = compositeOverColor(
        Uint8List.fromList([0, 0, 255, 128]),
        0x80FF0000,
      );
      expect(mixed[3], closeTo(192, 1));
      expect(mixed[0], closeTo(85, 1));
      expect(mixed[2], closeTo(170, 1));
    });
  });

  test('full pipeline: mask → alpha → composite isolates the subject', () {
    // A 4x4 red image with a 2x2 mask marking only the left half as subject.
    final image = solid(4, 4, [255, 0, 0, 255]);
    final mask = normalizeMask(
      Float32List.fromList([5, -5, 5, -5]), // raw scores, not probabilities
      MaskNormalization.minMax,
    );
    final alpha = upscaleMask(mask, 2, 2, 4, 4);
    final cutout = applyAlpha(image, alpha);
    final onWhite = compositeOverColor(cutout, 0xFFFFFFFF);

    for (var y = 0; y < 4; y++) {
      final left = (y * 4) * 4;
      final right = (y * 4 + 3) * 4;
      expect(cutout[left + 3], 255, reason: 'subject stays opaque');
      expect(cutout[right + 3], 0, reason: 'background becomes clear');
      expect(onWhite.sublist(left, left + 4), [255, 0, 0, 255]);
      expect(onWhite.sublist(right, right + 4), [255, 255, 255, 255]);
    }
  });
}
