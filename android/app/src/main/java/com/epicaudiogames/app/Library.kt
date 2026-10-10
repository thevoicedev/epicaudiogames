package com.epicaudiogames.app

import android.content.Context
import android.content.res.AssetManager
import com.epicaudiogames.engine.Saved
import org.json.JSONObject

/** A game on the list (assets/catalog.json, from games/catalog.json), with the packs that can be bought for it. */
data class GameInfo(val id: String, val title: String, val blurb: String, val free: String, val packs: List<PackInfo>)

/** A pack of more stories or levels: a Play in-app product, downloaded as <id>-<version>.zip from the pack server. */
data class PackInfo(
    val id: String,
    val game: String,
    val title: String,
    val description: String,
    val product: String,
    val version: Int,
    val size: Long,
    val sha256: String,
)

object Catalog {
    fun load(assets: AssetManager): List<GameInfo> {
        val games = JSONObject(assets.open("catalog.json").bufferedReader().use { it.readText() }).getJSONArray("games")
        return (0 until games.length()).map { i ->
            val g = games.getJSONObject(i)
            val packs = g.optJSONArray("packs")
            GameInfo(
                g.getString("id"), g.getString("title"), g.optString("blurb"), g.optString("free"),
                (0 until (packs?.length() ?: 0)).map { j ->
                    val p = packs!!.getJSONObject(j)
                    PackInfo(p.getString("id"), g.getString("id"), p.getString("title"), p.optString("description"),
                        p.getString("product"), p.getInt("version"), p.getLong("size"), p.getString("sha256"))
                },
            )
        }
    }
}

/** Each game's place: the node it waits at, its variables, and whether it has ended. Kept between plays. */
class Saves(context: Context) {
    private val prefs = context.getSharedPreferences("saves", Context.MODE_PRIVATE)

    fun load(game: String): Saved? {
        val json = prefs.getString(game, null) ?: return null
        return runCatching {
            val o = JSONObject(json)
            val vars = o.getJSONObject("vars")
            Saved(
                node = o.getString("node"),
                vars = vars.keys().asSequence().associateWith { k ->
                    when (val v = vars.get(k)) {
                        is Number -> v.toDouble()
                        else -> v
                    }
                },
                ended = o.optBoolean("ended"),
            )
        }.getOrNull()
    }

    fun store(game: String, saved: Saved) {
        val o = JSONObject()
            .put("node", saved.node)
            .put("vars", JSONObject(saved.vars))
            .put("ended", saved.ended)
        prefs.edit().putString(game, o.toString()).apply()
    }

    fun clear(game: String) = prefs.edit().remove(game).apply()

    /** Every game's place, and any kept aside (a debug build's EpicReset: no game is "In progress"). */
    fun clearAll() = prefs.edit().clear().apply()

    /** A game that was left part-way (not at its end). */
    fun inProgress(game: String): Boolean = load(game)?.let { !it.ended } ?: false
}
