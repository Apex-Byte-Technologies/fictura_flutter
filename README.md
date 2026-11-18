# Fictura for Flutter

`fictura_flutter` brings Fictura to Flutter apps: events, screens, users, server-driven paywalls and placements, A/B tests, purchases and Dart error reporting. It sends everything through the Fictura [iOS](https://github.com/Apex-Byte-Technologies/fictura_ios) and [Android](https://github.com/Apex-Byte-Technologies/fictura_android) SDKs. A Flutter app and a native app therefore share the same queue, paywalls, experiments and dashboard.

- Flutter 3.44 or later, iOS 15 or later, Android API 24 or later.
- On iOS it installs only through Swift Package Manager. Flutter turns that on by default from 3.44. If your project turned it off, turn it back on with `flutter config --enable-swift-package-manager`.

## Install

```bash
flutter pub add fictura_flutter
```

## Start

Call `configure` once, before `runApp`. The key is the app's publishable key (`gk_…`) from Fictura's Setup page. Pass it at build time instead of committing it:

```dart
import 'package:fictura_flutter/fictura_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fictura.configure(apiKey: const String.fromEnvironment('FICTURA_API_KEY'));
  runApp(const App());
}
```

```bash
flutter run --dart-define=FICTURA_API_KEY=gk_...
```

Record screens by adding the observer to your app, and give your routes names:

```dart
MaterialApp(navigatorObservers: [FicturaNavigatorObserver()], ...);
GoRouter(observers: [FicturaNavigatorObserver()], routes: [GoRoute(name: 'cart', ...)]);
```

## What it records by itself

- `first_open`, `app_open`, `app_backgrounded` and `app_updated`, with sessions (30 minutes idle).
- `screen_viewed` and `screen_closed` for named page routes, through `FicturaNavigatorObserver`. Dialogs and sheets are skipped. Call `Fictura.screen('Name')` for screens that aren't routes.
- Uncaught Dart errors from `FlutterError.onError` and `PlatformDispatcher.instance.onError`, with their Dart stacks. Fictura calls any handler you set before `configure`, so your own handling still runs.
- Native crashes and hangs (iOS MetricKit), uncaught native exceptions, and ANRs and native crashes on Android 11 and later.

Taps are not recorded automatically, because Flutter draws its own buttons.

Turn any of these off in `FicturaOptions` with `captureLifecycle`, `captureDartErrors` or `captureNativeErrors`.

## Events, users and attributes

```dart
Fictura.track('photo_saved', {'style': 'modern'});
Fictura.identify('user_123', attributes: {'plan': 'free'}); // after sign-in
Fictura.reset();                                            // after sign-out
Fictura.setAttributes({'plan': 'pro'});
Fictura.registerSuperProperties({'ab_group': 'b'});        // on every event from now on
Fictura.optOut();
```

## Paywalls and placements

Name a moment in your app once. The dashboard then decides who sees which paywall there, how often, and who is held out:

```dart
final result = await Fictura.register('export_hd');
if (result.featureUnlocked) exportHD();
```

`featureUnlocked` is false only when a gated paywall closed without a purchase, or when something failed. `result.paywall` names the paywall and its experiment variant, and `result.skipReason` says why none showed.

Only served HTML designs (paywall schema 5) show, as on the native SDKs.

### Purchases

Paywalls buy through your purchase handler, so RevenueCat or the store records the purchase as it does today. A sketch with RevenueCat (`purchases_flutter` 11; `pro` is your entitlement id, and [RevenueCat's purchase docs](https://www.revenuecat.com/docs/getting-started/making-purchases) have the details):

```dart
class RevenueCatHandler extends FicturaPurchaseHandler {
  @override
  Future<List<FicturaPackage>> packages(List<String> productIds) async {
    final offering = (await Purchases.getOfferings()).current;
    return [
      for (final p in offering?.availablePackages ?? <Package>[])
        if (productIds.contains(p.storeProduct.identifier))
          FicturaPackage(
            id: p.identifier,
            productId: p.storeProduct.identifier,
            priceString: p.storeProduct.priceString,
            priceMicros: (p.storeProduct.price * 1000000).round(),
            currency: p.storeProduct.currencyCode,
            period: switch (p.packageType) {
              PackageType.weekly => 'weekly',
              PackageType.monthly => 'monthly',
              PackageType.annual => 'annual',
              PackageType.lifetime => 'lifetime',
              _ => 'other',
            },
          ),
    ];
  }

  @override
  Future<FicturaPurchaseResult> purchase(FicturaPackage package, FicturaPurchaseContext context) async {
    try {
      final offering = (await Purchases.getOfferings()).current!;
      final p = offering.availablePackages.firstWhere((p) => p.identifier == package.id);
      await Purchases.purchase(PurchaseParams.package(p));
      return const FicturaPurchaseResult.purchased();
    } on PlatformException catch (e) {
      return PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError
          ? const FicturaPurchaseResult.cancelled()
          : FicturaPurchaseResult.failed(e.message ?? 'purchase failed');
    }
  }

  @override
  Future<bool> restore() async => (await Purchases.restorePurchases()).entitlements.all['pro']?.isActive ?? false;

  @override
  Future<bool> isSubscribed() async => (await Purchases.getCustomerInfo()).entitlements.all['pro']?.isActive ?? false;
}

await Fictura.setPurchaseHandler(RevenueCatHandler());
await Fictura.setRevenueCatUserId(await Purchases.appUserID); // and again after every Purchases.logIn
```

Without a handler, iOS buys through StoreKit 2 and Android paywalls can't buy. Android has no pending purchase, so `FicturaPurchaseResult.pending()` keeps the paywall open there, like a cancel.

## Links and attribution

Pass every link that opens the app to `Fictura.handleUrl`, including the one that cold-started it, from whatever listens for links in your app (`app_links`, for example):

```dart
Fictura.handleUrl(uri);
Fictura.conversions.listen((data) => print('matched install: $data'));
```

## Errors

```dart
try {
  await checkout();
} catch (e, stack) {
  Fictura.capture(e, stack, {'step': 'checkout'});
}
Fictura.captureMessage('sync is slow', level: 'warning');
```

Dart errors group by the app's own frames (`cart.dart:CartRepository.checkout`). The Dart SDK, Flutter and this package's frames are skipped. Don't build releases with `--obfuscate` for now. An obfuscated stack has no names, so its errors group by message, and the issue is tagged `dart_stack: non_symbolic`.

## Not yet available in Flutter

- Automatic taps.
- Readable stacks from `--obfuscate --split-debug-info` builds (no symbol upload yet).
- `presentationResult`, `dismissPaywall` and custom paywall actions, which only the iOS SDK has today.
- Flutter web, macOS, Windows and Linux.
- Anything the native SDKs don't do yet: push sent by Fictura, revenue without RevenueCat or Stripe, the cancel survey, and iOS and Android performance traces.

## How it works

```
Dart API (lib/)  ──Pigeon──▶  FicturaSDK (iOS)       ──▶  Fictura API
                 ◀─────────   fictura-android         ◀──
                 (purchase handler, conversions)
```

`pigeon/messages.dart` defines the bridge. The native SDK keeps sending its own `x-fictura-sdk: ios/…` or `android/…`, so Swift and Kotlin crash stacks and HTML paywalls work as in a native app. This package adds `x-fictura-wrapper: flutter/<version>`, `$wrapper` on every event and `contexts.app.wrapper` on every error.

## Development

```bash
flutter pub get
dart run pigeon --input pigeon/messages.dart && dart format lib/src/messages.g.dart   # after changing pigeon/messages.dart
flutter analyze
flutter test                                   # Dart unit tests
```

Kotlin unit tests, from `example/android`: `./gradlew :fictura_flutter:testDebugUnitTest`.

### Testing against a local backend and unreleased native SDKs

The integration test runs the example app on a simulator or emulator, through the real native SDKs, against a backend:

```bash
cd example
# iOS: build against a local fictura_ios checkout
FICTURA_IOS_PATH=/path/to/fictura_ios flutter test integration_test -d <simulator> \
  --dart-define=FICTURA_API_KEY=gk_... --dart-define=FICTURA_API_BASE=http://localhost:4000 \
  --dart-define=FICTURA_RUN_ID=$(date +%s)
# Android: `./gradlew :fictura:publishToMavenLocal` in fictura_android first
FICTURA_MAVEN_LOCAL=1 flutter test integration_test -d emulator-5554 \
  --dart-define=FICTURA_API_KEY=gk_... --dart-define=FICTURA_API_BASE=http://10.0.2.2:4000 \
  --dart-define=FICTURA_RUN_ID=$(date +%s)
```

Every event and error it sends carries the run id as `run_id`, so you can check that they arrived.
