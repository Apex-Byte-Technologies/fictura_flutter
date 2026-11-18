import 'dart:async';

import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// Run against a local backend:
///   flutter run --dart-define=FICTURA_API_KEY=gk_... --dart-define=FICTURA_API_BASE=http://localhost:4000
/// (the Android emulator reaches the Mac at http://10.0.2.2:4000).
const apiKey = String.fromEnvironment('FICTURA_API_KEY');
const apiBase = String.fromEnvironment('FICTURA_API_BASE');

/// The placement the "Show a paywall" button registers.
const demoPlacement = String.fromEnvironment(
  'FICTURA_DEMO_PLACEMENT',
  defaultValue: 'flutter_demo',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fictura.setPurchaseHandler(DemoPurchaseHandler());
  await Fictura.configure(
    apiKey: apiKey,
    options: FicturaOptions(
      apiBase: apiBase.isEmpty ? null : apiBase,
      environment: 'development',
      debug: true,
    ),
  );
  await Fictura.setLegalUrls(
    terms: Uri.parse('https://fictura.co/terms'),
    privacy: Uri.parse('https://fictura.co/privacy'),
  );
  runApp(const DemoApp());
}

/// Sells a made-up monthly plan, so paywalls can be tried without a store account.
/// A real app backs this with purchases_flutter (RevenueCat) or in_app_purchase.
class DemoPurchaseHandler extends FicturaPurchaseHandler {
  @override
  Future<List<FicturaPackage>> packages(List<String> productIds) async => [
    for (final id in productIds)
      FicturaPackage(
        id: id,
        productId: id,
        priceString: r'US$4.99',
        priceMicros: 4990000,
        currency: 'USD',
        period: id.contains('annual') ? 'annual' : 'monthly',
        trialDays: 3,
        trialEligible: true,
      ),
  ];

  @override
  Future<FicturaPurchaseResult> purchase(
    FicturaPackage package,
    FicturaPurchaseContext context,
  ) async => FicturaPurchaseResult.purchased(
    transactionId: 'demo_${DateTime.now().millisecondsSinceEpoch}',
    environment: 'sandbox',
  );
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fictura Flutter demo',
    navigatorObservers: [FicturaNavigatorObserver()],
    initialRoute: 'Home',
    routes: {'Home': (_) => const HomePage(), 'Cart': (_) => const CartPage()},
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Ready';
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    Fictura.deviceId.then((id) => setState(() => _deviceId = id));
  }

  void _say(String s) => setState(() => _status = s);

  @override
  Widget build(BuildContext context) {
    final buttons = <(String, String, FutureOr<void> Function())>[
      (
        'track',
        'Track an event',
        () async {
          await Fictura.track('demo_button_tapped', {
            'button': 'track',
            'at': DateTime.now().toIso8601String(),
          });
          _say('Tracked demo_button_tapped');
        },
      ),
      (
        'identify',
        'Sign in as demo_user',
        () async {
          await Fictura.identify('demo_user', attributes: {'plan': 'free'});
          _say('Identified demo_user');
        },
      ),
      (
        'cart',
        'Open the cart screen',
        () => Navigator.of(context).pushNamed('Cart'),
      ),
      (
        'paywall',
        'Show the $demoPlacement placement',
        () async {
          final r = await Fictura.register(
            demoPlacement,
            params: {'source': 'home'},
          );
          _say('Placement: $r');
        },
      ),
      (
        'handled',
        'Report a handled error',
        () async {
          try {
            int.parse('not a number');
          } catch (e, stack) {
            await Fictura.capture(e, stack, {'button': 'handled'});
          }
          _say('Captured a FormatException');
        },
      ),
      (
        'throw',
        'Throw in a tap handler',
        () => throw StateError('Demo: thrown in a tap handler'),
      ),
      (
        'async',
        'Throw in an async gap',
        () {
          unawaited(
            Future<void>.delayed(
              Duration.zero,
              () => throw ArgumentError('Demo: thrown after an await'),
            ),
          );
          _say('Threw an async error');
        },
      ),
      (
        'flush',
        'Send queued events now',
        () async {
          await Fictura.flush();
          _say('Flushed');
        },
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Fictura Flutter demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            apiKey.isEmpty
                ? 'No FICTURA_API_KEY: Fictura is off.'
                : 'Device: ${_deviceId ?? '…'}',
            key: const Key('device'),
          ),
          const SizedBox(height: 8),
          Text(_status, key: const Key('status')),
          const SizedBox(height: 16),
          for (final (key, label, action) in buttons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                key: Key(key),
                onPressed: action,
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cart')),
    body: Center(
      child: FilledButton(
        key: const Key('checkout'),
        onPressed: () => Fictura.track('checkout_started', {'items': 2}),
        child: const Text('Checkout'),
      ),
    ),
  );
}
