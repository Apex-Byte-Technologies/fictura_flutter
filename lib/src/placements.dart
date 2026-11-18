import 'messages.g.dart';

/// The paywall a placement showed.
class FicturaPaywallInfo {
  const FicturaPaywallInfo({
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

  final String paywallId;
  final String placement;
  final String? campaignId;
  final String? audienceId;
  final String? experimentId;
  final String? variantId;

  /// gated (the feature runs only after a purchase or restore) or non_gated.
  final String featureGating;
  final String presentationStyle;

  /// Why it closed: manual, purchased, restored, webview_failed, …
  final String? closeReason;

  static FicturaPaywallInfo fromMessage(PaywallInfoMessage m) =>
      FicturaPaywallInfo(
        paywallId: m.paywallId,
        placement: m.placement,
        campaignId: m.campaignId,
        audienceId: m.audienceId,
        experimentId: m.experimentId,
        variantId: m.variantId,
        featureGating: m.featureGating,
        presentationStyle: m.presentationStyle,
        closeReason: m.closeReason,
      );
}

enum FicturaPlacementOutcome {
  /// A paywall showed and has closed.
  presented,

  /// No paywall for this user now: see [FicturaPlacementResult.skipReason].
  skipped,

  /// Nothing showed because something failed: see [FicturaPlacementResult.error].
  error,
}

/// What one `Fictura.register` call did.
class FicturaPlacementResult {
  const FicturaPlacementResult({
    required this.featureUnlocked,
    required this.outcome,
    this.skipReason,
    this.paywallResult,
    this.error,
    this.paywall,
  });

  /// Run the feature behind the placement. False only when a gated paywall closed
  /// without a purchase, or when something failed.
  final bool featureUnlocked;
  final FicturaPlacementOutcome outcome;

  /// holdout, no_audience_match, placement_not_found, placement_paused or user_is_subscribed.
  final String? skipReason;

  /// purchased, restored or declined.
  final String? paywallResult;

  /// no_config, paywall_not_available, paywall_already_presented, no_activity, …
  final String? error;
  final FicturaPaywallInfo? paywall;

  static FicturaPlacementResult fromMessage(PlacementResultMessage m) =>
      FicturaPlacementResult(
        featureUnlocked: m.featureUnlocked,
        outcome: FicturaPlacementOutcome.values.firstWhere(
          (o) => o.name == m.outcome,
          orElse: () => FicturaPlacementOutcome.error,
        ),
        skipReason: m.skipReason,
        paywallResult: m.paywallResult,
        error: m.error,
        paywall: m.paywall == null
            ? null
            : FicturaPaywallInfo.fromMessage(m.paywall!),
      );

  @override
  String toString() =>
      'FicturaPlacementResult(featureUnlocked: $featureUnlocked, outcome: ${outcome.name}, skipReason: $skipReason, '
      'paywallResult: $paywallResult, error: $error, paywall: ${paywall?.paywallId})';
}
