package co.fictura.fictura_flutter

import co.fictura.sdk.FicturaPackage
import co.fictura.sdk.PaywallInfo
import co.fictura.sdk.PurchaseContext
import co.fictura.sdk.PurchaseResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class FicturaFlutterPluginTest {
    @Test
    fun purchaseResultsMapToTheSdk() {
        assertEquals(PurchaseResult.Purchased("tx_1", "trial"),
            DartPurchaseController.toResult(PurchaseResultMessage(status = "purchased", transactionId = "tx_1", periodType = "trial")))
        assertEquals(PurchaseResult.Cancelled, DartPurchaseController.toResult(PurchaseResultMessage(status = "cancelled")))
        assertEquals(PurchaseResult.Cancelled, DartPurchaseController.toResult(PurchaseResultMessage(status = "pending")),
            "Android has no pending purchase: the paywall stays open")
        assertEquals(PurchaseResult.Failed("card declined"),
            DartPurchaseController.toResult(PurchaseResultMessage(status = "failed", error = "card declined")))
        assertEquals(PurchaseResult.Failed("purchase_failed"), DartPurchaseController.toResult(PurchaseResultMessage(status = "odd")))
        assertEquals(PurchaseResult.Failed("no_purchase_handler"), DartPurchaseController.toResult(null))
    }

    @Test
    fun packagesRoundTrip() {
        val pkg = FicturaPackage("\$rc_monthly", "pro_monthly", "US$9.99", 9_990_000, "USD", "monthly", trialDays = 7,
            trialEligible = true, title = "Pro")
        val message = DartPurchaseController.toMessage(pkg)
        assertEquals(9_990_000L, message.priceMicros)
        assertEquals(7L, message.trialDays)
        assertEquals(pkg, DartPurchaseController.toPackage(message))
        val ctx = DartPurchaseController.toMessage(PurchaseContext("export_hd", "pw_1", "c_1", null, "e_1", "v_2"))
        assertEquals("export_hd", ctx.placement)
        assertEquals("v_2", ctx.variantId)
        assertNull(ctx.audienceId)
    }

    @Test
    fun placementOutcomeCarriesThePaywall() {
        val outcome = PlacementOutcome(android.os.Handler(android.os.Looper.getMainLooper())) {}
        val info = PaywallInfo("pw_1", "export_hd", "c_1", "a_1", "e_1", "v_1", "gated", "fullscreen", "manual")
        outcome.handler.onPresent(info)
        val presented = outcome.message()
        assertEquals("skipped", presented.outcome, "nothing has closed yet")
        assertEquals("pw_1", presented.paywall?.paywallId)
        outcome.kind = "presented"
        outcome.paywallResult = "declined"
        val m = outcome.message()
        assertFalse(m.featureUnlocked)
        assertEquals("gated", m.paywall?.featureGating)
        assertEquals("manual", m.paywall?.closeReason)
        outcome.featureUnlocked = true
        assertTrue(outcome.message().featureUnlocked)
    }
}
