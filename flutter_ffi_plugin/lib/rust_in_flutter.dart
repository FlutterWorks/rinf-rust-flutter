/// This module supports communication with Rust.
/// More specifically, sending requests to Rust and
/// receiving stream signals from Rust are possible.

import 'dart:async';
import 'dart:math';
import 'src/exports.dart';
import 'package:flutter/foundation.dart';

export 'src/exports.dart' show RustOperation;
export 'src/exports.dart' show RustRequest;
export 'src/exports.dart' show RustResponse;
export 'src/exports.dart' show RustSignal;

/// Listens to a stream from Rust and broadcasts the data in Dart.
/// You can see the usage example at
/// https://pub.dev/packages/rinf/example.
final rustBroadcaster = StreamController<RustSignal>.broadcast();
final _responseBroadcaster = StreamController<RustResponseUnique>.broadcast();
final _requestIdGenerator = _IdGenerator();

/// Contains basic functionalities of this framework.
class Rinf {
  /// Makes sure that the Rust side is ready.
  /// Don't forget to call this function in the `main` function of Dart.
  static Future<void> ensureInitialized() async {
    await api.prepareChannels();
    final rustSignalStream = api.prepareRustSignalStream();
    rustSignalStream.listen((rustSignal) {
      rustBroadcaster.add(rustSignal);
    });
    final rustResponseStream = api.prepareRustResponseStream();
    rustResponseStream.listen((rustResponseUnique) {
      _responseBroadcaster.add(rustResponseUnique);
    });
    if (kDebugMode) {
      final rustReportStream = api.prepareRustReportStream();
      rustReportStream.listen((rustReport) {
        print(rustReport);
      });
    }
    while (!(await api.checkRustStreams())) {}
    api.startRustLogic();
  }

  /// Ensure that all Rust tasks are terminated
  /// by calling this function before closing the Flutter app.
  /// Doing so can prevent potential memory errors that may occur
  /// when Rust attempts to send data after the Dart VM has been turned off.
  /// Please note that on the web, this function does not have any effect,
  /// as tasks are managed by the JavaScript runtime, not Rust.
  static Future<void> ensureFinalized() async {
    await api.stopRustLogic();
  }
}

/// Sends bytes data to Rust wrapped in `RustRequest` object
/// with operation and address fields.
/// This system follows the definition of RESTful API
/// and is very similar to HTTP request.
/// Returns `RustResponse` object that is somehow calculated
/// from the Rust side.
/// If the Rust doesn't respond for 60 seconds,
/// this function will return a failed `RustResponse` object.
/// You can see the usage example at
/// https://pub.dev/packages/rinf/example.
Future<RustResponse> requestToRust(RustRequest rustRequest) async {
  final id = _requestIdGenerator.generateId();
  final requestUnique = RustRequestUnique(id: id, request: rustRequest);
  api.requestToRust(requestUnique: requestUnique);
  final future = _responseBroadcaster.stream.firstWhere((responseUnique) {
    return responseUnique.id == id;
  });
  final responseUnique = await future.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      return RustResponseUnique(
        id: id,
        response: RustResponse(
          successful: false,
          message: null,
          blob: null,
        ),
      );
    },
  );
  final rustResponse = responseUnique.response;
  return rustResponse;
}

class _IdGenerator {
  final _maxLimit = pow(2, 31).toInt() - 1;
  final _minLimit = -pow(2, 31).toInt();
  int _counter = 0;
  int generateId() {
    final id = _counter;
    final increased = _counter + 1;
    _counter = increased <= _maxLimit ? increased : _minLimit;
    return id;
  }
}
