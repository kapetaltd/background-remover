import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

enum ImageInputSource { gallery, camera, clipboard }

enum ImageInputErrorKind { permissionDenied, noCamera, clipboardEmpty, failed }

class ImageInputException implements Exception {
  const ImageInputException(this.kind, this.message);

  final ImageInputErrorKind kind;

  /// A sentence suitable for showing to the user.
  final String message;

  @override
  String toString() => 'ImageInputException(${kind.name}): $message';
}

/// Gets image bytes from the gallery, camera or clipboard.
class ImageInputService {
  ImageInputService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest edge requested from the picker. Large camera photos are scaled by
  /// the platform (which also normalises HEIC and EXIF rotation) to stay well
  /// under the decoder's pixel limit.
  static const maxPickedEdge = 5600.0;

  bool get supportsCamera => _picker.supportsImageSource(ImageSource.camera);

  /// Clipboard image reading exists on Android, iOS and web.
  bool get supportsClipboard =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Returns the chosen image's bytes, or null if the user cancelled.
  Future<Uint8List?> pick(ImageInputSource source) async {
    try {
      return await switch (source) {
        ImageInputSource.gallery => _pickWith(ImageSource.gallery),
        ImageInputSource.camera => _pickWith(ImageSource.camera),
        ImageInputSource.clipboard => _paste(),
      };
    } on ImageInputException {
      rethrow;
    } on PlatformException catch (e) {
      throw _fromPlatform(e, source);
    }
  }

  Future<Uint8List?> _pickWith(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxPickedEdge,
      maxHeight: maxPickedEdge,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }

  Future<Uint8List> _paste() async {
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) {
      throw const ImageInputException(
        ImageInputErrorKind.clipboardEmpty,
        'There is no image on the clipboard. Copy an image, then try again.',
      );
    }
    return bytes;
  }

  ImageInputException _fromPlatform(
    PlatformException e,
    ImageInputSource source,
  ) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return ImageInputException(
        ImageInputErrorKind.permissionDenied,
        source == ImageInputSource.camera
            ? 'Cutout needs camera access to take a photo. '
                  'You can allow it in Settings.'
            : 'Cutout needs access to your photos to open one. '
                  'You can allow it in Settings.',
      );
    }
    if (code.contains('no_available_camera') || code.contains('camera')) {
      return const ImageInputException(
        ImageInputErrorKind.noCamera,
        "This device doesn't have a camera Cutout can use.",
      );
    }
    return ImageInputException(
      ImageInputErrorKind.failed,
      'Couldn\'t open that image (${e.message ?? e.code}).',
    );
  }
}
