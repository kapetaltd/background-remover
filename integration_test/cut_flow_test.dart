// End-to-end: real model, real background isolate, real UI.
//
//   flutter test integration_test -d <device>
//
// Optional (desktop): --dart-define=CUTOUT_FIXTURE=/path/photo.jpg to cut a
// real photo, and --dart-define=CUTOUT_OUT=/some/dir to write the cutout and
// a screenshot there.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cutout/app.dart';
import 'package:cutout/features/editor/editor_controller.dart';
import 'package:cutout/features/export/export_service.dart';
import 'package:cutout/features/input/image_input_service.dart';
import 'package:cutout/features/segmentation/segmentation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

const fixturePath = String.fromEnvironment('CUTOUT_FIXTURE');
const outDir = String.fromEnvironment('CUTOUT_OUT');

/// A dark red disc on a pale, slightly noisy backdrop: an unambiguous
/// salient object, so the test does not depend on a bundled photo.
Future<Uint8List> syntheticScene() async {
  const w = 900, h = 700;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w + 0.0, h + 0.0),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(w + 0.0, h + 0.0),
        [const Color(0xFFEFEFE8), const Color(0xFFD9DEE3)],
      ),
  );
  canvas.drawCircle(
    const Offset(w / 2, h / 2),
    210,
    Paint()..color = const Color(0xFF9E1B1B),
  );
  canvas.drawCircle(
    const Offset(w / 2 - 60, h / 2 - 70),
    50,
    Paint()..color = const Color(0xFFD94A3A),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

class FixtureInput extends ImageInputService {
  FixtureInput(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List?> pick(ImageInputSource source) async => bytes;
}

class RecordingExport extends ExportService {
  Uint8List? lastPng;

  @override
  Future<void> saveToGallery(Uint8List png) async => lastPng = png;
}

double alphaAt(Uint8List rgba, int width, double fx, double fy) {
  final height = rgba.length ~/ 4 ~/ width;
  final x = (fx * (width - 1)).round();
  final y = (fy * (height - 1)).round();
  return rgba[(y * width + x) * 4 + 3] / 255;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('a full cut runs on-device and exports a PNG', (tester) async {
    final bytes = fixturePath.isNotEmpty
        ? File(fixturePath).readAsBytesSync()
        : await syntheticScene();
    final export = RecordingExport();
    final controller = EditorController(
      segmentation: SegmentationService(),
      input: FixtureInput(bytes),
      export: export,
    );

    final sawStages = <String>{};
    controller.addListener(() {
      if (controller.phase == EditorPhase.processing) {
        sawStages.add(controller.stage.name);
      }
    });

    await tester.pumpWidget(CutoutApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));

    // While the cut runs, a periodic timer measures how late the UI isolate's
    // event loop is. If inference or mask work ran on the UI isolate, the
    // worst lag would be roughly the whole processing time.
    final watch = Stopwatch()..start();
    var lastTick = 0;
    var worstLagMs = 0;
    final lagTimer = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = watch.elapsedMilliseconds;
      final lag = now - lastTick - 8;
      if (lastTick > 0 && lag > worstLagMs) worstLagMs = lag;
      if (lag > 100) debugPrint('LAG ${lag}ms at stage=${controller.stage}');
      lastTick = now;
    });
    var last = watch.elapsedMilliseconds;
    var worstFrameGapMs = 0;
    while (controller.phase != EditorPhase.ready) {
      if (controller.error != null) fail('Cut failed: ${controller.error}');
      if (watch.elapsed > const Duration(minutes: 2)) fail('Cut timed out');
      await tester.pump(const Duration(milliseconds: 16));
      final now = watch.elapsedMilliseconds;
      if (now - last > worstFrameGapMs) worstFrameGapMs = now - last;
      last = now;
    }
    final cutMs = watch.elapsedMilliseconds;
    lagTimer.cancel();
    await tester.pumpAndSettle();

    final result = controller.result!;
    final px = result.cutoutPixels;
    debugPrint(
      'CUT ${px.width}x${px.height} in ${cutMs}ms; '
      'stages=$sawStages; worst event-loop lag ${worstLagMs}ms; '
      'worst frame gap ${worstFrameGapMs}ms',
    );
    expect(px.width, result.original.width);
    expect(px.height, result.original.height);
    expect(sawStages, contains('inferring'));

    // The mask must actually separate something: some clear and some solid.
    var clear = 0, solid = 0;
    for (var i = 3; i < px.pixels.length; i += 4) {
      if (px.pixels[i] < 16) clear++;
      if (px.pixels[i] > 240) solid++;
    }
    final total = px.width * px.height;
    debugPrint(
      'alpha: ${(100 * clear / total).toStringAsFixed(1)}% clear, '
      '${(100 * solid / total).toStringAsFixed(1)}% solid',
    );
    expect(clear / total, greaterThan(0.1));
    expect(solid / total, greaterThan(0.05));

    if (fixturePath.isEmpty) {
      expect(alphaAt(px.pixels, px.width, 0.5, 0.5), greaterThan(0.9));
      expect(alphaAt(px.pixels, px.width, 0.03, 0.03), lessThan(0.1));
      expect(alphaAt(px.pixels, px.width, 0.97, 0.97), lessThan(0.1));
    }
    expect(worstLagMs, lessThan(cutMs ~/ 2), reason: 'UI isolate was blocked');

    // Pick a background and export through the real compositor and encoder.
    await tester.tap(find.text('Yellow'));
    await tester.pump();
    await tester.tap(find.text('Save PNG'));
    for (var i = 0; i < 600 && export.lastPng == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final png = export.lastPng!;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    final exported = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      return (
        frame.image.width,
        frame.image.height,
        data!.buffer.asUint8List(),
      );
    });
    final (ew, eh, epx) = exported!;
    expect((ew, eh), (px.width, px.height));
    // Yellow background: a corner is opaque yellow.
    expect(epx.sublist(0, 4), [0xFF, 0xD2, 0x3F, 0xFF]);

    if (outDir.isNotEmpty) {
      await tester.pumpAndSettle();
      final transparent = await tester.runAsync(
        () => ExportService().renderPng(px, null),
      );
      File('$outDir/cutout.png').writeAsBytesSync(transparent!);
      File('$outDir/cutout_yellow.png').writeAsBytesSync(png);
      File('$outDir/alpha.raw').writeAsBytesSync([
        for (var i = 3; i < px.pixels.length; i += 4) px.pixels[i],
      ]);
      await _screenshot(tester, '$outDir/screen_result.png');
    }
    await tester.tap(find.text('New photo'));
    await tester.pumpAndSettle();
    expect(find.text('Cut out anything'), findsOneWidget);
  });
}

Future<void> _screenshot(WidgetTester tester, String path) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final bytes = await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
}
