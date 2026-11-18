import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:fictura_flutter/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class ShopHandler extends FicturaPurchaseHandler {
  final List<String> asked = [];
  FicturaPurchaseResult next = const FicturaPurchaseResult.purchased(
    transactionId: 'tx_9',
    periodType: 'trial',
  );
  bool fail = false;

  @override
  Future<List<FicturaPackage>> packages(List<String> productIds) async {
    asked.addAll(productIds);
    if (fail) throw StateError('store down');
    return [
      for (final id in productIds)
        FicturaPackage(
          id: id,
          productId: id,
          priceString: r'US$9.99',
          priceMicros: 9990000,
          currency: 'USD',
          period: 'monthly',
          trialDays: 7,
        ),
    ];
  }

  @override
  Future<FicturaPurchaseResult> purchase(
    FicturaPackage package,
    FicturaPurchaseContext context,
  ) async {
    if (fail) throw StateError('store down');
    expect(context.placement, 'export_hd');
    return next;
  }

  @override
  Future<bool> restore() async => true;

  @override
  Future<bool> isSubscribed() async => fail ? throw StateError('x') : true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late FicturaFlutterApi native;
  final pkg = PackageMessage(
    id: 'pro_monthly',
    productId: 'pro_monthly',
    priceString: r'US$9.99',
    priceMicros: 9990000,
    currency: 'USD',
    period: 'monthly',
  );
  final ctx = PurchaseContextMessage(
    placement: 'export_hd',
    paywallId: 'pw_1',
    variantId: 'v_2',
  );

  setUp(() {
    host = FakeHost();
    Fictura.debugReset(host: host);
    native = Fictura.debugFlutterSide;
  });

  tearDown(() => Fictura.debugReset());

  test('setting a handler switches the native SDK to it', () async {
    await Fictura.setPurchaseHandler(ShopHandler());
    expect(host.argsOf('setPurchaseHandlerEnabled').single, [true]);
  });

  test(
    'the native SDK reads packages and buys through the Dart handler',
    () async {
      final handler = ShopHandler();
      await Fictura.setPurchaseHandler(handler);
      final list = await native.packages(['pro_monthly', 'pro_annual']);
      expect(handler.asked, ['pro_monthly', 'pro_annual']);
      expect(list.map((p) => p.id), ['pro_monthly', 'pro_annual']);
      expect(list.first.priceMicros, 9990000);
      expect(list.first.trialDays, 7);

      final bought = await native.purchase(pkg, ctx);
      expect(bought.status, 'purchased');
      expect(bought.transactionId, 'tx_9');
      expect(bought.periodType, 'trial');

      handler.next = const FicturaPurchaseResult.cancelled();
      expect((await native.purchase(pkg, ctx)).status, 'cancelled');
      handler.next = const FicturaPurchaseResult.pending();
      expect((await native.purchase(pkg, ctx)).status, 'pending');
      handler.next = const FicturaPurchaseResult.failed('card declined');
      final failed = await native.purchase(pkg, ctx);
      expect(failed.status, 'failed');
      expect(failed.error, 'card declined');

      expect(await native.restore(), isTrue);
      expect(await native.isSubscribed(), isTrue);
    },
  );

  test(
    'a handler that throws becomes no packages and a failed purchase, never a crash',
    () async {
      await Fictura.setPurchaseHandler(ShopHandler()..fail = true);
      expect(await native.packages(['pro_monthly']), isEmpty);
      final r = await native.purchase(pkg, ctx);
      expect(r.status, 'failed');
      expect(r.error, contains('store down'));
      expect(await native.isSubscribed(), isFalse);
    },
  );

  test('without a handler nothing is sold', () async {
    expect(await native.packages(['pro_monthly']), isEmpty);
    expect((await native.purchase(pkg, ctx)).error, 'no_purchase_handler');
    expect(await native.restore(), isFalse);
    expect(await native.isSubscribed(), isFalse);
  });

  test('conversions arrive on the stream', () async {
    final next = Fictura.conversions.first;
    native.onConversion({'campaign': 'tiktok_bio', 'deep_link': null});
    expect(await next, {'campaign': 'tiktok_bio', 'deep_link': null});
  });
}
