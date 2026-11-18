import FicturaSDK
import Flutter
import UIKit

/// The iOS side of fictura_flutter: each Dart call goes to the Fictura iOS SDK.
public final class FicturaFlutterPlugin: NSObject, FlutterPlugin, FicturaHostApi {
    private let flutterApi: FicturaFlutterApi
    private var purchaseController: DartPurchaseController?

    init(messenger: FlutterBinaryMessenger) {
        flutterApi = FicturaFlutterApi(binaryMessenger: messenger)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FicturaFlutterPlugin(messenger: registrar.messenger())
        FicturaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        registrar.publish(instance)
    }

    // MARK: Setup

    func configure(message: ConfigureMessage) throws {
        var options = FicturaOptions()
        if let base = message.apiBase, let url = URL(string: base) { options.apiBase = url }
        // A Flutter app is one view controller and draws its own controls, so screens
        // and taps come from Dart (FicturaNavigatorObserver, Fictura.screen).
        options.captureScreens = false
        options.captureTaps = false
        options.captureLifecycle = message.captureLifecycle
        options.captureErrors = message.captureNativeErrors
        options.release = message.release
        options.environment = message.environment
        options.debug = message.debug
        options.wrapper = FicturaWrapper(name: "flutter", version: message.wrapperVersion)
        Fictura.configure(apiKey: message.apiKey, options: options)
        // The app usually sets its purchase handler before configure.
        if let purchaseController { Fictura.purchaseController = purchaseController }
        let api = flutterApi
        Fictura.onConversion { data in
            let payload = Bridge.toDart(data)
            Task { @MainActor in try? await api.onConversion(data: payload) }
        }
    }

    // MARK: Events and users

    func track(event: String, properties: [String: Any?]) throws {
        Fictura.track(event, properties: Bridge.fromDart(properties))
    }

    func screen(name: String, properties: [String: Any?]) throws {
        Fictura.screen(name, properties: Bridge.fromDart(properties))
    }

    func identify(userId: String, attributes: [String: Any?]?) throws {
        Fictura.identify(userId, attributes: attributes.map(Bridge.fromDart))
    }

    func reset() throws { Fictura.reset() }

    func setAttributes(attributes: [String: Any?]) throws { Fictura.setAttributes(Bridge.fromDart(attributes)) }

    func setOnce(attributes: [String: Any?]) throws { Fictura.setOnce(Bridge.fromDart(attributes)) }

    func unsetAttribute(key: String) throws { Fictura.unsetAttribute(key) }

    func registerSuperProperties(properties: [String: Any?]) throws {
        Fictura.register(superProperties: Bridge.fromDart(properties))
    }

    func optOut() throws { Fictura.optOut() }

    func optIn() throws { Fictura.optIn() }

    func flush() async throws {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Fictura.flush { done.resume() }
        }
    }

    func deviceId() throws -> String? { Fictura.deviceId }

    func setRevenueCatUserId(id: String?) throws { Fictura.setRevenueCatUserId(id) }

    func setLegalUrls(terms: String?, privacy: String?) throws {
        Fictura.setLegalURLs(terms: terms.flatMap(URL.init(string:)), privacy: privacy.flatMap(URL.init(string:)))
    }

    // MARK: Paywalls

    func setPurchaseHandlerEnabled(enabled: Bool) throws {
        purchaseController = enabled ? DartPurchaseController(api: flutterApi) : nil
        Fictura.purchaseController = purchaseController
    }

    func register(placement: String, params: [String: Any?]) async throws -> PlacementResultMessage {
        let clean = Bridge.fromDart(params)
        return await withCheckedContinuation { (done: CheckedContinuation<PlacementResultMessage, Never>) in
            DispatchQueue.main.async {
                let outcome = PlacementOutcome(done)
                var handler = PlacementHandler()
                handler.onPresent = { info in outcome.paywall = info }
                handler.onDismiss = { info, result in
                    outcome.kind = "presented"
                    outcome.paywall = info
                    switch result {
                    case .purchased: outcome.paywallResult = "purchased"
                    case .restored: outcome.paywallResult = "restored"
                    case .declined: outcome.paywallResult = "declined"
                    }
                    outcome.finishSoon()
                }
                handler.onSkip = { reason in
                    outcome.kind = "skipped"
                    outcome.skipReason = reason.rawValue
                    outcome.finishSoon()
                }
                handler.onError = { error in
                    outcome.kind = "error"
                    outcome.error = (error as? FicturaError)?.code ?? String(describing: error)
                    outcome.finishSoon()
                }
                Fictura.register(placement: placement, params: clean, handler: handler) {
                    outcome.featureUnlocked = true
                    outcome.finishSoon()
                }
            }
        }
    }

    // MARK: Links and errors

    func handleUrl(url: String) throws -> Bool {
        guard let u = URL(string: url) else { return false }
        return Fictura.handle(url: u)
    }

    func captureError(error: ErrorMessage) throws {
        Fictura.Wrapper.captureError(type: error.type, message: error.message, stack: error.stack, handled: error.handled,
                                     level: error.level, mechanism: error.mechanism, runtime: "dart",
                                     properties: Bridge.fromDart(error.properties))
    }

    func captureMessage(message: String, level: String) throws {
        Fictura.captureMessage(message, level: level)
    }
}

/// Collects one `register` call's callbacks into a single answer. The native SDK
/// calls the handler, then the feature, in one main-thread turn, so the answer is
/// sent on the next turn, once both have run.
private final class PlacementOutcome {
    private var done: CheckedContinuation<PlacementResultMessage, Never>?
    var featureUnlocked = false
    var kind = "skipped"
    var skipReason: String?
    var paywallResult: String?
    var error: String?
    var paywall: PaywallInfo?

    init(_ done: CheckedContinuation<PlacementResultMessage, Never>) { self.done = done }

    func finishSoon() {
        DispatchQueue.main.async { [self] in
            guard let done else { return }
            self.done = nil
            done.resume(returning: PlacementResultMessage(
                featureUnlocked: featureUnlocked, outcome: kind, skipReason: skipReason, paywallResult: paywallResult,
                error: error, paywall: paywall.map {
                    PaywallInfoMessage(paywallId: $0.paywallId, placement: $0.placement, campaignId: $0.campaignId,
                                       audienceId: $0.audienceId, experimentId: $0.experimentId, variantId: $0.variantId,
                                       featureGating: $0.featureGating, presentationStyle: $0.presentationStyle,
                                       closeReason: $0.closeReason)
                }))
        }
    }
}

/// Paywalls buy through the app's Dart purchase handler (`Fictura.setPurchaseHandler`).
final class DartPurchaseController: FicturaPurchaseController {
    private let api: FicturaFlutterApi

    init(api: FicturaFlutterApi) { self.api = api }

    func packages(for productIds: [String]) async -> [FicturaPackage] {
        guard let list = try? await api.packages(productIds: productIds) else { return [] }
        return list.map {
            FicturaPackage(id: $0.id, productId: $0.productId, priceString: $0.priceString, priceMicros: Int($0.priceMicros),
                           currency: $0.currency, period: $0.period, trialDays: $0.trialDays.map { Int($0) },
                           periodMonths: $0.periodMonths.map { Int($0) }, oneTime: $0.oneTime, title: $0.title,
                           trialEligible: $0.trialEligible)
        }
    }

    func purchase(_ package: FicturaPackage, context: FicturaPurchaseContext) async -> FicturaPurchaseResult {
        let message = PackageMessage(id: package.id, productId: package.product_id, priceString: package.price_string,
                                     priceMicros: Int64(package.price_micros), currency: package.currency, period: package.period,
                                     trialDays: package.trial_days.map { Int64($0) }, periodMonths: package.period_months.map { Int64($0) },
                                     oneTime: package.one_time, title: package.title, trialEligible: package.trial_eligible)
        let ctx = PurchaseContextMessage(placement: context.placement, paywallId: context.paywallId, campaignId: context.campaignId,
                                         audienceId: context.audienceId, experimentId: context.experimentId, variantId: context.variantId)
        do {
            let r = try await api.purchase(package: message, context: ctx)
            switch r.status {
            case "purchased": return .purchased(transactionId: r.transactionId, periodType: r.periodType, environment: r.environment)
            case "cancelled": return .cancelled
            case "pending": return .pending
            default: return .failed(r.error ?? "purchase_failed")
            }
        } catch {
            return .failed(String(describing: error))
        }
    }

    func restore() async throws -> Bool { try await api.restore() }

    func isSubscribed() async -> Bool { (try? await api.isSubscribed()) ?? false }
}

/// Values crossing the bridge: Dart's nulls become NSNull for the SDK, and back.
enum Bridge {
    static func fromDart(_ map: [String: Any?]) -> [String: Any] {
        map.mapValues { value($0) }
    }

    private static func value(_ v: Any?) -> Any {
        switch v {
        case nil: return NSNull()
        case let m as [String: Any?]: return fromDart(m)
        case let m as [AnyHashable: Any?]:
            var out: [String: Any] = [:]
            for (k, x) in m { out[String(describing: k)] = value(x) }
            return out
        case let a as [Any?]: return a.map { value($0) }
        case let some?: return some
        }
    }

    static func toDart(_ map: [String: Any]) -> [String: Any?] {
        map.mapValues { $0 is NSNull ? nil : $0 }
    }
}
