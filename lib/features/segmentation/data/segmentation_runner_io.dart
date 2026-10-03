import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/segmentation_model_config.dart';
import '../domain/segmentation_types.dart';
import 'segmentation_pipeline.dart';

/// Runs the pipeline in a long-lived background isolate that owns the ONNX
/// session, so pre-processing, inference and mask compositing never touch the
/// UI isolate. Pixel buffers cross the isolate boundary as
/// [TransferableTypedData], which moves them without copying.
class SegmentationRunner {
  SegmentationRunner._(this._isolate, this._commands, this._responses);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final _jobs = <int, _PendingJob>{};
  var _nextId = 0;

  static Future<SegmentationRunner> start(
    SegmentationModelConfig config,
  ) async {
    final modelPath = await _extractModel(config);
    final responses = ReceivePort('cutout-segmentation');

    // The worker replies with its command port, then with null (ready) or an
    // error message if the model could not be loaded; after that, job updates.
    final commandPort = Completer<SendPort>();
    final loaded = Completer<Object?>();
    SegmentationRunner? runner;
    responses.listen((message) {
      if (runner != null) {
        runner._onResponse(message);
      } else if (!commandPort.isCompleted) {
        commandPort.complete(message! as SendPort);
      } else if (!loaded.isCompleted) {
        loaded.complete(message);
      }
    });

    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerArgs(
        responses.sendPort,
        RootIsolateToken.instance!,
        config,
        modelPath,
      ),
      debugName: 'cutout-segmentation',
      paused: true,
    );
    isolate.addOnExitListener(responses.sendPort, response: _workerExited);
    isolate.resume(isolate.pauseCapability!);
    final commands = await commandPort.future;
    final loadError = await loaded.future;
    if (loadError is String) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw SegmentationException(
        SegmentationErrorKind.modelUnavailable,
        'The background-removal model could not be loaded. $loadError',
      );
    }
    return runner = SegmentationRunner._(isolate, commands, responses);
  }

  Future<Uint8List> cut(
    RgbaImage image, {
    required void Function(SegmentationStage stage) onStage,
  }) {
    final id = _nextId++;
    final job = _PendingJob(onStage);
    _jobs[id] = job;
    _commands.send(
      _Job(
        id,
        TransferableTypedData.fromList([image.pixels]),
        image.width,
        image.height,
      ),
    );
    return job.completer.future;
  }

  Future<void> dispose() async {
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final job in _jobs.values) {
      job.completer.completeError(
        const SegmentationException(
          SegmentationErrorKind.unknown,
          'The cut was cancelled.',
        ),
      );
    }
    _jobs.clear();
  }

  void _onResponse(Object? message) {
    switch (message) {
      case _Progress(:final id, :final stage):
        _jobs[id]?.onStage(stage);
      case _Done(:final id, :final pixels):
        _jobs
            .remove(id)
            ?.completer
            .complete(pixels.materialize().asUint8List());
      case _Failed(:final id, :final kind, :final message):
        _jobs
            .remove(id)
            ?.completer
            .completeError(SegmentationException(kind, message));
      case _workerExited:
        for (final job in _jobs.values) {
          job.completer.completeError(
            const SegmentationException(
              SegmentationErrorKind.outOfMemory,
              'Background removal stopped unexpectedly. Try a smaller photo.',
            ),
          );
        }
        _jobs.clear();
    }
  }

  /// Copies the bundled model to disk, because native ONNX Runtime loads
  /// models from a file path. The file name includes a content hash so that
  /// swapping the asset never reuses a stale cached copy.
  static Future<String> _extractModel(SegmentationModelConfig config) async {
    final data = await rootBundle.load(config.assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final hash = await Isolate.run(() => _fnv1a(bytes));
    final dir = await getApplicationSupportDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${config.id}-${hash.toRadixString(16)}.onnx',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    }
    return file.path;
  }

  static int _fnv1a(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

const _workerExited = 'cutout-worker-exited';

class _PendingJob {
  _PendingJob(this.onStage);
  final void Function(SegmentationStage stage) onStage;
  final completer = Completer<Uint8List>();
}

Future<void> _workerMain(_WorkerArgs args) async {
  final out = args.replies;
  final commands = ReceivePort();
  out.send(commands.sendPort);

  // Lets plugin method channels (ONNX Runtime) work from this isolate.
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);
  DartPluginRegistrant.ensureInitialized();

  final SegmentationPipeline pipeline;
  try {
    final session = await openSession(args.config, args.modelPath);
    pipeline = SegmentationPipeline(session, args.config);
    out.send(null);
  } catch (e) {
    out.send('$e');
    commands.close();
    return;
  }

  await for (final message in commands) {
    if (message is! _Job) continue;
    try {
      final image = RgbaImage(
        message.pixels.materialize().asUint8List(),
        message.width,
        message.height,
      );
      final result = await pipeline.cut(
        image,
        onStage: (stage) async => out.send(_Progress(message.id, stage)),
      );
      out.send(_Done(message.id, TransferableTypedData.fromList([result])));
    } on SegmentationException catch (e) {
      out.send(_Failed(message.id, e.kind, e.message));
    } on OutOfMemoryError {
      out.send(
        _Failed(
          message.id,
          SegmentationErrorKind.outOfMemory,
          'Your device ran out of memory on this image. Try a smaller photo.',
        ),
      );
    } catch (e) {
      out.send(
        _Failed(
          message.id,
          SegmentationErrorKind.unknown,
          'Background removal failed: $e',
        ),
      );
    }
  }
}

class _WorkerArgs {
  _WorkerArgs(this.replies, this.token, this.config, this.modelPath);
  final SendPort replies;
  final RootIsolateToken token;
  final SegmentationModelConfig config;
  final String modelPath;
}

class _Job {
  _Job(this.id, this.pixels, this.width, this.height);
  final int id;
  final TransferableTypedData pixels;
  final int width;
  final int height;
}

class _Progress {
  _Progress(this.id, this.stage);
  final int id;
  final SegmentationStage stage;
}

class _Done {
  _Done(this.id, this.pixels);
  final int id;
  final TransferableTypedData pixels;
}

class _Failed {
  _Failed(this.id, this.kind, this.message);
  final int id;
  final SegmentationErrorKind kind;
  final String message;
}
