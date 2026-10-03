import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/imaging/image_codec.dart';
import '../segmentation/domain/mask_ops.dart';
import '../segmentation/domain/segmentation_types.dart';
import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';

enum ExportErrorKind { permissionDenied, noSpace, failed }

class ExportException implements Exception {
  const ExportException(this.kind, this.message);

  final ExportErrorKind kind;

  /// A sentence suitable for showing to the user.
  final String message;

  @override
  String toString() => 'ExportException(${kind.name}): $message';
}

/// Renders the final PNG and hands it to the gallery or the share sheet.
class ExportService {
  /// Web can't write to a photo library, so "save" downloads the file instead.
  bool get savesByDownload => kIsWeb;

  /// Composites [cutout] over [background] (`0xAARRGGBB`, or null for
  /// transparent) and encodes it as PNG at full resolution.
  Future<Uint8List> renderPng(RgbaImage cutout, int? background) async {
    var pixels = cutout.pixels;
    if (background != null) {
      pixels = await compute(_composite, (cutout.pixels, background));
    }
    return encodePng(RgbaImage(pixels, cutout.width, cutout.height));
  }

  Future<void> saveToGallery(Uint8List png) async {
    final name = _fileName();
    if (savesByDownload) {
      downloadBytes(png, '$name.png', 'image/png');
      return;
    }
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw _denied;
      }
      await Gal.putImageBytes(png, name: name);
    } on GalException catch (e) {
      throw switch (e.type) {
        GalExceptionType.accessDenied => _denied,
        GalExceptionType.notEnoughSpace => const ExportException(
          ExportErrorKind.noSpace,
          "There isn't enough storage space to save this image.",
        ),
        _ => ExportException(
          ExportErrorKind.failed,
          "Couldn't save to your gallery (${e.type.name}).",
        ),
      };
    }
  }

  Future<void> share(Uint8List png, {Rect? origin}) async {
    final name = '${_fileName()}.png';
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png', name: name)],
          fileNameOverrides: [name],
          sharePositionOrigin: origin,
        ),
      );
    } on PlatformException catch (e) {
      throw ExportException(
        ExportErrorKind.failed,
        "Couldn't open the share sheet (${e.message ?? e.code}).",
      );
    }
  }

  static const _denied = ExportException(
    ExportErrorKind.permissionDenied,
    'Cutout needs permission to add photos to your library. '
    'You can allow it in Settings.',
  );

  static String _fileName() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'cutout_${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

Uint8List _composite((Uint8List, int) args) =>
    compositeOverColor(args.$1, args.$2);
