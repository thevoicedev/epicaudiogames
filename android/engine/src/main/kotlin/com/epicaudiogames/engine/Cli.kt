package com.epicaudiogames.engine

import java.io.File

/**
 * Play a game by typing: `gradlew :engine:run --args="noodle-rush" --console=plain` (from android/).
 * Every line the game says is printed as it would be shown in the app. Type an answer; an empty line is silence.
 * Commands: /vars (the variables), /restart, /quit.
 */
fun main(args: Array<String>) {
    val name = args.firstOrNull()
    if (name == null) {
        println("Usage: run --args=\"<game id or path to map.json>\"")
        return
    }
    val file = File(name).takeIf { it.isFile } ?: File("games/$name/map.json")
    if (!file.isFile) {
        println("No map at ${file.path}")
        return
    }
    val map = GameMap.load(file)
    val session = Session(map)
    println("== ${map.title} ==  (type your answers; an empty line is silence; /vars, /restart, /quit)")
    var turn = session.start()
    while (true) {
        show(map, turn)
        if (turn.quit) {
            println("[you left the game]")
            return
        }
        val end = turn.end
        if (end != null) {
            val next = end.next
            val canNext = end.kind == "chapter" && next != null && next in map.nodes
            println("[THE END: ${end.title}]" + when {
                canNext -> "  type next for the next chapter, again to start over, or /quit"
                end.locked != null -> "  (the next part is in the pack \"${end.locked}\")  type again to start over, or /quit"
                else -> "  type again to start over, or /quit"
            })
            val line = prompt() ?: return
            turn = when {
                line == "/quit" -> return
                line == "next" && canNext -> session.nextChapter()
                end.kind == "gameover" && end.retry != null -> session.restart(end.retry)
                else -> session.restart()
            }
            continue
        }
        val line = prompt() ?: return
        turn = when (line) {
            "/quit" -> return
            "/vars" -> { println("   ${session.vars}"); continue }
            "/restart" -> session.restart()
            "" -> session.silence()
            else -> {
                if (Commands.isPause(line)) {
                    println("[paused: press Enter to carry on]")
                    prompt() ?: return
                    turn = session.silence()
                    continue
                }
                session.answer(line)
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

private fun show(map: GameMap, turn: Turn) {
    for (step in turn.steps) {
        when (step) {
            is Step.Play -> for (line in step.lines) println("${map.who[line.who] ?: line.who}: ${line.text}")
            is Step.Num -> println("   [${step.variable}]")
            is Step.Bed -> if (step.path != null) println("   (${step.path.substringAfterLast('/')} plays underneath)")
            else -> Unit
        }
    }
    val buttons = turn.ask?.buttons.orEmpty()
    if (buttons.isNotEmpty()) println("   " + buttons.joinToString("  ") { "[${it.label}]" })
}
