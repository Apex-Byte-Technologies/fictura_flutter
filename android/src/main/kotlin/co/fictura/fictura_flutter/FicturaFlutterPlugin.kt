package co.fictura.fictura_flutter

import android.app.Activity
import android.app.Application
import android.net.Uri
import android.os.Handler
import android.os.Looper
import co.fictura.sdk.Fictura
import co.fictura.sdk.FicturaOptions
import co.fictura.sdk.FicturaPackage
import co.fictura.sdk.FicturaWrapper
import co.fictura.sdk.PaywallInfo
import co.fictura.sdk.PlacementHandler
import co.fictura.sdk.PurchaseContext
import co.fictura.sdk.PurchaseController
import co.fictura.sdk.PurchaseResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.lang.ref.WeakReference
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/** The Android side of fictura_flutter: each Dart call goes to the Fictura Android SDK. */
class FicturaFlutterPlugin : FlutterPlugin, ActivityAware, FicturaHostApi {
    private var app: Application? = null
    private var activity: WeakReference<Activity>? = null
    private var flutterApi: FicturaFlutterApi? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext as? Application
        flutterApi = FicturaFlutterApi(binding.binaryMessenger)
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        FicturaHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        FicturaHostApi.setUp(binding.binaryMessenger, null)
        scope.cancel()
        flutterApi = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = WeakReference(binding.activity) }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = WeakReference(binding.activity) }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    // ── Setup ────────────────────────────────────────────────────────────────

    override fun configure(message: ConfigureMessage) {
        val application = app ?: throw FlutterError("no_application", "The plugin has no Application context.", null)
        val options = FicturaOptions().apply {
            message.apiBase?.let { apiBase = it }
            // A Flutter app is one Activity and draws its own views, so screens and
            // taps come from Dart (FicturaNavigatorObserver, Fictura.screen).
            captureScreens = false
            captureTaps = false
            captureLifecycle = message.captureLifecycle
            captureErrors = message.captureNativeErrors
            release = message.release
            environment = message.environment
            debug = message.debug
            wrapper = FicturaWrapper("flutter", message.wrapperVersion)
        }
        Fictura.configure(application, message.apiKey, options)
        // Dart runs after the Activity started, so the SDK missed that start.
        activity?.get()?.let { Fictura.Wrapper.attach(it) }
        Fictura.onConversion = { data -> scope.launch { runCatching { flutterApi?.onConversion(data) } } }
    }

    // ── Events and users ─────────────────────────────────────────────────────

    override fun track(event: String, properties: Map<String, Any?>) = Fictura.track(event, properties)
    override fun screen(name: String, properties: Map<String, Any?>) = Fictura.screen(name, properties)
    override fun identify(userId: String, attributes: Map<String, Any?>?) = Fictura.identify(userId, attributes)
    override fun reset() = Fictura.reset()
    override fun setAttributes(attributes: Map<String, Any?>) = Fictura.setAttributes(attributes)
    override fun setOnce(attributes: Map<String, Any?>) = Fictura.setOnce(attributes)
    override fun unsetAttribute(key: String) = Fictura.unsetAttribute(key)
    override fun registerSuperProperties(properties: Map<String, Any?>) = Fictura.registerSuperProperties(properties)
    override fun optOut() = Fictura.optOut()
    override fun optIn() = Fictura.optIn()

    override suspend fun flush() = suspendCancellableCoroutine { done -> Fictura.flush { if (done.isActive) done.resume(Unit) } }

    override fun deviceId(): String? = Fictura.deviceId
    override fun setRevenueCatUserId(id: String?) = Fictura.setRevenueCatUserId(id)

    override fun setLegalUrls(terms: String?, privacy: String?) {
        Fictura.termsUrl = terms
        Fictura.privacyUrl = privacy
    }

    // ── Paywalls ─────────────────────────────────────────────────────────────

    override fun setPurchaseHandlerEnabled(enabled: Boolean) {
        Fictura.purchaseController = if (enabled) DartPurchaseController({ flutterApi }, { scope }) else null
    }

    override suspend fun register(placement: String, params: Map<String, Any?>): PlacementResultMessage =
        suspendCancellableCoroutine { done ->
            val act = activity?.get()
            if (act == null || act.isFinishing) {
                done.resume(PlacementResultMessage(featureUnlocked = false, outcome = "error", error = "no_activity"))
                return@suspendCancellableCoroutine
            }
            val outcome = PlacementOutcome(main) { if (done.isActive) done.resume(it) }
            Fictura.register(act, placement, params, outcome.handler) {
                outcome.featureUnlocked = true
                outcome.finishSoon()
            }
        }

    // ── Links and errors ─────────────────────────────────────────────────────

    override fun handleUrl(url: String): Boolean = Fictura.handle(Uri.parse(url))

    override fun captureError(error: ErrorMessage) {
        Fictura.Wrapper.captureError(error.type, error.message, error.stack, error.handled, error.level, error.mechanism, "dart",
            error.properties)
    }

    override fun captureMessage(message: String, level: String) = Fictura.captureMessage(message, level)
}

/**
 * Collects one `register` call's callbacks into a single answer. The SDK calls
 * the handler, then the feature, in one posted runnable, so the answer is sent
 * on the next turn of the main looper, once both have run.
 */
internal class PlacementOutcome(private val main: Handler, private val send: (PlacementResultMessage) -> Unit) {
    var featureUnlocked = false
    var kind = "skipped"
    var skipReason: String? = null
    var paywallResult: String? = null
    var error: String? = null
    var paywall: PaywallInfo? = null
    private var sent = false

    val handler = object : PlacementHandler() {
        override fun onPresent(info: PaywallInfo) { paywall = info }
        override fun onDismiss(info: PaywallInfo, result: String) {
            kind = "presented"; paywall = info; paywallResult = result; finishSoon()
        }
        override fun onSkip(reason: String) { kind = "skipped"; skipReason = reason; finishSoon() }
        override fun onError(error: String) { kind = "error"; this@PlacementOutcome.error = error; finishSoon() }
    }

    fun finishSoon() {
        main.post {
            if (sent) return@post
            sent = true
            send(message())
        }
    }

    fun message() = PlacementResultMessage(
        featureUnlocked = featureUnlocked, outcome = kind, skipReason = skipReason, paywallResult = paywallResult, error = error,
        paywall = paywall?.let {
            PaywallInfoMessage(it.paywallId, it.placement, it.campaignId, it.audienceId, it.experimentId, it.variantId,
                it.featureGating, it.presentationStyle, it.closeReason)
        },
    )
}

/** Paywalls buy through the app's Dart purchase handler (`Fictura.setPurchaseHandler`). */
internal class DartPurchaseController(
    private val api: () -> FicturaFlutterApi?,
    private val scope: () -> CoroutineScope,
) : PurchaseController {
    override fun packages(productIds: List<String>, done: (List<FicturaPackage>) -> Unit) {
        scope().launch {
            val list = runCatching { api()?.packages(productIds) }.getOrNull() ?: emptyList()
            done(list.map(::toPackage))
        }
    }

    override fun purchase(activity: Activity, pkg: FicturaPackage, context: PurchaseContext, done: (PurchaseResult) -> Unit) {
        scope().launch {
            val result = runCatching { api()?.purchase(toMessage(pkg), toMessage(context)) }
            done(result.fold({ toResult(it) }, { PurchaseResult.Failed(it.message ?: it.toString()) }))
        }
    }

    override fun restore(done: (Boolean) -> Unit) {
        scope().launch { done(runCatching { api()?.restore() }.getOrNull() ?: false) }
    }

    override fun isSubscribed(done: (Boolean) -> Unit) {
        scope().launch { done(runCatching { api()?.isSubscribed() }.getOrNull() ?: false) }
    }

    companion object {
        fun toPackage(m: PackageMessage) = FicturaPackage(
            id = m.id, productId = m.productId, priceString = m.priceString, priceMicros = m.priceMicros, currency = m.currency,
            period = m.period, trialDays = m.trialDays?.toInt(), trialEligible = m.trialEligible, title = m.title,
        )

        fun toMessage(p: FicturaPackage) = PackageMessage(
            id = p.id, productId = p.productId, priceString = p.priceString, priceMicros = p.priceMicros, currency = p.currency,
            period = p.period, trialDays = p.trialDays?.toLong(), trialEligible = p.trialEligible, title = p.title,
        )

        fun toMessage(c: PurchaseContext) =
            PurchaseContextMessage(c.placement, c.paywallId, c.campaignId, c.audienceId, c.experimentId, c.variantId)

        /** Android has no pending purchase: one waiting on approval keeps the paywall open, like a cancel. */
        fun toResult(m: PurchaseResultMessage?): PurchaseResult = when (m?.status) {
            "purchased" -> PurchaseResult.Purchased(m.transactionId, m.periodType)
            "cancelled", "pending" -> PurchaseResult.Cancelled
            null -> PurchaseResult.Failed("no_purchase_handler")
            else -> PurchaseResult.Failed(m.error ?: "purchase_failed")
        }
    }
}
