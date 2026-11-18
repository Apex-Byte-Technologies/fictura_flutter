import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// A Dart error as Issues reads it: its runtime type, message and stack text.
ErrorMessage errorMessage(
  Object error,
  StackTrace? stack, {
  required String mechanism,
  required bool handled,
  String level = 'error',
  String? message,
  Map<String, Object?> properties = const {},
}) {
  final text = stack?.toString();
  final props = <String, Object?>{...properties};
  // An obfuscated or DWARF-only release build writes addresses, not names
  // (`*** *** ***`, `#00 abs … _kDartIsolateSnapshotInstructions`): such an
  // error groups by message until symbols can be uploaded.
  if (text != null &&
      (text.contains('_kDartIsolateSnapshotInstructions') ||
          text.trimLeft().startsWith('*** ***'))) {
    props['dart_stack'] = 'non_symbolic';
  }
  return ErrorMessage(
    type: error.runtimeType.toString(),
    message: message ?? error.toString(),
    stack: (text == null || text.isEmpty) ? null : text,
    handled: handled,
    level: level,
    mechanism: mechanism,
    properties: props,
  );
}

/// Sends Flutter's and the platform dispatcher's uncaught errors, then hands each
/// one to the handler that was there before, so the app's own handling and
/// Flutter's console output are unchanged.
class DartErrorCapture {
  DartErrorCapture._(
    this._send,
    this._previousFlutter,
    this._previousDispatcher,
  );

  final void Function(ErrorMessage) _send;
  final FlutterExceptionHandler? _previousFlutter;
  final ErrorCallback? _previousDispatcher;

  static DartErrorCapture install(void Function(ErrorMessage) send) {
    final capture = DartErrorCapture._(
      send,
      FlutterError.onError,
      PlatformDispatcher.instance.onError,
    );
    FlutterError.onError = capture._onFlutterError;
    PlatformDispatcher.instance.onError = capture._onDispatcherError;
    return capture;
  }

  /// Puts the handlers that were there before back (tests).
  void uninstall() {
    FlutterError.onError = _previousFlutter;
    PlatformDispatcher.instance.onError = _previousDispatcher;
  }

  void _onFlutterError(FlutterErrorDetails details) {
    // Flutter marks expected, recoverable failures (an image that didn't load) silent.
    if (!details.silent) {
      _report(
        () => errorMessage(
          details.exception,
          details.stack,
          mechanism: 'flutter_error',
          handled: false,
          message: details.exceptionAsString(),
          properties: {
            if (details.library != null) 'library': details.library,
            if (details.context != null) 'context': details.context.toString(),
          },
        ),
      );
    }
    final previous = _previousFlutter;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _onDispatcherError(Object error, StackTrace stack) {
    _report(
      () => errorMessage(
        error,
        stack,
        mechanism: 'platform_dispatcher',
        handled: false,
      ),
    );
    return _previousDispatcher?.call(error, stack) ?? false;
  }

  void _report(ErrorMessage Function() build) {
    try {
      _send(build());
    } catch (_) {
      // Reporting must never become a second error.
    }
  }
}
