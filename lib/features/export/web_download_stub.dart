import 'dart:typed_data';

/// Only used on web; native platforms save through the gallery.
void downloadBytes(Uint8List bytes, String fileName, String mimeType) {
  throw UnsupportedError('Downloads are only available on web.');
}
