import 'package:cutout/core/theme/app_theme.dart';
import 'package:cutout/features/editor/widgets/processing_view.dart';
import 'package:cutout/features/segmentation/domain/segmentation_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget host(Widget child, {bool reduceMotion = false, bool dark = false}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('processing view is static when reduced motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ProcessingView(stage: SegmentationStage.inferring),
        reduceMotion: true,
      ),
    );
    // A repeating animation would make this time out.
    await tester.pumpAndSettle();
    expect(find.text('35%'), findsOneWidget);
  });

  testWidgets('processing view animates the blade otherwise', (tester) async {
    await tester.pumpWidget(
      host(const ProcessingView(stage: SegmentationStage.inferring)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('progress is announced as a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const ProcessingView(stage: SegmentationStage.refining)),
    );
    expect(
      find.bySemanticsLabel('Cutting along the edge, 80 percent'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('dark theme keeps text readable', (tester) async {
    await tester.pumpWidget(
      host(
        const ProcessingView(stage: SegmentationStage.preparing),
        dark: true,
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
