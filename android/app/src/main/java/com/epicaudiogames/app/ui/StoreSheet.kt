package com.epicaudiogames.app.ui

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.Packs
import com.epicaudiogames.app.Store

/**
 * A game's packs: what each adds, its price, and buying it (or its download, that it's paid for and waits to be
 * downloaded or for its payment, or that it's installed). A pack's own trouble shows under it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreSheet(game: GameInfo, store: Store, packs: Packs, onClose: () -> Unit) {
    val activity = LocalContext.current as? Activity
    ModalBottomSheet(onDismissRequest = onClose, containerColor = Palette.card) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(bottom = 12.dp)
                .windowInsetsPadding(WindowInsets.navigationBars),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedText("MORE FROM ${game.title.uppercase()}", size = 24.sp, fill = Palette.gold, maxLines = 2)
            store.installs    // read, so the sheet shows a pack as installed once it is
            for (pack in game.packs) {
                PackRow(pack, store, packs.isInstalled(pack)) { activity?.let { store.buy(it, pack) } }
            }
            store.message?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.no)
            }
            store.note?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.ink)
            }
            TextButton(onClick = store::restoreNow, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text("Restore purchases", color = Palette.title)
            }
        }
    }
}

@Composable
private fun PackRow(pack: PackInfo, store: Store, installed: Boolean, onBuy: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(pack.title, style = MaterialTheme.typography.titleLarge, color = Palette.title)
        if (pack.description.isNotEmpty()) {
            Text(pack.description, style = MaterialTheme.typography.bodyMedium, color = Palette.ink.copy(alpha = 0.85f))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("${(pack.size + 500_000) / 1_000_000} MB download", style = MaterialTheme.typography.bodySmall,
                color = Palette.ink.copy(alpha = 0.7f))
            Spacer(Modifier.weight(1f))
            val progress = store.downloading[pack.id]
            when {
                installed -> Pill("INSTALLED", Palette.headerLine, Palette.ink)
                progress != null -> LinearProgressIndicator(progress = { progress }, modifier = Modifier.weight(1f),
                    color = Palette.yes)
                pack.product in store.owned -> BuyButton("DOWNLOAD", onClick = store::restoreNow)
                pack.product in store.pending -> Pill("PAYMENT PENDING", Palette.headerLine, Palette.ink)
                else -> {
                    val price = store.prices[pack.product]
                    BuyButton(price ?: "GET", loading = price == null && store.loading, onClick = onBuy)
                }
            }
        }
        store.failed[pack.id]?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.no)
        }
    }
}

/** The price (GET until it's known, a spinner while it's asked for: GET still works), or DOWNLOAD. */
@Composable
private fun BuyButton(label: String, loading: Boolean = false, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = Palette.yes),
        shape = RoundedCornerShape(18.dp),
        modifier = if (loading) Modifier.semantics { contentDescription = label } else Modifier,
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        } else {
            Text(label, fontFamily = Lilita, fontSize = 18.sp, color = Color.White)
        }
    }
}
