import 'dart:ui';

import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:fictura_flutter/src/errors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('uncaught Dart errors', () {
    late FakeHost host;
    late FlutterExceptionHandler? flutterBefore;
    late ErrorCallback? dispatcherBefore;
    final seenByApp = <Object>[];

    setUp(() async {
      flutterBefore = FlutterError.onError;
      dispatcherBefore = PlatformDispatcher.instance.onError;
      seenByApp.clear();
      // The app's own handlers, set before Fictura.
      FlutterError.onError = (d) => seenByApp.add(d.exception);
      PlatformDispatcher.instance.onError = (e, s) {
        seenByApp.add(e);
        return true;
      };
      host = FakeHost();
      Fictura.debugReset(host: host);
      await Fictura.configure(apiKey: 'gk_test');
    });

    tearDown(() {
      Fictura.debugReset();
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = dispatcherBefore;
    });

    test(
      'a Flutter framework error is sent, and the app\'s handler still runs',
      () async {
        final error = StateError('layout broke');
        FlutterError.onError!(
          FlutterErrorDetails(
            exception: error,
            stack: StackTrace.current,
            library: 'widgets library',
            context: ErrorDescription('while building CartPage'),
          ),
        );
        await pumpEventQueue();
        final e = host.errors.single;
        expect(e.type, 'StateError');
        expect(e.message, contains('layout broke'));
        expect(e.mechanism, 'flutter_error');
        expect(e.handled, isFalse);
        expect(e.properties['library'], 'widgets library');
        expect(e.properties['context'], contains('CartPage'));
        expect(seenByApp, [error]);
      },
    );

    test('silent Flutter errors are not sent', () async {
      FlutterError.onError!(
        FlutterErrorDetails(exception: Exception('image failed'), silent: true),
      );
      await pumpEventQueue();
      expect(host.errors, isEmpty);
      expect(seenByApp, hasLength(1));
    });

    test(
      'an uncaught async error is sent, and the app\'s answer is kept',
      () async {
        final handled = PlatformDispatcher.instance.onError!(
          FormatException('bad json'),
          StackTrace.current,
        );
        await pumpEventQueue();
        expect(
          handled,
          isTrue,
          reason: 'the app\'s handler said it handled it',
        );
        expect(host.errors.single.type, 'FormatException');
        expect(host.errors.single.mechanism, 'platform_dispatcher');
        expect(seenByApp, hasLength(1));
      },
    );

    test('captureDartErrors: false leaves the handlers alone', () async {
      Fictura.debugReset(host: host);
      final before = FlutterError.onError;
      await Fictura.configure(
        apiKey: 'gk_test',
        options: const FicturaOptions(captureDartErrors: false),
      );
      expect(FlutterError.onError, same(before));
    });
  });

  group('errorMessage', () {
    test('marks an obfuscated or DWARF-only stack', () {
      final st = StackTrace.fromString(
        '*** *** *** *** ***\npid: 1, tid: 2, name 1.ui\n'
        '#00 abs 0000007a3c6d1e2b virt 00000000002d1e2b _kDartIsolateSnapshotInstructions+0x1b5e2b',
      );
      final m = errorMessage(
        StateError('x'),
        st,
        mechanism: 'manual',
        handled: true,
      );
      expect(m.properties['dart_stack'], 'non_symbolic');
    });

    test('leaves a readable stack unmarked, and an empty one out', () {
      expect(
        errorMessage(
          StateError('x'),
          StackTrace.current,
          mechanism: 'manual',
          handled: true,
        ).properties,
        isEmpty,
      );
      expect(
        errorMessage(
          StateError('x'),
          StackTrace.empty,
          mechanism: 'manual',
          handled: true,
        ).stack,
        isNull,
      );
    });
  });
}
