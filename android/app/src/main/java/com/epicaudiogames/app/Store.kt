package com.epicaudiogames.app

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.system.ErrnoException
import android.system.OsConstants
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.epicaudiogames.app.analytics.Event
import com.epicaudiogames.app.analytics.Events
import com.epicaudiogames.app.analytics.NoAnalytics
import com.epicaudiogames.app.analytics.PurchaseResult
import com.epicaudiogames.app.analytics.RestoreResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Buying packs (Google Play Billing, one-time products) and getting them. A purchase is acknowledged as soon as it's
 * paid for (Play refunds one left unacknowledged for three days); then the pack's zip is downloaded from the pack
 * server, checked and unpacked ([Packs]). A pack bought before (on this phone or another) that isn't here is
 * downloaded whenever the purchases are read: at launch, when the app comes back, when a store sheet opens, and a few
 * times more by itself after a download fails.
 *
 * Debug builds also install any <pack>-<version>.zip found in the app's external files/incoming folder (put there
 * with adb push), to try packs without a store or a server.
 *
 * What happens goes to [onEvent], for the usage data (docs/DESIGN.md › Usage data): a purchase started and how it
 * ended, Restore purchases pressed and what it found, and each download (which pack, whether it installed, how long
 * it took and how much came down). Never a price, an order or a Play account.
 */
class Store(
    private val context: Context,
    games: List<GameInfo>,
    private val packs: Packs,
    private val scope: CoroutineScope,
    /** A pack was installed: called once for each install (the open game may be waiting for it). */
    private val onInstalled: (PackInfo) -> Unit = {},
    /** What happens, for the usage data: an event's name and its details (as GameController's onEvent). */
    private val onEvent: (String, Map<String, Any>) -> Unit = NoAnalytics::track,
    /**
     * Where packs are downloaded from (<url>/<pack>-<version>.zip): the build's (gradle property epicPacksUrl), or a
     * debug build's launch's (DebugLaunch's EpicPacksURL). Empty: packs can't be downloaded, so none is sold.
     */
    private val packsUrl: String = BuildConfig.PACKS_URL,
) : PurchasesUpdatedListener {
    private val all = games.flatMap { it.packs }
    /** The app's words, for what the store tells the player ([message], [note], [failed]). */
    private val words = Words.of(context)
    /** The product a purchase was started for, until Play says how it ended. */
    private var buying: String? = null

    /** Each product's price, as Play shows it ("£1.99"), once known. */
    val prices = mutableStateMapOf<String, String>()
    /** The prices are being asked for (the sheet's Get shows a spinner). */
    var loading by mutableStateOf(false)
        private set
    /** The packs downloading, and how far each has got (0 to 1). */
    val downloading = mutableStateMapOf<String, Float>()
    /**
     * Why a pack's purchase or download didn't go through, by pack: its row says so, under it (docs/DESIGN.md › Shop:
     * failures under the row), where the player pressed Buy. Said there, TalkBack hears it: the Shop's list draws only
     * what's in sight, and the store's [message] at its foot may not be.
     */
    val failed = mutableStateMapOf<String, String>()
    /** The products paid for (their packs, if not here, show Download), and those waiting for their payment. */
    val owned = mutableStateMapOf<String, Boolean>()
    val pending = mutableStateMapOf<String, Boolean>()
    /**
     * Something to tell the player that isn't about one pack (the store not being there as purchases are restored); a
     * purchase that doesn't go through is said under its pack's row ([failed]).
     */
    var message by mutableStateOf<String?>(null)
    /** How "Restore purchases" went, when nothing went wrong. */
    var note by mutableStateOf<String?>(null)
    /** Bumped when a pack is installed, so the screens and maps pick it up. */
    var installs by mutableIntStateOf(0)
        private set

    private val details = mutableMapOf<String, ProductDetails>()
    private var connecting = false
    /** The downloads going: a second ask for one waits for it, instead of starting another. */
    private val inFlight = mutableMapOf<String, Deferred<Boolean>>()
    /** How many times each pack's failed download has been tried again by itself. */
    private val retries = mutableMapOf<String, Int>()
    private val client = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun start() {
        if (BuildConfig.DEBUG) scope.launch { installIncoming() }
        connect()
    }

    /** The app's model is gone: the connection to Play goes with it. */
    fun close() = client.endConnection()

    /** Something happened in the shop: to [onEvent]. */
    private fun emit(e: Event) = onEvent(e.name, e.props)

    private fun connect() {
        if (all.isEmpty() || client.isReady || connecting) return
        connecting = true
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                connecting = false
                if (result.responseCode != BillingClient.BillingResponseCode.OK) return
                scope.launch {
                    queryProducts()
                    restore()
                }
            }

            override fun onBillingServiceDisconnected() {
                connecting = false
            }
        })
    }

    private suspend fun queryProducts() {
        if (loading) return
        loading = true
        try {
            val products = all.map {
                QueryProductDetailsParams.Product.newBuilder().setProductId(it.product)
                    .setProductType(BillingClient.ProductType.INAPP).build()
            }
            val result = client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(products).build())
            for (d in result.productDetailsList.orEmpty()) {
                details[d.productId] = d
                d.oneTimePurchaseOfferDetails?.formattedPrice?.let { prices[d.productId] = it }
            }
        } finally {
            loading = false
        }
    }

    /**
     * The packs bought before: any not on this phone are downloaded, and any purchase not acknowledged is. Prices
     * still missing are asked for again. [asked]: the sheet's "Restore purchases", which says how it went.
     */
    suspend fun restore(asked: Boolean = false) {
        if (!client.isReady) {
            if (asked) {
                message = words.text(R.string.store_unavailable)
                emit(Events.restore(RestoreResult.FAILED, count = 0))
            }
            connect()
            return
        }
        if (all.any { it.product !in prices }) queryProducts()
        val result = client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
            if (asked) {
                message = words.text(R.string.store_restore_failed)
                emit(Events.restore(RestoreResult.FAILED, count = 0))
            }
            return
        }
        var ok = true
        for (p in result.purchasesList) ok = handle(p) && ok
        if (asked) {
            val paid = result.purchasesList.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            if (ok) {
                note = words.text(if (paid.isNotEmpty()) R.string.store_restored else R.string.store_nothing_to_restore)
            }
            // (A pack that then didn't download says so itself, and has its own pack_download.)
            val count = all.count { pack -> paid.any { pack.product in it.products } }
            emit(Events.restore(if (count > 0) RestoreResult.RESTORED else RestoreResult.NONE, count))
        }
    }

    /** The sheet's "Restore purchases", in the store's scope: closing the sheet doesn't stop it. */
    fun restoreNow() {
        message = null
        note = null
        scope.launch { restore(asked = true) }
    }

    /** A store sheet opening (or closing): what was said before goes; opening reads the purchases again. */
    fun sheet(open: Boolean) {
        message = null
        note = null
        if (open) {
            failed.clear()
            scope.launch { restore() }
        }
    }

    fun buy(activity: Activity, pack: PackInfo) {
        message = null
        note = null
        failed.remove(pack.id)
        if (packsUrl.isEmpty()) {
            // As on iOS (L6): nothing is bought that couldn't be downloaded.
            failed[pack.id] = words.text(R.string.store_no_server)
            return
        }
        val d = details[pack.product]
        if (d == null) {
            failed[pack.id] = words.text(R.string.store_unavailable)
            if (client.isReady) scope.launch { queryProducts() } else connect()
            return
        }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()))
            .build()
        buying = pack.product
        emit(Events.purchaseStart(pack.product))
        purchaseWent(client.launchBillingFlow(activity, params).responseCode)
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
            // Bought, or waiting for its payment (and later, from Play, bought after all).
            for (p in purchases.orEmpty()) {
                val outcome = when (p.purchaseState) {
                    Purchase.PurchaseState.PURCHASED -> PurchaseResult.PURCHASED
                    Purchase.PurchaseState.PENDING -> PurchaseResult.PENDING
                    else -> continue
                }
                for (product in p.products) {
                    if (all.any { it.product == product }) emit(Events.purchaseResult(product, outcome))
                }
            }
            buying = null
            purchases.orEmpty().forEach { scope.launch { handle(it) } }
        } else {
            purchaseWent(result.responseCode)
        }
    }

    /** A purchase that didn't come to a purchase (launching it, or its answer): what to say and do. */
    private fun purchaseWent(code: Int) {
        val product = buying
        val outcome = when (code) {
            BillingClient.BillingResponseCode.OK -> null        // Play's sheet is up: it says how it ends
            BillingClient.BillingResponseCode.USER_CANCELED -> PurchaseResult.CANCELLED
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> PurchaseResult.OWNED
            else -> PurchaseResult.FAILED
        }
        if (outcome != null) {
            product?.let { emit(Events.purchaseResult(it, outcome)) }
            buying = null
        }
        when (code) {
            BillingClient.BillingResponseCode.OK, BillingClient.BillingResponseCode.USER_CANCELED -> Unit
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> scope.launch { restore() }
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED -> {
                didntGoThrough(product, words.text(R.string.store_unavailable))
                connect()
            }
            else -> didntGoThrough(product, words.text(R.string.store_purchase_failed))
        }
    }

    /**
     * A purchase of [product] that didn't go through, and why: under its pack's row ([failed]), or, with no purchase
     * known to be under way, as the store's [message].
     */
    private fun didntGoThrough(product: String?, why: String) {
        val bought = all.filter { it.product == product }
        if (bought.isEmpty()) message = why else bought.forEach { failed[it.id] = why }
    }

    /** A purchase: acknowledged once it's paid for, then its packs downloaded if they aren't here (false if one isn't). */
    private suspend fun handle(purchase: Purchase): Boolean {
        val bought = all.filter { it.product in purchase.products }
        if (purchase.purchaseState == Purchase.PurchaseState.PENDING) bought.forEach { pending[it.product] = true }
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return true    // pending: Play tells us later
        bought.forEach {
            pending.remove(it.product)
            owned[it.product] = true
        }
        if (!purchase.isAcknowledged) {
            client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
        }
        var ok = true
        for (pack in bought) if (!packs.isInstalled(pack)) ok = download(pack) && ok
        return ok
    }

    /** Downloads a pack's zip and installs it, in the store's scope whoever asks. False if it couldn't. */
    private suspend fun download(pack: PackInfo): Boolean {
        inFlight[pack.id]?.let { return it.await() }
        if (packsUrl.isEmpty()) {
            message = words.text(R.string.store_no_server)
            return false
        }
        if (!packs.hasRoom(pack)) {
            failed[pack.id] = noRoom(pack)
            return false
        }
        val job = scope.async(start = CoroutineStart.LAZY) {
            try {
                fetch(pack)
            } finally {
                inFlight.remove(pack.id)
            }
        }
        inFlight[pack.id] = job
        return job.await()
    }

    private suspend fun fetch(pack: PackInfo): Boolean {
        downloading[pack.id] = 0f
        failed.remove(pack.id)
        val zip = File(context.cacheDir, "${pack.id}-${pack.version}.zip")
        // For the usage data: how long it took, and how much came down.
        val started = SystemClock.elapsedRealtime()
        var done = 0L
        val seconds = { (SystemClock.elapsedRealtime() - started) / 1000 }
        return try {
            withContext(Dispatchers.IO) {
                val conn = URL("${packsUrl.trimEnd('/')}/${pack.id}-${pack.version}.zip")
                    .openConnection() as HttpURLConnection
                conn.connectTimeout = 15_000
                conn.readTimeout = 30_000
                try {
                    check(conn.responseCode == 200) { "HTTP ${conn.responseCode}" }
                    conn.inputStream.use { input ->
                        zip.outputStream().use { out ->
                            val buf = ByteArray(1 shl 16)
                            var shown = 0f
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                done += n
                                val progress = (done.toFloat() / pack.size).coerceIn(0f, 1f)
                                if (progress - shown >= 0.01f || progress == 1f) {
                                    shown = progress
                                    withContext(Dispatchers.Main) { downloading[pack.id] = progress }
                                }
                            }
                        }
                    }
                } finally {
                    conn.disconnect()
                }
                packs.install(pack, zip)
            }
            retries.remove(pack.id)
            installs++
            emit(Events.packDownload(pack.id, installed = true, seconds(), done))
            onInstalled(pack)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(Events.packDownload(pack.id, installed = false, seconds(), done))
            if (outOfSpace(e)) {
                failed[pack.id] = noRoom(pack)
            } else {
                failed[pack.id] = words.text(R.string.store_download_failed, pack.title)
                retryLater(pack)
            }
            false
        } finally {
            zip.delete()
            downloading.remove(pack.id)
        }
    }

    /** A download that failed is tried again by itself, a while later, a few times (opening a sheet tries too). */
    private fun retryLater(pack: PackInfo) {
        val n = retries[pack.id] ?: 0
        if (n >= RETRY_DELAYS.size) return
        retries[pack.id] = n + 1
        scope.launch {
            delay(RETRY_DELAYS[n])
            if (!packs.isInstalled(pack)) restore()
        }
    }

    private suspend fun installIncoming() {
        val dir = context.getExternalFilesDir("incoming") ?: return
        for (pack in all) {
            val zip = File(dir, "${pack.id}-${pack.version}.zip")
            if (!zip.isFile || packs.isInstalled(pack)) continue
            val done = withContext(Dispatchers.IO) { runCatching { packs.install(pack, zip) }.isSuccess }
            if (done) {
                installs++
                onInstalled(pack)
            } else {
                message = words.text(R.string.store_incoming_wrong, zip.name, pack.id)
            }
        }
    }

    /** Not enough room on the phone for [pack]: what it needs, unpacked from its download, to the megabyte. */
    private fun noRoom(pack: PackInfo): String =
        words.text(R.string.store_no_room, pack.title, (pack.size * 22 / 10 + 500_000) / 1_000_000)

    private companion object {
        /** How long to wait (ms) before trying a failed download again, each time. */
        val RETRY_DELAYS = longArrayOf(15_000, 60_000, 300_000)

        /** A full disk (ENOSPC), anywhere in the cause chain. */
        fun outOfSpace(e: Throwable): Boolean = generateSequence(e) { it.cause }.any {
            (it is ErrnoException && it.errno == OsConstants.ENOSPC) || it.message?.contains("ENOSPC") == true
        }
    }
}
