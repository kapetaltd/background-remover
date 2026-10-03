import 'dart:math' as math;
import 'dart:typed_data';

/// Pure pixel operations used by the segmentation pipeline and export.
///
/// Everything here works on straight (non-premultiplied) RGBA8888 buffers,
/// row-major, 4 bytes per pixel, and has no Flutter dependencies so it can run
/// in any isolate and be unit tested directly.

/// Downsamples [rgba] to a [targetSize] x [targetSize] tensor in NCHW order,
/// normalised per channel as `(value / 255 - mean) / std`.
///
/// Uses area averaging, so shrinking a 12 MP photo to 320 x 320 does not alias
/// the way point or bilinear sampling would. The aspect ratio is not preserved;
/// salient-object models such as U²-Net are trained on squashed inputs and the
/// mask is stretched back to the original shape afterwards.
Float32List preprocessRgba(
  Uint8List rgba,
  int width,
  int height, {
  required int targetSize,
  required List<double> mean,
  required List<double> std,
}) {
  _checkRgba(rgba, width, height);
  final plane = targetSize * targetSize;
  final out = Float32List(3 * plane);
  final xStarts = _boxEdges(width, targetSize);
  final yStarts = _boxEdges(height, targetSize);

  for (var ty = 0; ty < targetSize; ty++) {
    final y0 = yStarts[ty];
    final y1 = math.max(y0 + 1, yStarts[ty + 1]);
    for (var tx = 0; tx < targetSize; tx++) {
      final x0 = xStarts[tx];
      final x1 = math.max(x0 + 1, xStarts[tx + 1]);
      var r = 0, g = 0, b = 0;
      for (var y = y0; y < y1; y++) {
        var i = (y * width + x0) * 4;
        for (var x = x0; x < x1; x++, i += 4) {
          r += rgba[i];
          g += rgba[i + 1];
          b += rgba[i + 2];
        }
      }
      final count = (y1 - y0) * (x1 - x0) * 255.0;
      final o = ty * targetSize + tx;
      out[o] = (r / count - mean[0]) / std[0];
      out[plane + o] = (g / count - mean[1]) / std[1];
      out[2 * plane + o] = (b / count - mean[2]) / std[2];
    }
  }
  return out;
}

/// How raw model output is mapped into the 0..1 range.
enum MaskNormalization {
  /// Stretch the observed min..max to 0..1 (what rembg does for U²-Net).
  minMax,

  /// Apply a logistic sigmoid, for models that output logits.
  sigmoid,

  /// Clamp to 0..1; for models that already output probabilities.
  clamp,
}

/// Returns a copy of [raw] mapped into 0..1 using [mode].
///
/// A flat min-max input (every value equal) has no contrast to stretch, so it
/// is clamped instead of dividing by zero.
Float32List normalizeMask(Float32List raw, MaskNormalization mode) {
  final out = Float32List(raw.length);
  switch (mode) {
    case MaskNormalization.minMax:
      var lo = double.infinity, hi = double.negativeInfinity;
      for (final v in raw) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      final range = hi - lo;
      if (range < 1e-6) return normalizeMask(raw, MaskNormalization.clamp);
      for (var i = 0; i < raw.length; i++) {
        out[i] = (raw[i] - lo) / range;
      }
    case MaskNormalization.sigmoid:
      for (var i = 0; i < raw.length; i++) {
        out[i] = 1 / (1 + math.exp(-raw[i]));
      }
    case MaskNormalization.clamp:
      for (var i = 0; i < raw.length; i++) {
        out[i] = raw[i].clamp(0.0, 1.0);
      }
  }
  return out;
}

/// Bilinearly resizes a 0..1 [mask] of [maskWidth] x [maskHeight] to an
/// 8-bit alpha plane of [width] x [height].
///
/// Sampling is pixel-centre aligned, so a 1:1 resize returns the input
/// unchanged and edges are clamped rather than wrapped.
Uint8List upscaleMask(
  Float32List mask,
  int maskWidth,
  int maskHeight,
  int width,
  int height,
) {
  if (mask.length != maskWidth * maskHeight) {
    throw ArgumentError.value(
      mask.length,
      'mask',
      'expected $maskWidth x $maskHeight values',
    );
  }
  final out = Uint8List(width * height);
  final sx = maskWidth / width;
  final sy = maskHeight / height;

  // Horizontal taps are the same for every row, so compute them once.
  final xLo = Int32List(width);
  final xHi = Int32List(width);
  final xT = Float32List(width);
  for (var x = 0; x < width; x++) {
    final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, maskWidth - 1.0);
    xLo[x] = fx.floor();
    xHi[x] = math.min(xLo[x] + 1, maskWidth - 1);
    xT[x] = fx - xLo[x];
  }

  for (var y = 0; y < height; y++) {
    final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, maskHeight - 1.0);
    final y0 = fy.floor();
    final y1 = math.min(y0 + 1, maskHeight - 1);
    final ty = fy - y0;
    final row0 = y0 * maskWidth;
    final row1 = y1 * maskWidth;
    final o = y * width;
    for (var x = 0; x < width; x++) {
      final t = xT[x];
      final top = mask[row0 + xLo[x]] * (1 - t) + mask[row0 + xHi[x]] * t;
      final bottom = mask[row1 + xLo[x]] * (1 - t) + mask[row1 + xHi[x]] * t;
      final v = top * (1 - ty) + bottom * ty;
      out[o + x] = (v * 255 + 0.5).clamp(0, 255).toInt();
    }
  }
  return out;
}

/// Returns a copy of [rgba] whose alpha is the product of its own alpha and
/// [alpha], so already-transparent pixels stay transparent.
Uint8List applyAlpha(Uint8List rgba, Uint8List alpha) {
  if (rgba.length != alpha.length * 4) {
    throw ArgumentError(
      'alpha has ${alpha.length} values but image has ${rgba.length ~/ 4} pixels',
    );
  }
  final out = Uint8List.fromList(rgba);
  for (var p = 0, i = 3; p < alpha.length; p++, i += 4) {
    out[i] = (out[i] * alpha[p] + 127) ~/ 255;
  }
  return out;
}

/// Composites [rgba] over a solid background with the Porter-Duff source-over
/// operator and returns straight-alpha RGBA.
///
/// [background] is `0xAARRGGBB`, as in `Color.toARGB32()`. An opaque
/// background yields an opaque image; a fully transparent one returns the
/// input unchanged.
Uint8List compositeOverColor(Uint8List rgba, int background) {
  final ba = (background >> 24) & 0xff;
  final br = (background >> 16) & 0xff;
  final bg = (background >> 8) & 0xff;
  final bb = background & 0xff;
  if (ba == 0) return Uint8List.fromList(rgba);

  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final sa = rgba[i + 3];
    if (sa == 255) {
      out[i] = rgba[i];
      out[i + 1] = rgba[i + 1];
      out[i + 2] = rgba[i + 2];
      out[i + 3] = 255;
      continue;
    }
    // Work in 0..255*255 fixed point: outA = sa + ba * (1 - sa).
    final bWeight = ba * (255 - sa); // background contribution, scaled by 255
    final outA255 = sa * 255 + bWeight;
    if (outA255 == 0) continue; // both transparent: leave zeros
    final half = outA255 ~/ 2;
    out[i] = (rgba[i] * sa * 255 + br * bWeight + half) ~/ outA255;
    out[i + 1] = (rgba[i + 1] * sa * 255 + bg * bWeight + half) ~/ outA255;
    out[i + 2] = (rgba[i + 2] * sa * 255 + bb * bWeight + half) ~/ outA255;
    out[i + 3] = (outA255 + 127) ~/ 255;
  }
  return out;
}

/// Box boundaries for shrinking [source] pixels into [target] boxes.
Int32List _boxEdges(int source, int target) {
  final edges = Int32List(target + 1);
  for (var i = 0; i <= target; i++) {
    edges[i] = math.min(source - 1, (i * source) ~/ target);
  }
  edges[target] = source;
  return edges;
}

void _checkRgba(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
    throw ArgumentError(
      'RGBA buffer of ${rgba.length} bytes does not match ${width}x$height',
    );
  }
}
