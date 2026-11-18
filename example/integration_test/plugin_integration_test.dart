// Runs on a simulator or emulator, through the real native SDK, against a
// Fictura backend:
//
//   flutter test integration_test \
//     --dart-define=FICTURA_API_KEY=gk_... \
//     --dart-define=FICTURA_API_BASE=http://localhost:4000 \
//     --dart-define=FICTURA_RUN_ID=<anything unique>
//
// Every event and error it sends carries run_id, so the backend side can be
// checked afterwards (see the README's "Testing" section).

import 'dart:io';

import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const apiKey = String.fromEnvironment('FICTURA_API_KEY');
const apiBase = String.fromEnvironment('FICTURA_API_BASE');
const runId = String.fromEnvironment('FICTURA_RUN_ID', defaultValue: 'local');

class _TestPurchases extends FicturaPurchaseHandler {
  @override
  Future<List<FicturaPackage>> packages(List<String> productIds) async =>
      const [];

  @override
  Future<FicturaPurchaseResult> purchase(
    FicturaPackage package,
    FicturaPurchaseContext context,
  ) async => const FicturaPurchaseResult.cancelled();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'every call reaches the native SDK, and the SDK reaches the backend',
    (tester) async {
      expect(apiKey, isNotEmpty, reason: 'pass --dart-define=FICTURA_API_KEY');
      await Fictura.setPurchaseHandler(_TestPurchases());
      await Fictura.configure(
        apiKey: apiKey,
        options: FicturaOptions(
          apiBase: apiBase.isEmpty ? null : apiBase,
          environment: 'integration_test',
          release: 'flutter-it+$runId',
          debug: true,
        ),
      );
      expect(Fictura.isConfigured, isTrue);

      final device = await Fictura.deviceId;
      expect(device, isNotNull);
      expect(device, startsWith(Platform.isIOS ? 'ios-' : 'and-'));

      await Fictura.identify(
        'flutter_it_$runId',
        attributes: {'run_id': runId},
      );
      await Fictura.setAttributes({'flutter_it': true});
      await Fictura.registerSuperProperties({'run_id': runId});
      await Fictura.screen('IntegrationScreen', {'run_id': runId});
      await Fictura.track('flutter_integration_test', {
        'run_id': runId,
        'platform': Platform.operatingSystem,
      });

      try {
        throw StateError('flutter integration test');
      } catch (e, stack) {
        await Fictura.capture(e, stack, {'run_id': runId});
      }
      await Fictura.captureMessage(
        'flutter integration test message',
        level: 'warning',
      );

      // No campaign targets this placement, so nothing shows and the feature runs. The
      // first sighting of a name is placement_not_found; the backend then records the
      // placement (enabled, no audiences), so later runs get no_audience_match.
      final placement = await Fictura.register('flutter_it_not_a_placement');
      expect(
        placement.outcome,
        FicturaPlacementOutcome.skipped,
        reason: '$placement',
      );
      expect(
        placement.skipReason,
        isIn(['placement_not_found', 'no_audience_match']),
        reason: '$placement',
      );
      expect(placement.featureUnlocked, isTrue);

      expect(
        await Fictura.handleUrl(
          Uri.parse(
            'fictura-demo://open?utm_source=flutter_it&utm_campaign=$runId',
          ),
        ),
        isTrue,
      );

      await Fictura.flush();
    },
  );
}
