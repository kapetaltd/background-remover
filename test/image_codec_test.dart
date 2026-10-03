import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cutout/core/imaging/image_codec.dart';
import 'package:cutout/features/segmentation/domain/segmentation_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PNG that declares [width] x [height] in its header but carries only a
/// token of pixel data: enough for the decoder to read the size, never enough
/// to decode. Proves oversized images are rejected before decoding.
Uint8List pngHeaderOnly(int width, int height) {
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // RGBA
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    ..._chunk('IHDR', ihdr.buffer.asUint8List()),
    ..._chunk('IDAT', [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return [...length.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List()];
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

Matcher throwsSegmentation(SegmentationErrorKind kind, String text) => throwsA(
  isA<SegmentationException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rejects an oversized image from its header alone', () async {
    await expectLater(
      decodeImage(pngHeaderOnly(9000, 6000)),
      throwsSegmentation(SegmentationErrorKind.tooLarge, '54 MP'),
    );
  });

  test('rejects files over the byte limit before decoding', () async {
    await expectLater(
      decodeImage(Uint8List(maxInputBytes + 1)),
      throwsSegmentation(SegmentationErrorKind.tooLarge, 'MB'),
    );
  });

  test('reports non-image data as unreadable', () async {
    await expectLater(
      decodeImage(Uint8List.fromList('not an image'.codeUnits)),
      throwsSegmentation(SegmentationErrorKind.unreadable, 'JPEG, PNG'),
    );
  });

  test('round-trips straight alpha through PNG encode and decode', () async {
    final pixels = Uint8List.fromList([
      255, 0, 0, 255, //
      0, 255, 0, 128,
      0, 0, 255, 0,
      10, 20, 30, 255,
    ]);
    final png = await encodePng(RgbaImage(pixels, 2, 2));
    final decoded = await decodeImage(png);
    expect(decoded.rgba.width, 2);
    expect(decoded.rgba.height, 2);
    final out = decoded.rgba.pixels;
    expect(out.sublist(0, 4), [255, 0, 0, 255]);
    expect(out[7], 128); // half alpha survives
    expect(out[4], 0);
    expect(out[5], closeTo(255, 1)); // straight colour, not premultiplied
    expect(out[11], 0);
    expect(out.sublist(12, 16), [10, 20, 30, 255]);
    expect(decoded.image, isA<ui.Image>());
    decoded.image.dispose();
  });
}
