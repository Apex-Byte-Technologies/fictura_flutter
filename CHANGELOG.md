# Changelog

## 0.1.0 - Unreleased

First release: Fictura for Flutter apps, wrapping the Fictura iOS SDK (0.2.0) and Android SDK (0.2.0).

- `Fictura.configure`, events, screens, users, attributes, super properties, opt-out and flush, through the native SDKs' event queue.
- `FicturaNavigatorObserver` records named page routes as screens (Navigator, MaterialApp, GoRouter).
- `Fictura.register(placement)` shows the dashboard's paywall and returns whether the feature may run, with the paywall and its A/B variant.
- `Fictura.setPurchaseHandler` buys through `purchases_flutter`, `in_app_purchase` or your own code. Without one, iOS uses StoreKit 2.
- Uncaught Dart errors (`FlutterError.onError`, `PlatformDispatcher.onError`), `Fictura.capture` and `captureMessage` reach Issues with their Dart stacks, grouped by the app's own frames. Native crashes, hangs and ANRs come from the native SDKs.
- `Fictura.handleUrl` for tracking links and campaign parameters; `Fictura.conversions` for the matched install.
- Requests carry `x-fictura-wrapper: flutter/0.1.0` next to the native SDK's own `x-fictura-sdk`.
