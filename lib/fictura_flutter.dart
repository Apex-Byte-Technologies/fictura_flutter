/// Fictura for Flutter apps.
///
/// Events, screens, users, server-driven paywalls and placements, A/B tests,
/// purchases and Dart error reporting, through the Fictura iOS and Android SDKs.
library;

export 'src/fictura.dart' show Fictura, FicturaOptions;
export 'src/navigator_observer.dart' show FicturaNavigatorObserver;
export 'src/placements.dart'
    show FicturaPaywallInfo, FicturaPlacementOutcome, FicturaPlacementResult;
export 'src/purchases.dart'
    show
        FicturaPackage,
        FicturaPurchaseCancelled,
        FicturaPurchaseContext,
        FicturaPurchaseFailed,
        FicturaPurchaseHandler,
        FicturaPurchasePending,
        FicturaPurchaseResult,
        FicturaPurchased;
export 'src/version.dart' show ficturaFlutterVersion;
