import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cutout/app.dart';
import 'package:cutout/features/editor/editor_controller.dart';
import 'package:cutout/features/export/export_service.dart';
import 'package:cutout/features/input/image_input_service.dart';
import 'package:cutout/features/segmentation/domain/segmentation_types.dart';
import 'package:cutout/features/segmentation/segmentation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<ui.Image> _image(int w, int h, Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  return recorder.endRecording().toImage(w, h);
}

class FakeSegmentation extends SegmentationService {
  Object? failWith;
  int cuts = 0;

  @override
  Future<void> warmUp() async {}

  @override
  Future<CutResult> cut(
    Uint8List bytes, {
    void Function(SegmentationStage stage)? onStage,
  }) async {
    cuts++;
    onStage?.call(SegmentationStage.inferring);
    if (failWith != null) throw failWith!;
    return CutResult(
      original: await _image(40, 30, Colors.red),
      cutout: await _image(40, 30, Colors.blue),
      cutoutPixels: RgbaImage(Uint8List(40 * 30 * 4), 40, 30),
    );
  }

  @override
  Future<void> dispose() async {}
}

class FakeInput extends ImageInputService {
  Uint8List? next = Uint8List.fromList([1, 2, 3]);
  ImageInputException? failWith;

  @override
  bool get supportsCamera => true;

  @override
  bool get supportsClipboard => true;

  @override
  Future<Uint8List?> pick(ImageInputSource source) async {
    if (failWith != null) throw failWith!;
    return next;
  }
}

class FakeExport extends ExportService {
  final saved = <int?>[];

  @override
  Future<Uint8List> renderPng(RgbaImage cutout, int? background) async {
    saved.add(background);
    return Uint8List(0);
  }

  @override
  Future<void> saveToGallery(Uint8List png) async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeSegmentation segmentation;
  late FakeInput input;
  late FakeExport export;
  late EditorController controller;

  setUp(() {
    segmentation = FakeSegmentation();
    input = FakeInput();
    export = FakeExport();
    controller = EditorController(
      segmentation: segmentation,
      input: input,
      export: export,
    );
  });

  group('EditorController', () {
    test('a cancelled pick leaves the editor empty', () async {
      input.next = null;
      await controller.pick(ImageInputSource.gallery);
      expect(controller.phase, EditorPhase.empty);
      expect(segmentation.cuts, 0);
      expect(controller.error, isNull);
    });

    test('a successful cut moves to ready', () async {
      await controller.pick(ImageInputSource.gallery);
      expect(controller.phase, EditorPhase.ready);
      expect(controller.result, isNotNull);
    });

    test('a permission error is shown to the user', () async {
      input.failWith = const ImageInputException(
        ImageInputErrorKind.permissionDenied,
        'Cutout needs camera access.',
      );
      await controller.pick(ImageInputSource.camera);
      expect(controller.phase, EditorPhase.empty);
      expect(controller.error, 'Cutout needs camera access.');
    });

    test('a too-large image returns to empty with its message', () async {
      segmentation.failWith = const SegmentationException(
        SegmentationErrorKind.tooLarge,
        'That image is too large.',
      );
      await controller.pick(ImageInputSource.gallery);
      expect(controller.phase, EditorPhase.empty);
      expect(controller.error, 'That image is too large.');
    });

    test('export bakes in the chosen background', () async {
      await controller.pick(ImageInputSource.gallery);
      await controller.export(ExportAction.save);
      controller.setBackground(BackgroundChoice.yellow);
      await controller.export(ExportAction.save);
      controller.setBackground(
        const BackgroundChoice.custom(Color(0xFF123456)),
      );
      await controller.export(ExportAction.save);
      expect(export.saved, [null, 0xFFFFD23F, 0xFF123456]);
      expect(controller.customColor, const Color(0xFF123456));
    });

    test('reset clears the result', () async {
      await controller.pick(ImageInputSource.gallery);
      controller.reset();
      expect(controller.phase, EditorPhase.empty);
      expect(controller.result, isNull);
    });
  });

  group('EditorScreen', () {
    testWidgets('empty state offers gallery, camera and paste', (tester) async {
      await tester.pumpWidget(CutoutApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Cut out anything'), findsOneWidget);
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('picking shows the compare view and background options', (
      tester,
    ) async {
      await tester.pumpWidget(CutoutApp(controller: controller));
      await tester.runAsync(() => controller.pick(ImageInputSource.gallery));
      await tester.pumpAndSettle();

      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      for (final label in [
        'Transparent',
        'White',
        'Black',
        'Yellow',
        'Custom',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Save PNG'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.text('Black'));
      await tester.pump();
      expect(controller.background, BackgroundChoice.black);

      await tester.tap(find.text('New photo'));
      await tester.pumpAndSettle();
      expect(find.text('Cut out anything'), findsOneWidget);
    });

    testWidgets('errors are announced in a banner', (tester) async {
      input.failWith = const ImageInputException(
        ImageInputErrorKind.permissionDenied,
        'Cutout needs access to your photos.',
      );
      await tester.pumpWidget(CutoutApp(controller: controller));
      await tester.tap(find.text('Choose a photo'));
      await tester.pumpAndSettle();
      expect(find.text('Cutout needs access to your photos.'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Cutout needs access to your photos.'), findsNothing);
    });

    testWidgets('the compare slider responds to drags and has semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(CutoutApp(controller: controller));
      await tester.runAsync(() => controller.pick(ImageInputSource.gallery));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Before and after comparison'),
        ),
        matchesSemantics(
          label: 'Before and after comparison',
          value: '50% original',
          increasedValue: '55% original',
          decreasedValue: '45% original',
          isSlider: true,
          isFocusable: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
          hasTapAction: true,
          hasFocusAction: true,
          // From the horizontal drag recogniser.
          hasScrollLeftAction: true,
          hasScrollRightAction: true,
        ),
      );

      final slider = find.bySemanticsLabel('Before and after comparison');
      final box = tester.getRect(slider);
      await tester.dragFrom(box.center, Offset(-box.width * 0.4, 0));
      await tester.pump();
      final value = tester.getSemantics(slider).value;
      expect(int.parse(value.split('%').first), lessThan(20));
      handle.dispose();
    });

    testWidgets('all tap targets meet the 48dp guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(CutoutApp(controller: controller));
      await tester.runAsync(() => controller.pick(ImageInputSource.gallery));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
