import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart';

import '../export/export_service.dart';
import '../input/image_input_service.dart';
import '../segmentation/domain/segmentation_types.dart';
import '../segmentation/segmentation_service.dart';

/// The background shown behind the cutout and baked into the exported PNG.
@immutable
class BackgroundChoice {
  const BackgroundChoice._(this.color, this.label);

  const BackgroundChoice.custom(Color color) : this._(color, 'Custom');

  /// Null means transparent.
  final Color? color;
  final String label;

  bool get isTransparent => color == null;

  static const transparent = BackgroundChoice._(null, 'Transparent');
  static const white = BackgroundChoice._(Color(0xFFFFFFFF), 'White');
  static const black = BackgroundChoice._(Color(0xFF000000), 'Black');
  static const yellow = BackgroundChoice._(Color(0xFFFFD23F), 'Yellow');
  static const presets = [transparent, white, black, yellow];

  @override
  bool operator ==(Object other) =>
      other is BackgroundChoice && other.color == color && other.label == label;

  @override
  int get hashCode => Object.hash(color, label);
}

enum EditorPhase { empty, processing, ready }

enum ExportAction { save, share }

/// Drives the single-screen flow: pick → cut → choose background → export.
class EditorController extends ChangeNotifier {
  EditorController({
    required this._segmentation,
    required this._input,
    required this._export,
  });

  final SegmentationService _segmentation;
  final ImageInputService _input;
  final ExportService _export;

  EditorPhase _phase = EditorPhase.empty;
  EditorPhase get phase => _phase;

  SegmentationStage _stage = SegmentationStage.decoding;
  SegmentationStage get stage => _stage;

  CutResult? _result;
  CutResult? get result => _result;

  BackgroundChoice _background = BackgroundChoice.transparent;
  BackgroundChoice get background => _background;

  /// Last custom colour, so reopening the picker starts where the user left it.
  Color _customColor = const Color(0xFF4DA3FF);
  Color get customColor => _customColor;

  ExportAction? _exporting;
  ExportAction? get exporting => _exporting;

  String? _error;

  /// A user-facing message for the most recent pick or cut failure.
  String? get error => _error;

  bool get supportsCamera => _input.supportsCamera;
  bool get supportsClipboard => _input.supportsClipboard;
  bool get savesByDownload => _export.savesByDownload;

  var _generation = 0;
  var _disposed = false;

  /// Starts loading the model so the first cut is faster.
  void warmUp() {
    _segmentation.warmUp().catchError((Object e) {
      // Surfaced again, with a message, when the user makes a cut.
      debugPrint('Model warm-up failed: $e');
    });
  }

  Future<void> pick(ImageInputSource source) async {
    if (_phase == EditorPhase.processing) return;
    clearError();
    final Uint8List? bytes;
    try {
      bytes = await _input.pick(source);
    } on ImageInputException catch (e) {
      _setError(e.message);
      return;
    }
    if (bytes == null) return; // cancelled
    await cutImage(bytes);
  }

  /// Cuts the background out of [bytes], replacing any current result.
  Future<void> cutImage(Uint8List bytes) async {
    final generation = ++_generation;
    _replaceResult(null);
    _phase = EditorPhase.processing;
    _stage = SegmentationStage.decoding;
    _error = null;
    _notify();

    try {
      final result = await _segmentation.cut(
        bytes,
        onStage: (stage) {
          if (generation != _generation) return;
          _stage = stage;
          _notify();
        },
      );
      if (generation != _generation || _disposed) {
        result.dispose();
        return;
      }
      _replaceResult(result);
      _phase = EditorPhase.ready;
    } on SegmentationException catch (e) {
      if (generation != _generation) return;
      _phase = EditorPhase.empty;
      _error = e.message;
    } catch (e) {
      if (generation != _generation) return;
      _phase = EditorPhase.empty;
      _error = 'Something went wrong while removing the background ($e).';
    }
    _notify();
  }

  void setBackground(BackgroundChoice choice) {
    if (choice.label == 'Custom' && choice.color != null) {
      _customColor = choice.color!;
    }
    _background = choice;
    _notify();
  }

  /// Renders and saves or shares the PNG. Returns a confirmation message on
  /// success; throws [ExportException] on failure.
  Future<String?> export(ExportAction action, {Rect? shareOrigin}) async {
    final result = _result;
    if (result == null || _exporting != null) return null;
    _exporting = action;
    _notify();
    try {
      final png = await _export.renderPng(
        result.cutoutPixels,
        _background.color?.toARGB32(),
      );
      switch (action) {
        case ExportAction.save:
          await _export.saveToGallery(png);
          return savesByDownload ? 'PNG downloaded.' : 'Saved to your photos.';
        case ExportAction.share:
          await _export.share(png, origin: shareOrigin);
          return null;
      }
    } finally {
      _exporting = null;
      _notify();
    }
  }

  /// Back to the empty state for a new photo.
  void reset() {
    _generation++;
    _replaceResult(null);
    _phase = EditorPhase.empty;
    _error = null;
    _notify();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  void _setError(String message) {
    _error = message;
    _notify();
  }

  void _replaceResult(CutResult? next) {
    _result?.dispose();
    _result = next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _replaceResult(null);
    _segmentation.dispose();
    super.dispose();
  }
}
