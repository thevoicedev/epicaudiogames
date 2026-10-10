package com.epicaudiogames.app

import org.w3c.dom.Element
import java.io.File
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The app's words as the JVM tests read them: res/values/strings.xml itself (the tests run in android/app), found by
 * the R ids the code uses, with their placeholders filled as Android fills them (String.format, only when there's
 * something to put in) and the strings file's escapes undone. So a test of a label made in plain Kotlin checks the
 * words the player gets (PackUiStateTest, CircleActionTest), as the iOS tests check their literals.
 */
object TestWords : Words {
    val file = File("src/main/res/values/strings.xml")
    private val root: Element =
        DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement

    /** Each string's text, by its name. */
    val strings: Map<String, String> =
        root.children("string").associate { it.getAttribute("name") to unescape(it.textContent) }

    /** Each plural's forms ("one", "other"), by its name. */
    private val plurals: Map<String, Map<String, String>> = root.children("plurals").associate { p ->
        p.getAttribute("name") to p.children("item").associate { it.getAttribute("quantity") to unescape(it.textContent) }
    }

    private val stringNames = ids(R.string::class.java)
    private val pluralNames = ids(R.plurals::class.java)

    override fun text(id: Int, vararg args: Any): String {
        val name = stringNames[id] ?: error("no string has the id $id")
        val text = strings[name] ?: error("strings.xml has no string $name")
        return if (args.isEmpty()) text else String.format(Locale.UK, text, *args)
    }

    override fun plural(id: Int, count: Int, vararg args: Any): String {
        val name = pluralNames[id] ?: error("no plural has the id $id")
        val forms = plurals[name] ?: error("strings.xml has no plural $name")
        // English: one for 1, other for everything else.
        val form = forms[if (count == 1) "one" else "other"] ?: forms.getValue("other")
        return String.format(Locale.UK, form, *args)
    }

    private fun Element.children(tag: String): List<Element> {
        val nodes = getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }.filter { it.parentNode == this }
    }

    private fun ids(type: Class<*>): Map<Int, String> = type.fields.associate { it.getInt(null) to it.name }

    /**
     * A string as Android reads it from the file: runs of white space as one space (outside double quotes), the
     * quotes themselves gone, and the backslash escapes (\', \", \n, \t, \\, \@, \?) undone.
     */
    fun unescape(raw: String): String {
        val out = StringBuilder()
        var quoted = false
        var space = false
        var i = 0
        while (i < raw.length) {
            val ch = raw[i]
            when {
                ch == '\\' && i + 1 < raw.length -> {
                    out.append(
                        when (val next = raw[i + 1]) {
                            'n' -> '\n'
                            't' -> '\t'
                            else -> next
                        },
                    )
                    space = false
                    i++
                }
                ch == '"' -> quoted = !quoted
                ch.isWhitespace() && !quoted -> {
                    if (!space) out.append(' ')
                    space = true
                }
                else -> {
                    out.append(ch)
                    space = false
                }
            }
            i++
        }
        return out.toString().trim()
    }
}
