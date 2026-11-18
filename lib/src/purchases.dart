import 'messages.g.dart';

/// A product a paywall can sell, priced for this user's store.
class FicturaPackage {
  const FicturaPackage({
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

  /// The id the paywall buys with: the store product id, or a RevenueCat package id like `$rc_monthly`.
  final String id;
  final String productId;

  /// The store's localized price, like `US$9.99`.
  final String priceString;

  /// The price in millionths of [currency], for per-week and per-day math.
  final int priceMicros;
  final String currency;

  /// weekly, monthly, annual, lifetime or other.
  final String period;
  final int? trialDays;

  /// Months one renewal covers when the plan isn't weekly, monthly or yearly (iOS only).
  final int? periodMonths;

  /// Bought once and never renews (iOS only).
  final bool? oneTime;
  final String? title;
  final bool? trialEligible;

  PackageMessage toMessage() => PackageMessage(
    id: id,
    productId: productId,
    priceString: priceString,
    priceMicros: priceMicros,
    currency: currency,
    period: period,
    trialDays: trialDays,
    periodMonths: periodMonths,
    oneTime: oneTime,
    title: title,
    trialEligible: trialEligible,
  );

  static FicturaPackage fromMessage(PackageMessage m) => FicturaPackage(
    id: m.id,
    productId: m.productId,
    priceString: m.priceString,
    priceMicros: m.priceMicros,
    currency: m.currency,
    period: m.period,
    trialDays: m.trialDays,
    periodMonths: m.periodMonths,
    oneTime: m.oneTime,
    title: m.title,
    trialEligible: m.trialEligible,
  );
}

/// Where a purchase came from, for attribution in Fictura and RevenueCat.
class FicturaPurchaseContext {
  const FicturaPurchaseContext({
    required this.placement,
    required this.paywallId,
    this.campaignId,
    this.audienceId,
    this.experimentId,
    this.variantId,
  });

  final String placement;
  final String paywallId;
  final String? campaignId;
  final String? audienceId;
  final String? experimentId;
  final String? variantId;

  static FicturaPurchaseContext fromMessage(PurchaseContextMessage m) =>
      FicturaPurchaseContext(
        placement: m.placement,
        paywallId: m.paywallId,
        campaignId: m.campaignId,
        audienceId: m.audienceId,
        experimentId: m.experimentId,
        variantId: m.variantId,
      );
}

/// How a purchase ended.
sealed class FicturaPurchaseResult {
  const FicturaPurchaseResult();

  const factory FicturaPurchaseResult.purchased({
    String? transactionId,
    String? periodType,
    String? environment,
  }) = FicturaPurchased;
  const factory FicturaPurchaseResult.cancelled() = FicturaPurchaseCancelled;

  /// Waiting on approval, like Ask to Buy. Android reads it as cancelled: the paywall stays open.
  const factory FicturaPurchaseResult.pending() = FicturaPurchasePending;
  const factory FicturaPurchaseResult.failed(String message) =
      FicturaPurchaseFailed;

  PurchaseResultMessage toMessage() => switch (this) {
    FicturaPurchased(
      :final transactionId,
      :final periodType,
      :final environment,
    ) =>
      PurchaseResultMessage(
        status: 'purchased',
        transactionId: transactionId,
        periodType: periodType,
        environment: environment,
      ),
    FicturaPurchaseCancelled() => PurchaseResultMessage(status: 'cancelled'),
    FicturaPurchasePending() => PurchaseResultMessage(status: 'pending'),
    FicturaPurchaseFailed(:final message) => PurchaseResultMessage(
      status: 'failed',
      error: message,
    ),
  };
}

final class FicturaPurchased extends FicturaPurchaseResult {
  const FicturaPurchased({
    this.transactionId,
    this.periodType,
    this.environment,
  });

  final String? transactionId;

  /// normal, trial or intro.
  final String? periodType;

  /// production or sandbox.
  final String? environment;
}

final class FicturaPurchaseCancelled extends FicturaPurchaseResult {
  const FicturaPurchaseCancelled();
}

final class FicturaPurchasePending extends FicturaPurchaseResult {
  const FicturaPurchasePending();
}

final class FicturaPurchaseFailed extends FicturaPurchaseResult {
  const FicturaPurchaseFailed(this.message);

  final String message;
}

/// How paywalls buy, set with `Fictura.setPurchaseHandler`. Back it with
/// `purchases_flutter` (RevenueCat) or `in_app_purchase`, so the store and your
/// billing provider record the purchase as they do today.
///
/// Without one, iOS buys through StoreKit 2 and Android paywalls can't buy.
abstract class FicturaPurchaseHandler {
  /// Packages for these store product ids, priced for this user.
  Future<List<FicturaPackage>> packages(List<String> productIds);

  Future<FicturaPurchaseResult> purchase(
    FicturaPackage package,
    FicturaPurchaseContext context,
  );

  /// True when an active purchase was restored.
  Future<bool> restore() async => false;

  /// True when the user has an active subscription. Placements skip subscribers by default.
  Future<bool> isSubscribed() async => false;
}
