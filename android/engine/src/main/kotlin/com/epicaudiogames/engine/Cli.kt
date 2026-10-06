package com.epicaudiogames.engine

import com.epicaudiogames.engine.nuclear.Lines
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File

/**
 * Play a game by typing: `gradlew :engine:run --args="noodle-rush" --console=plain` (from android/).
 * Every line the game says is printed as it would be shown in the app. Type an answer; an empty line is silence.
 * Commands: /vars (the variables), /restart, /quit.
 *
 * `--args="--nuclear-lines <file>"` writes every line of Nuclear War's announcer (for tools/games/nuclearwar.py).
 */
fun main(args: Array<String>) {
    val name = args.firstOrNull()
    if (name == null) {
        println("Usage: run --args=\"<game id or path to map.json>\"  or  --args=\"--nuclear-lines <file>\"")
        return
    }
    if (name == "--nuclear-lines") {
        val out = File(args.getOrNull(1) ?: "games/nuclear-war/lines.json")
        val lines = Lines.all().map { p ->
            buildJsonObject {
                put("text", p.text)
                if (p.speak != p.text) put("speak", p.speak)
                if (p.before.isNotEmpty()) put("before", p.before)
                if (p.after.isNotEmpty()) put("after", p.after)
            }
        }
        out.parentFile?.mkdirs()
        out.writeText(JsonArray(lines).toString().replace("},{", "},\n{") + "\n")
        println("${lines.size} lines -> ${out.path}")
        return
    }
    val game: Play
    val vars: () -> Any
    if (name == NuclearWar.ID) {
        val clips = File("games/${NuclearWar.ID}/clips.json")
        val nw = NuclearWar(if (clips.isFile) NuclearAudio.load(clips) else NuclearAudio.placeholder())
        game = nw
        vars = { nw.save().vars["state"] ?: "" }
    } else {
        val file = File(name).takeIf { it.isFile } ?: File("games/$name/map.json")
        if (!file.isFile) {
            println("No map at ${file.path}")
            return
        }
        val session = Session(GameMap.load(file))
        game = session
        vars = { session.vars }
    }
    println("== $name ==  (type your answers; an empty line is silence; /vars, /restart, /quit)")
    var turn = game.start()
    while (true) {
        show(game.who, turn)
        if (turn.quit) {
            println("[you left the game]")
            return
        }
        val end = turn.end
        if (end != null) {
            val next = end.next
            val canNext = end.kind == "chapter" && next != null && game.hasChapter(next)
            println("[THE END: ${end.title}]" + when {
                canNext -> "  type next for the next chapter, again to start over, or /quit"
                end.locked != null -> "  (the next part is in the pack \"${end.locked}\")  type again to start over, or /quit"
                else -> "  type again to start over, or /quit"
            })
            val line = prompt() ?: return
            turn = when {
                line == "/quit" -> return
                line == "next" && canNext -> game.nextChapter()
                end.kind == "gameover" && end.retry != null -> game.restart(end.retry)
                else -> game.restart()
            }
            continue
        }
        val line = prompt() ?: return
        turn = when (line) {
            "/quit" -> return
            "/vars" -> { println("   ${vars()}"); continue }
            "/restart" -> game.restart()
            "" -> game.silence()
            else -> {
                if (Commands.isPause(line)) {
                    println("[paused: press Enter to carry on]")
                    prompt() ?: return
                    turn = game.silence()
                    continue
                }
                game.answer(line)
            }
        }
        turn.heard?.let { println("   (heard: ${it.how})") }
    }
}

private fun prompt(): String? {
    print("> ")
    System.out.flush()
    return readlnOrNull()?.trim()
}

/** A turn's lines as the app shows them: a line that carries on joins the one before. */
private fun show(who: Map<String, String>, turn: Turn) {
    var carry: String? = null
    for (step in turn.steps) {
        when (step) {
            is Step.Play -> for (line in step.lines) {
                val text = carry?.let { "$it ${line.text}" } ?: "${who[line.who] ?: line.who}: ${line.text}"
                if (line.more) carry = text else {
                    println(text)
                    carry = null
                }
            }
            is Step.Num -> println("   [${step.variable}]")
            is Step.Bed -> if (step.path != null) println("   (${step.path.substringAfterLast('/')} plays underneath)")
            else -> Unit
        }
    }
    carry?.let { println(it) }
    val buttons = turn.ask?.buttons.orEmpty()
    if (buttons.isNotEmpty()) println("   " + buttons.joinToString("  ") { "[${it.label}]" })
}
