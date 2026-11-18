import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:fictura_flutter/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;

  setUp(() {
    host = FakeHost();
    Fictura.debugReset(host: host);
  });

  tearDown(() => Fictura.debugReset());

  group('configure', () {
    test(
      'names this package as the wrapper and keeps native screen and tap capture to Dart',
      () async {
        await Fictura.configure(
          apiKey: ' gk_test ',
          options: const FicturaOptions(
            apiBase: 'http://10.0.2.2:4000',
            release: '1.2.0+3',
            environment: 'staging',
          ),
        );
        final m = host.configured!;
        expect(m.apiKey, 'gk_test');
        expect(m.wrapperVersion, ficturaFlutterVersion);
        expect(m.apiBase, 'http://10.0.2.2:4000');
        expect(m.release, '1.2.0+3');
        expect(m.environment, 'staging');
        expect(m.captureLifecycle, isTrue);
        expect(m.captureNativeErrors, isTrue);
        expect(Fictura.isConfigured, isTrue);
      },
    );

    test(
      'an empty key leaves Fictura off, and calls before configure are dropped',
      () async {
        await Fictura.configure(apiKey: '   ');
        expect(host.configured, isNull);
        expect(Fictura.isConfigured, isFalse);
        await Fictura.track('photo_saved');
        await Fictura.identify('user_1');
        expect(host.calls, isEmpty);
        expect(await Fictura.deviceId, isNull);
        expect(
          await Fictura.handleUrl(Uri.parse('shop://open?growth_click=x')),
          isFalse,
        );
      },
    );

    test('a second configure does nothing', () async {
      await Fictura.configure(apiKey: 'gk_one');
      await Fictura.configure(apiKey: 'gk_two');
      expect(host.argsOf('configure'), hasLength(1));
      expect(host.configured!.apiKey, 'gk_one');
    });
  });

  group('events and users', () {
    setUp(() => Fictura.configure(apiKey: 'gk_test'));

    test('each call reaches the native SDK with its arguments', () async {
      await Fictura.track('photo_saved', {
        'style': 'modern',
        'count': 3,
        'tags': ['a', null],
      });
      await Fictura.screen('Cart');
      await Fictura.identify('user_77', attributes: {'plan': 'pro'});
      await Fictura.setAttributes({'plan': 'pro'});
      await Fictura.setOnce({'first_seen': '2026-11-18'});
      await Fictura.unsetAttribute('plan');
      await Fictura.registerSuperProperties({'ab': 'b'});
      await Fictura.setRevenueCatUserId(r'$RCAnonymousID:abc');
      await Fictura.optOut();
      await Fictura.optIn();
      await Fictura.flush();
      await Fictura.reset();
      expect(host.calls.map((c) => c.$1).where((n) => n != 'configure'), [
        'track',
        'screen',
        'identify',
        'setAttributes',
        'setOnce',
        'unsetAttribute',
        'registerSuperProperties',
        'setRevenueCatUserId',
        'optOut',
        'optIn',
        'flush',
        'reset',
      ]);
      expect(host.argsOf('track').single, [
        'photo_saved',
        {
          'style': 'modern',
          'count': 3,
          'tags': ['a', null],
        },
      ]);
      expect(host.argsOf('identify').single, [
        'user_77',
        {'plan': 'pro'},
      ]);
      expect(await Fictura.deviceId, 'ios-test-device');
    });

    test('a failing bridge never throws into the app', () async {
      host.throwOnTrack = true;
      await expectLater(Fictura.track('photo_saved'), completes);
    });

    test('links are handed over as strings', () async {
      expect(
        await Fictura.handleUrl(Uri.parse('shop://open?growth_click=1b2c')),
        isTrue,
      );
      expect(host.argsOf('handleUrl').single, [
        'shop://open?growth_click=1b2c',
      ]);
    });
  });

  group('placements', () {
    test(
      'register passes the placement and params, and reads the answer',
      () async {
        await Fictura.configure(apiKey: 'gk_test');
        host.registerAnswer = PlacementResultMessage(
          featureUnlocked: false,
          outcome: 'presented',
          paywallResult: 'declined',
          paywall: PaywallInfoMessage(
            paywallId: 'pw_1',
            placement: 'export_hd',
            experimentId: 'e_1',
            variantId: 'v_2',
            featureGating: 'gated',
            presentationStyle: 'fullscreen',
            closeReason: 'manual',
          ),
        );
        final r = await Fictura.register(
          'export_hd',
          params: {'source': 'editor'},
        );
        expect(host.argsOf('register').single, [
          'export_hd',
          {'source': 'editor'},
        ]);
        expect(r.featureUnlocked, isFalse);
        expect(r.outcome, FicturaPlacementOutcome.presented);
        expect(r.paywallResult, 'declined');
        expect(r.paywall!.paywallId, 'pw_1');
        expect(r.paywall!.variantId, 'v_2');
        expect(r.paywall!.featureGating, 'gated');
      },
    );

    test(
      'before configure the feature is unlocked, as the native SDKs do',
      () async {
        final r = await Fictura.register('export_hd');
        expect(r.featureUnlocked, isTrue);
        expect(host.calls, isEmpty);
      },
    );

    test('an unknown outcome reads as an error', () async {
      await Fictura.configure(apiKey: 'gk_test');
      host.registerAnswer = PlacementResultMessage(
        featureUnlocked: false,
        outcome: 'surprise',
      );
      expect(
        (await Fictura.register('x')).outcome,
        FicturaPlacementOutcome.error,
      );
    });
  });

  group('errors', () {
    setUp(() => Fictura.configure(apiKey: 'gk_test'));

    test('capture sends the type, message and Dart stack', () async {
      try {
        throw StateError('cart is empty');
      } catch (e, stack) {
        await Fictura.capture(e, stack, {'screen': 'Cart'});
      }
      final e = host.errors.single;
      expect(e.type, 'StateError');
      expect(e.message, 'Bad state: cart is empty');
      expect(e.stack, contains('fictura_test.dart'));
      expect(e.stack, startsWith('#0'));
      expect(e.handled, isTrue);
      expect(e.mechanism, 'manual');
      expect(e.properties, {'screen': 'Cart'});
    });

    test('capture without a stack uses the current one', () async {
      await Fictura.capture(Exception('no stack given'));
      expect(host.errors.single.stack, isNotEmpty);
    });

    test('captureMessage passes its level', () async {
      await Fictura.captureMessage('sync slow', level: 'warning');
      expect(host.argsOf('captureMessage').single, ['sync slow', 'warning']);
    });
  });

  test('legal urls and the purchase handler switch', () async {
    await Fictura.setLegalUrls(terms: Uri.parse('https://shop.app/terms'));
    await Fictura.setPurchaseHandler(null);
    expect(host.argsOf('setLegalUrls').single, [
      'https://shop.app/terms',
      null,
    ]);
    expect(host.argsOf('setPurchaseHandlerEnabled').single, [false]);
  });
}
