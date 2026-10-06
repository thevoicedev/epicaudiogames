package com.epicaudiogames.app

import android.app.Activity
import android.content.Context
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Buying packs (Google Play Billing, one-time products) and getting them. After a purchase, or for one made
 * before (on this phone or another), the pack's zip is downloaded from the pack server, checked and unpacked
 * ([Packs]); then the purchase is acknowledged, as Play requires within three days. A download that fails is tried
 * again the next time the store opens.
 *
 * Debug builds also install any <pack>-<version>.zip found in the app's external files/incoming folder (put there
 * with adb push), to try packs without a store or a server.
 */
class Store(
    private val context: Context,
    games: List<GameInfo>,
    private val packs: Packs,
    private val scope: CoroutineScope,
) : PurchasesUpdatedListener {
    private val all = games.flatMap { it.packs }

    /** Each product's price, as Play shows it ("£1.99"), once known. */
    val prices = mutableStateMapOf<String, String>()
    /** The packs downloading, and how far each has got (0 to 1). */
    val downloading = mutableStateMapOf<String, Float>()
    /** Something to tell the player (a failed download, the store not being there). */
    var message by mutableStateOf<String?>(null)
    /** Bumped when a pack is installed, so the screens and maps pick it up. */
    var installs by mutableIntStateOf(0)
        private set
    var ready by mutableStateOf(false)
        private set

    private val details = mutableMapOf<String, ProductDetails>()
    private val client = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun start() {
        if (BuildConfig.DEBUG) scope.launch { installIncoming() }
        connect()
    }

    private fun connect() {
        if (all.isEmpty() || client.isReady) return
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) return
                scope.launch {
                    queryProducts()
                    restore()
                    ready = true
                }
            }

            override fun onBillingServiceDisconnected() {
                ready = false
            }
        })
    }

    private suspend fun queryProducts() {
        val products = all.map {
            QueryProductDetailsParams.Product.newBuilder().setProductId(it.product)
                .setProductType(BillingClient.ProductType.INAPP).build()
        }
        val result = client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(products).build())
        for (d in result.productDetailsList.orEmpty()) {
            details[d.productId] = d
            d.oneTimePurchaseOfferDetails?.formattedPrice?.let { prices[d.productId] = it }
        }
    }

    /** The packs bought before: any not on this phone are downloaded, and any purchase not acknowledged is. */
    suspend fun restore() {
        if (!client.isReady) {
            connect()
            return
        }
        val result = client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        for (p in result.purchasesList) handle(p)
    }

    fun buy(activity: Activity, pack: PackInfo) {
        val d = details[pack.product]
        if (d == null) {
            message = "The store isn't available right now. Check that you're signed in to Google Play."
            connect()
            return
        }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()))
            .build()
        client.launchBillingFlow(activity, params)
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> purchases.orEmpty().forEach { scope.launch { handle(it) } }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> scope.launch { restore() }
            BillingClient.BillingResponseCode.USER_CANCELED -> Unit
            else -> message = "The purchase didn't go through. Please try again."
        }
    }

    private suspend fun handle(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return    // pending: Play tells us later
        var ok = true
        for (product in purchase.products) {
            val pack = all.firstOrNull { it.product == product } ?: continue
            if (!packs.isInstalled(pack)) ok = download(pack) && ok
        }
        if (ok && !purchase.isAcknowledged) {
            client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
        }
    }

    /** Downloads a pack's zip and installs it. False if it couldn't. */
    private suspend fun download(pack: PackInfo): Boolean {
        if (pack.id in downloading) return false
        if (BuildConfig.PACKS_URL.isEmpty()) {
            message = "Packs can't be downloaded in this version of the app yet."
            return false
        }
        downloading[pack.id] = 0f
        return try {
            withContext(Dispatchers.IO) {
                val zip = File(context.cacheDir, "${pack.id}-${pack.version}.zip")
                val conn = URL("${BuildConfig.PACKS_URL.trimEnd('/')}/${pack.id}-${pack.version}.zip")
                    .openConnection() as HttpURLConnection
                conn.connectTimeout = 15_000
                conn.readTimeout = 30_000
                try {
                    check(conn.responseCode == 200) { "HTTP ${conn.responseCode}" }
                    conn.inputStream.use { input ->
                        zip.outputStream().use { out ->
                            val buf = ByteArray(1 shl 16)
                            var done = 0L
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                done += n
                                val progress = (done.toFloat() / pack.size).coerceIn(0f, 1f)
                                withContext(Dispatchers.Main) { downloading[pack.id] = progress }
                            }
                        }
                    }
                } finally {
                    conn.disconnect()
                }
                try {
                    packs.install(pack, zip)
                } finally {
                    zip.delete()
                }
            }
            installs++
            true
        } catch (e: Exception) {
            message = "Couldn't download ${pack.title}. Check your connection, and open the store again to retry."
            false
        } finally {
            downloading.remove(pack.id)
        }
    }

    private suspend fun installIncoming() {
        val dir = context.getExternalFilesDir("incoming") ?: return
        for (pack in all) {
            val zip = File(dir, "${pack.id}-${pack.version}.zip")
            if (!zip.isFile || packs.isInstalled(pack)) continue
            val done = withContext(Dispatchers.IO) { runCatching { packs.install(pack, zip) }.isSuccess }
            if (done) installs++ else message = "${zip.name} isn't the catalog's ${pack.id}."
        }
    }
}
