package com.epicaudiogames.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * The mic, and (Android 13+) the notification that shows the game while the screen is off: whether they're allowed,
 * whether they've been asked for, and the way to the app's page in the phone's settings. Used by the game screen, and
 * by the game's service ([BackgroundPlay]), which may only use the mic in the background once it's allowed.
 */
object Permissions {
    /** The mic has been asked for since the app started: opening another game doesn't ask again (the mic button does). */
    var micAsked = false
    /** Notifications have been asked for (with the mic) since the app started. */
    var notificationsAsked = false

    fun micGranted(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /**
     * Android would ask for the mic again, saying why (refused once, not for good). False before it's ever asked, and
     * once it's refused for good, when asking it answers at once without asking the player.
     */
    fun micRationale(context: Context): Boolean = context.findActivity()?.let {
        ActivityCompat.shouldShowRequestPermissionRationale(it, Manifest.permission.RECORD_AUDIO)
    } ?: false

    /** Android 13+'s notification permission, if it isn't granted yet (before 13, notifications need none). */
    fun notificationPermission(context: Context): String? =
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) Manifest.permission.POST_NOTIFICATIONS else null

    /** The app's page in the phone's settings, where the mic can be turned on once Android won't ask any more. */
    fun openAppSettings(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
        )
    }
}

/** The activity a composable's context belongs to (for permission questions, and the window's keep-awake flag). */
fun Context.findActivity(): Activity? {
    var c: Context = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}
