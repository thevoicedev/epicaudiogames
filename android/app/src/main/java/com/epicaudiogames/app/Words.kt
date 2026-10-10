package com.epicaudiogames.app

import android.content.Context
import android.content.res.Resources
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

/**
 * The app's words (res/values/strings.xml: every word the app shows or says, so it can be translated) for code that
 * isn't a screen's own: a button's name made in plain Kotlin (PackRows.kt), the talking circle's (MicPolicy.kt), the
 * game's notes, the store's messages and the notification. On the phone they're the app's resources ([of]); the JVM
 * tests read the same strings file (TestWords), so they check the words themselves. A screen uses stringResource
 * (and [rememberWords], below, for these). iOS: Text("…"), whose words Localizable.xcstrings gathers.
 */
interface Words {
    /** The string [id], with [args] put in its placeholders ("Get %1$s"). */
    fun text(@StringRes id: Int, vararg args: Any): String

    /** The plural [id]'s form for [count] ("1 second", "6 seconds"), with [args] put in. */
    fun plural(@PluralsRes id: Int, count: Int, vararg args: Any): String

    companion object {
        /** The words in [context]'s language (only English for now). */
        fun of(context: Context): Words = ResourceWords(context.resources)
    }
}

/** [Words] from the app's [resources]. */
class ResourceWords(private val resources: Resources) : Words {
    override fun text(id: Int, vararg args: Any): String = resources.getString(id, *args)

    override fun plural(id: Int, count: Int, vararg args: Any): String = resources.getQuantityString(id, count, *args)
}

/**
 * The app's [Words] where a screen draws, as stringResource reads them (a change of language draws them again): for
 * the words plain Kotlin makes (a button's name), and in a lambda that isn't a composable (a choice's label).
 */
@Composable
fun rememberWords(): Words {
    val configuration = LocalConfiguration.current
    val resources = LocalContext.current.resources
    return remember(resources, configuration) { ResourceWords(resources) }
}
