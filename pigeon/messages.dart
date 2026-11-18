import 'package:pigeon/pigeon.dart';

// The bridge between the Dart API (lib/src) and the Fictura iOS and Android
// SDKs. After editing, regenerate the three outputs with
//   dart run pigeon --input pigeon/messages.dart

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'fictura_flutter',
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/co/fictura/fictura_flutter/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'co.fictura.fictura_flutter'),
    swiftOut: 'ios/fictura_flutter/Sources/fictura_flutter/Messages.g.swift',
  ),
)
/// `Fictura.configure`: the native SDK's options. Screens and taps are always
/// recorded from Dart, so the native SDK's own screen and tap capture is off.
class ConfigureMessage {
  ConfigureMessage({
    required this.apiKey,
    required this.wrapperVersion,
    this.apiBase,
    this.release,
    this.environment,
    required this.captureLifecycle,
    required this.captureNativeErrors,
    required this.debug,
  });

  String apiKey;

  /// This package's version, sent as `x-fictura-wrapper: flutter/<version>`.
  String wrapperVersion;
  String? apiBase;
  String? release;
  String? environment;
  bool captureLifecycle;
  bool captureNativeErrors;
  bool debug;
}

/// A Dart error for Issues, sent through the native SDK's error queue.
class ErrorMessage {
  ErrorMessage({
    required this.type,
    this.message,
    this.stack,
    required this.handled,
    required this.level,
    required this.mechanism,
    required this.properties,
  });

  String type;
  String? message;
  String? stack;
  bool handled;

  /// info, warning, error or fatal.
  String level;

  /// manual, flutter_error or platform_dispatcher.
  String mechanism;
  Map<String, Object?> properties;
}

class PaywallInfoMessage {
  PaywallInfoMessage({
    required this.paywallId,
    required this.placement,
    this.campaignId,
    this.audienceId,
    this.experimentId,
    this.variantId,
    required this.featureGating,
    required this.presentationStyle,
    this.closeReason,
  });

  String paywallId;
  String placement;
  String? campaignId;
  String? audienceId;
  String? experimentId;
  String? variantId;
  String featureGating;
  String presentationStyle;
  String? closeReason;
}

/// What one `Fictura.register` call did.
class PlacementResultMessage {
  PlacementResultMessage({
    required this.featureUnlocked,
    required this.outcome,
    this.skipReason,
    this.paywallResult,
    this.error,
    this.paywall,
  });

  /// The feature behind the placement may run now.
  bool featureUnlocked;

  /// presented, skipped or error.
  String outcome;

  /// holdout, no_audience_match, placement_not_found, placement_paused, user_is_subscribed.
  String? skipReason;

  /// purchased, restored or declined.
  String? paywallResult;
  String? error;
  PaywallInfoMessage? paywall;
}

class PackageMessage {
  PackageMessage({
    required this.id,
    required this.productId,
    required this.priceString,
    required this.priceMicros,
    required this.currency,
    required this.period,
    this.trialDays,
    this.periodMonths,
    this.oneTime,
    this.title,
    this.trialEligible,
  });

  String id;
  String productId;
  String priceString;
  int priceMicros;
  String currency;
  String period;
  int? trialDays;
  int? periodMonths;
  bool? oneTime;
  String? title;
  bool? trialEligible;
}

class PurchaseContextMessage {
  PurchaseContextMessage({
    required this.placement,
    required this.paywallId,
    this.campaignId,
    this.audienceId,
    this.experimentId,
    this.variantId,
  });

  String placement;
  String paywallId;
  String? campaignId;
  String? audienceId;
  String? experimentId;
  String? variantId;
}

class PurchaseResultMessage {
  PurchaseResultMessage({
    required this.status,
    this.transactionId,
    this.periodType,
    this.environment,
    this.error,
  });

  /// purchased, cancelled, pending or failed.
  String status;
  String? transactionId;
  String? periodType;
  String? environment;
  String? error;
}

/// Dart → native.
@HostApi()
abstract class FicturaHostApi {
  void configure(ConfigureMessage message);
  void track(String event, Map<String, Object?> properties);
  void screen(String name, Map<String, Object?> properties);
  void identify(String userId, Map<String, Object?>? attributes);
  void reset();
  void setAttributes(Map<String, Object?> attributes);
  void setOnce(Map<String, Object?> attributes);
  void unsetAttribute(String key);
  void registerSuperProperties(Map<String, Object?> properties);
  void optOut();
  void optIn();
  @async
  void flush();
  String? deviceId();
  void setRevenueCatUserId(String? id);
  void setLegalUrls(String? terms, String? privacy);

  /// On: paywalls buy through the Dart purchase handler. Off: the native default
  /// (StoreKit 2 on iOS; none on Android).
  void setPurchaseHandlerEnabled(bool enabled);
  @async
  PlacementResultMessage register(
    String placement,
    Map<String, Object?> params,
  );
  bool handleUrl(String url);
  void captureError(ErrorMessage error);
  void captureMessage(String message, String level);
}

/// Native → Dart: the purchase handler and attribution callbacks.
@FlutterApi()
abstract class FicturaFlutterApi {
  @async
  List<PackageMessage> packages(List<String> productIds);
  @async
  PurchaseResultMessage purchase(
    PackageMessage package,
    PurchaseContextMessage context,
  );
  @async
  bool restore();
  @async
  bool isSubscribed();
  void onConversion(Map<String, Object?> data);
}
