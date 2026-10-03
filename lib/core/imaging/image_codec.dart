import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../features/segmentation/domain/segmentation_types.dart';

/// Upper bounds for input images. A 32 MP cut holds the original, the cutout
/// and a mask in memory at once (~280 MB), which is about as far as mid-range
/// phones go comfortably.
const maxInputPixels = 32 * 1000 * 1000;
const maxInputBytes = 60 * 1024 * 1024;

/// A decoded image as both a drawable [ui.Image] and raw RGBA pixels.
class DecodedImage {
  DecodedImage(this.image, this.rgba);
  final ui.Image image;
  final RgbaImage rgba;
}

/// Decodes [bytes] (JPEG, PNG, WebP, GIF, BMP, and HEIC where the platform
/// supports it) with the engine's native codecs, which run off the UI thread
/// and apply EXIF orientation. Size limits are checked from the header before
/// any pixels are decoded.
Future<DecodedImage> decodeImage(Uint8List bytes) async {
  if (bytes.lengthInBytes > maxInputBytes) {
    throw SegmentationException(
      SegmentationErrorKind.tooLarge,
      'That file is ${_mb(bytes.lengthInBytes)} MB. '
      'Cutout handles files up to ${_mb(maxInputBytes)} MB.',
    );
  }

  final ui.Codec codec;
  try {
    codec = await _codecFor(bytes);
  } on SegmentationException {
    rethrow;
  } catch (_) {
    throw const SegmentationException(
      SegmentationErrorKind.unreadable,
      "That file isn't an image Cutout can read. Try a JPEG, PNG or WebP.",
    );
  }

  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      _checkPixelCount(image.width, image.height);
    } catch (_) {
      image.dispose();
      rethrow;
    }
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      image.dispose();
      throw const SegmentationException(
        SegmentationErrorKind.unreadable,
        "Cutout couldn't read the pixels in that image.",
      );
    }
    return DecodedImage(
      image,
      RgbaImage(data.buffer.asUint8List(), image.width, image.height),
    );
  } on SegmentationException {
    rethrow;
  } catch (e) {
    throw SegmentationException(
      SegmentationErrorKind.unreadable,
      "Cutout couldn't decode that image ($e).",
    );
  } finally {
    codec.dispose();
  }
}

/// On native platforms the header is read first so oversized images are
/// rejected before any pixels are decoded. Web's decoder doesn't expose the
/// header, so there the size is checked after decoding.
Future<ui.Codec> _codecFor(Uint8List bytes) async {
  if (kIsWeb) return ui.instantiateImageCodec(bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    // As in dart:ui's own instantiateImageCodecWithSize, the descriptor is
    // not disposed here: the codec still needs it to decode frames.
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    _checkPixelCount(descriptor.width, descriptor.height);
    return await descriptor.instantiateCodec();
  } finally {
    buffer.dispose();
  }
}

/// Wraps straight-alpha RGBA pixels in a drawable [ui.Image].
Future<ui.Image> imageFromRgba(RgbaImage rgba) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba.pixels,
    rgba.width,
    rgba.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Encodes RGBA pixels as PNG using the engine's encoder.
Future<Uint8List> encodePng(RgbaImage rgba) async {
  final image = await imageFromRgba(rgba);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding returned no data');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void _checkPixelCount(int width, int height) {
  final pixels = width * height;
  if (pixels > maxInputPixels) {
    throw SegmentationException(
      SegmentationErrorKind.tooLarge,
      'That image is $width x $height (${(pixels / 1e6).toStringAsFixed(0)} MP). '
      'Cutout handles up to ${maxInputPixels ~/ 1000000} MP. '
      'Try a smaller or cropped copy.',
    );
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
