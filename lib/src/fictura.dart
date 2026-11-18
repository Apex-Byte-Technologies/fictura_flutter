import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'errors.dart';
import 'messages.g.dart';
import 'placements.dart';
import 'purchases.dart';
import 'version.dart';

/// Settings for [Fictura.configure]. Every field has a working default.
class FicturaOptions {
  const FicturaOptions({
    this.apiBase,
    this.release,
    this.environment,
    this.captureLifecycle = true,
    this.captureDartErrors = true,
    this.captureNativeErrors = true,
    this.debug = false,
  });

  /// Fictura's API. Change it only to test against a local backend.
  final String? apiBase;

  /// The release for Issues and Releases (default: the app's version+build, `1.2.0+45`).
  final String? release;

  /// `production`, `staging`, … (default `production`; `development` in iOS debug builds).
  final String? environment;

  /// Record `first_open`, `app_open`, `app_backgrounded` and `app_updated`.
  final bool captureLifecycle;

  /// Report uncaught Dart errors (`FlutterError.onError`, `PlatformDispatcher.onError`).
  final bool captureDartErrors;

  /// Report native crashes, hangs and ANRs, read by the iOS and Android SDKs.
  final bool captureNativeErrors;

  /// Print what the native SDK does to the device log.
  final bool debug;
}

/// Fictura for Flutter apps: events, screens, users, paywalls and placements,
/// purchases and errors, through the Fictura iOS and Android SDKs.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Fictura.configure(apiKey: const String.fromEnvironment('FICTURA_API_KEY'));
///   runApp(const App());
/// }
/// ```
///
/// Nothing here throws: a call that fails is dropped, and in debug builds it
/// says why on the console.
abstract final class Fictura {
  static FicturaHostApi _host = FicturaHostApi();
  static bool _configured = false;
  static FicturaPurchaseHandler? _purchaseHandler;
  static DartErrorCapture? _errorCapture;
  static final _FlutterSide _flutterSide = _FlutterSide();
  static StreamController<Map<String, Object?>> _conversions =
      StreamController.broadcast();

  /// Whether [configure] has run.
  static bool get isConfigured => _configured;

  /// Starts Fictura. Call once, before `runApp`. [apiKey] is the app's publishable
  /// key (`gk_…`) from Fictura's Setup page. A second call does nothing.
  static Future<void> configure({
    required String apiKey,
    FicturaOptions options = const FicturaOptions(),
  }) async {
    if (_configured) {
      _log('configure() was called twice; the first call wins.');
      return;
    }
    final key = apiKey.trim();
    if (key.isEmpty) {
      _log(
        'configure(): the API key is empty, so Fictura stays off. Pass it with --dart-define=FICTURA_API_KEY=...',
      );
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    FicturaFlutterApi.setUp(_flutterSide);
    try {
      await _host.configure(
        ConfigureMessage(
          apiKey: key,
          wrapperVersion: ficturaFlutterVersion,
          apiBase: options.apiBase,
          release: options.release,
          environment: options.environment,
          captureLifecycle: options.captureLifecycle,
          captureNativeErrors: options.captureNativeErrors,
          debug: options.debug,
        ),
      );
    } catch (e) {
      _log('configure() failed: $e');
      return;
    }
    _configured = true;
    if (options.captureDartErrors) {
      _errorCapture = DartErrorCapture.install(
        (m) => unawaited(_call(() => _host.captureError(m))),
      );
    }
  }

  // ── Events ────────────────────────────────────────────────────────────────

  /// Records an event, like `Fictura.track('photo_saved', {'style': 'modern'})`.
  static Future<void> track(
    String event, [
    Map<String, Object?> properties = const {},
  ]) => _whenConfigured(() => _host.track(event, properties));

  /// Records a screen view (`screen_viewed`, and `screen_closed` for the one before).
  /// [FicturaNavigatorObserver] calls it for named routes.
  static Future<void> screen(
    String name, [
    Map<String, Object?> properties = const {},
  ]) => _whenConfigured(() => _host.screen(name, properties));

  /// Properties added to every event from now on (kept between launches).
  static Future<void> registerSuperProperties(
    Map<String, Object?> properties,
  ) => _whenConfigured(() => _host.registerSuperProperties(properties));

  /// Sends queued events now.
  static Future<void> flush() => _whenConfigured(() => _host.flush());

  // ── Users ─────────────────────────────────────────────────────────────────

  /// Links this device to your user id, after sign-in. Experiments follow the user to other devices.
  static Future<void> identify(
    String userId, {
    Map<String, Object?>? attributes,
  }) => _whenConfigured(() => _host.identify(userId, attributes));

  /// Logs the user out, at sign-out.
  static Future<void> reset() => _whenConfigured(() => _host.reset());

  /// User attributes for audiences and targeting (letters, digits and `_`; at most 100).
  static Future<void> setAttributes(Map<String, Object?> attributes) =>
      _whenConfigured(() => _host.setAttributes(attributes));

  /// Attributes set only if the user doesn't have them yet.
  static Future<void> setOnce(Map<String, Object?> attributes) =>
      _whenConfigured(() => _host.setOnce(attributes));

  static Future<void> unsetAttribute(String key) =>
      _whenConfigured(() => _host.unsetAttribute(key));

  /// Stops all capture and drops what is queued. Remembered between launches.
  static Future<void> optOut() => _whenConfigured(() => _host.optOut());

  static Future<void> optIn() => _whenConfigured(() => _host.optIn());

  /// This install's Fictura device id, or null before [configure].
  static Future<String?> get deviceId async => _configured
      ? await _call<String?>(() => _host.deviceId(), fallback: null)
      : null;

  /// The RevenueCat app user id, so RevenueCat's webhook revenue joins this user.
  /// Call it after `Purchases.configure` and after every RevenueCat `logIn`.
  static Future<void> setRevenueCatUserId(String? id) =>
      _call(() => _host.setRevenueCatUserId(id));

  // ── Paywalls and placements ───────────────────────────────────────────────

  /// Shows the paywall the dashboard set for [placement], if any, and says
  /// whether the feature behind it may run:
  ///
  /// ```dart
  /// final result = await Fictura.register('export_hd');
  /// if (result.featureUnlocked) exportHD();
  /// ```
  ///
  /// The future completes when the paywall closes, or at once when none shows.
  /// Before [configure] the feature is unlocked, as the native SDKs do.
  static Future<FicturaPlacementResult> register(
    String placement, {
    Map<String, Object?> params = const {},
  }) async {
    if (!_configured) {
      return const FicturaPlacementResult(
        featureUnlocked: true,
        outcome: FicturaPlacementOutcome.skipped,
        error: 'not_configured',
      );
    }
    try {
      return FicturaPlacementResult.fromMessage(
        await _host.register(placement, params),
      );
    } catch (e) {
      _log('register($placement) failed: $e');
      return FicturaPlacementResult(
        featureUnlocked: false,
        outcome: FicturaPlacementOutcome.error,
        error: '$e',
      );
    }
  }

  /// How paywalls buy. Set it before the first paywall shows; null goes back to
  /// the native default (StoreKit 2 on iOS, none on Android).
  static Future<void> setPurchaseHandler(FicturaPurchaseHandler? handler) {
    _purchaseHandler = handler;
    WidgetsFlutterBinding.ensureInitialized();
    FicturaFlutterApi.setUp(_flutterSide);
    return _call(() => _host.setPurchaseHandlerEnabled(handler != null));
  }

  /// Your terms and privacy URLs, which paywall designs link to.
  static Future<void> setLegalUrls({Uri? terms, Uri? privacy}) =>
      _call(() => _host.setLegalUrls(terms?.toString(), privacy?.toString()));

  // ── Links and attribution ─────────────────────────────────────────────────

  /// Pass every link that opens the app, including the one that cold-started it.
  /// Fictura reads its tracking-link and campaign parameters. True when it found some.
  static Future<bool> handleUrl(Uri uri) async => _configured
      ? await _call<bool>(
          () => _host.handleUrl(uri.toString()),
          fallback: false,
        )
      : false;

  /// Data the backend matched for this install (deferred deep links, campaign), once per install.
  static Stream<Map<String, Object?>> get conversions => _conversions.stream;

  // ── Errors ────────────────────────────────────────────────────────────────

  /// Reports a handled error to Issues, with its stack:
  /// `catch (e, stack) { Fictura.capture(e, stack); }`.
  static Future<void> capture(
    Object error, [
    StackTrace? stackTrace,
    Map<String, Object?> properties = const {},
  ]) => _whenConfigured(
    () => _host.captureError(
      errorMessage(
        error,
        stackTrace ?? StackTrace.current,
        mechanism: 'manual',
        handled: true,
        properties: properties,
      ),
    ),
  );

  /// Reports a message to Issues. [level]: info, warning, error or fatal.
  static Future<void> captureMessage(
    String message, {
    String level = 'error',
  }) => _whenConfigured(() => _host.captureMessage(message, level));

  // ── Internals ─────────────────────────────────────────────────────────────

  static Future<void> _whenConfigured(Future<void> Function() call) async {
    if (!_configured) return;
    await _call(call);
  }

  static Future<T> _call<T>(Future<T> Function() call, {T? fallback}) async {
    try {
      return await call();
    } catch (e) {
      _log('call failed: $e');
      return fallback as T;
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[fictura] $message');
  }

  /// Replaces the bridge to the native SDK and forgets every setting (tests).
  @visibleForTesting
  static void debugReset({FicturaHostApi? host}) {
    _errorCapture?.uninstall();
    _errorCapture = null;
    _host = host ?? FicturaHostApi();
    _configured = false;
    _purchaseHandler = null;
    unawaited(_conversions.close());
    _conversions = StreamController.broadcast();
  }

  /// What the native SDK calls in Dart (tests).
  @visibleForTesting
  static FicturaFlutterApi get debugFlutterSide => _flutterSide;
}

/// The native SDK's calls into Dart: the purchase handler and conversions.
class _FlutterSide extends FicturaFlutterApi {
  FicturaPurchaseHandler? get _handler => Fictura._purchaseHandler;

  @override
  Future<List<PackageMessage>> packages(List<String> productIds) async {
    final handler = _handler;
    if (handler == null) return const [];
    try {
      return (await handler.packages(
        productIds,
      )).map((p) => p.toMessage()).toList();
    } catch (e) {
      Fictura._log('the purchase handler\'s packages() failed: $e');
      return const [];
    }
  }

  @override
  Future<PurchaseResultMessage> purchase(
    PackageMessage package,
    PurchaseContextMessage context,
  ) async {
    final handler = _handler;
    if (handler == null) {
      return PurchaseResultMessage(
        status: 'failed',
        error: 'no_purchase_handler',
      );
    }
    try {
      final result = await handler.purchase(
        FicturaPackage.fromMessage(package),
        FicturaPurchaseContext.fromMessage(context),
      );
      return result.toMessage();
    } catch (e) {
      return PurchaseResultMessage(status: 'failed', error: '$e');
    }
  }

  @override
  Future<bool> restore() async {
    try {
      return await _handler?.restore() ?? false;
    } catch (e) {
      Fictura._log('the purchase handler\'s restore() failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isSubscribed() async {
    try {
      return await _handler?.isSubscribed() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  void onConversion(Map<String, Object?> data) {
    if (!Fictura._conversions.isClosed) Fictura._conversions.add(data);
  }
}
