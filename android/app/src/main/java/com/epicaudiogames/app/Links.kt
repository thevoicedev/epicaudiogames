package com.epicaudiogames.app

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * The website's pages and the support address, opened from the game's menu, Help and Settings (the stores want the
 * help and privacy pages reachable in the app). The same as iOS's App/Links.swift.
 */
object Links {
    const val SUPPORT = "https://epicaudiogames.com/support"
    const val PRIVACY = "https://epicaudiogames.com/privacy"
    const val ACCESSIBILITY = "https://epicaudiogames.com/accessibility"
    /** The website's support address (support.html). */
    const val EMAIL = "james@hugo.fm"

    /**
     * A web page, in the browser; a mailto: link (a help page's "Email …"), a new email in the phone's mail app. With
     * nothing on the phone to open it with, there's nothing to do.
     */
    fun open(context: Context, url: String) {
        val action = if (url.startsWith("mailto:")) Intent.ACTION_SENDTO else Intent.ACTION_VIEW
        runCatching { context.startActivity(Intent(action, Uri.parse(url))) }
    }

    /** A new email to [EMAIL] in the phone's mail app, its subject the app's name (as the website's link). */
    fun email(context: Context) {
        val subject = Uri.encode(context.getString(R.string.app_name))
        runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$EMAIL?subject=$subject"))) }
    }
}
