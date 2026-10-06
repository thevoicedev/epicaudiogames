// Reads each radio play's flow out of the Mini Games skill code (the all-minigames-sites repo next to this one, or
// MINIGAMES_DIR) and writes it as plain JSON to tools/flows/<game>.json, for build_maps.py.
//
// Two ways in, both read-only:
// - a flow table (an array literal such as NOODLE_GAME_FLOW) is cut out of the source and evaluated with our own
//   stand-ins for the helpers it calls (noodleScene, frPass, puzzleFlow...), which record their arguments;
// - word lists and other module-level constants are read by loading the module with one extra export line.
// Nothing from Mini Games runs in the app: this only turns its content into data.
//
// Usage (from the repo root): node tools/extract_flows.js
const fs = require("fs");
const path = require("path");
const Module = require("module");

const ROOT = path.join(__dirname, "..");
const MINI = process.env.MINIGAMES_DIR || path.join(ROOT, "..", "all-minigames-sites");
const GAMES = path.join(MINI, "alexa", "lambda", "Games");
const OUT = path.join(__dirname, "flows");

// SkillFlow and friends replace console.log when they load; write output directly.
const say = (s) => process.stdout.write(s + "\n");

// The array literal assigned to `const name = [`, cut out of the source with brackets matched (strings, template
// literals and comments skipped).
function arrayLiteral(src, name) {
    const start = src.indexOf(`const ${name} = [`);
    if (start < 0) throw new Error(`no "const ${name} = [" in the source`);
    let i = src.indexOf("[", start), depth = 0;
    const open = i;
    for (; i < src.length; i++) {
        const c = src[i], n = src[i + 1];
        if (c === "/" && n === "/") { i = src.indexOf("\n", i); continue; }
        if (c === "/" && n === "*") { i = src.indexOf("*/", i) + 1; continue; }
        if (c === '"' || c === "'" || c === "`") {
            for (i++; i < src.length && src[i] !== c; i++) if (src[i] === "\\") i++;
            continue;
        }
        if (c === "[") depth++;
        else if (c === "]" && --depth === 0) return src.slice(open, i + 1);
    }
    throw new Error(`unbalanced brackets after "const ${name} = ["`);
}

function evalFlow(file, name, stubs) {
    const text = arrayLiteral(fs.readFileSync(file, "utf8"), name);
    // eslint-disable-next-line no-new-func
    return new Function(...Object.keys(stubs), `return ${text};`)(...Object.values(stubs));
}

// Loads the module with `module.exports.__eag = { names }` appended, so module-level constants can be read.
function internals(file, names) {
    const src = fs.readFileSync(file, "utf8") + `\nmodule.exports.__eag = { ${names.join(", ")} };\n`;
    const m = new Module(file, module);
    m.filename = file;
    m.paths = Module._nodeModulePaths(path.dirname(file));
    m._compile(src, file);
    return m.exports.__eag;
}

const fnText = (v) => (typeof v === "function" ? { fn: String(v) } : v);

function noodleRush() {
    const file = path.join(GAMES, "noodle-rush", "index.js");
    const flow = evalFlow(file, "NOODLE_GAME_FLOW", {
        noodleScene: (id, slug, description, choices, opts = {}) => ({ type: "scene", id, slug, description, choices, ...opts }),
        noodleEnding: (id, slug, description) => ({ type: "ending", id, slug, description }),
    });
    const { NOODLE_UTTERANCE_MAP } = internals(file, ["NOODLE_UTTERANCE_MAP"]);
    return {
        game: "noodle-rush",
        flow,
        choiceWords: NOODLE_UTTERANCE_MAP,
        // doNoodleAnswer's own lists (local to that function in the skill).
        words: {
            yes: ["yes", "yeah", "yep", "yup", "sure", "of course", "definitely", "yes please"],
            no: ["no", "nope", "nah", "no thanks", "not really"],
        },
        reprompts: require(path.join(GAMES, "noodle-rush", "reprompts.js")),
    };
}

function frootopia() {
    const file = path.join(GAMES, "frootopia", "index.js");
    const FR_FLOWS = require(path.join(GAMES, "frootopia", "flows.js"));
    const flow = evalFlow(file, "FROOTOPIA_GAME_FLOW", {
        frScene: (id, description, { yes, no, stats } = {}) => ({ type: "scene", id, description, yes, no, stats }),
        frPass: (id, description, next, stats) => ({ type: "pass", id, description, next, stats }),
        frExit: (id, description) => ({ type: "exit", id, description }),
        frGameOver: (id, description) => ({ type: "gameover", id, description }),
        frEnding: (id, description, story) => ({ type: "ending", id, description, story }),
        storyNode: (id, f) => ({ type: "story", id, ...f }),
        FR_FLOWS,
    });
    const w = internals(file, ["YES_WORDS", "NO_WORDS", "REPEAT_WORDS", "NAMED_ANSWER_IS", "NODE_CHOICE_WORDS", "YES_EXACT", "STORIES"]);
    return {
        game: "frootopia",
        flow,
        words: { yes: w.YES_WORDS, no: w.NO_WORDS, repeat: w.REPEAT_WORDS, yesExact: w.YES_EXACT },
        namedAnswerIs: w.NAMED_ANSWER_IS,
        nodeChoiceWords: w.NODE_CHOICE_WORDS,
        stories: w.STORIES,
        reprompts: require(path.join(GAMES, "frootopia", "reprompts.js")),
    };
}

function signalDecoders() {
    const file = path.join(GAMES, "alien-invasion", "index.js");
    const pass = (id, next) => ({ type: "pass", id, next: fnText(next) });
    const puzzle = (id, key) => ({ type: "puzzle", id, puzzle: key });
    const flow = evalFlow(file, "ALIEN_INVASION_FLOW", {
        pass,
        question: (id, branches) => ({ type: "question", id, ...branches }),
        puzzle,
        choice: (id) => ({ type: "choice", id }),
        ending: (id, chapter) => ({ type: "ending", id, chapter }),
        exitNode: (id) => ({ type: "exit", id }),
        // The skill's puzzleFlow: the question, the hint, the question again, the reveal and the right answer.
        puzzleFlow: (id, key, after) => [puzzle(id, key), puzzle(`${id}-hint`, key), puzzle(`${id}-again`, key),
            pass(`${id}-reveal`, `${id}-yes`), pass(`${id}-yes`, after)],
    });
    const w = internals(file, ["PUZZLES", "YES_WORDS", "NO_WORDS", "UNSURE_WORDS", "REPEAT_WORDS", "FOLLOW_WORDS", "HIDE_WORDS",
        "LETTER_WORDS", "TURN_WORDS", "SOS_WORDS", "HL_WORDS", "CHAPTERS"]);
    const puzzles = {};
    for (const [key, p] of Object.entries(w.PUZZLES)) {
        puzzles[key] = { start: p.start, hint: p.hint, again: p.again, reveal: p.reveal, correct: p.correct, check: p.check.name, options: p.options };
    }
    return {
        game: "signal-decoders",
        flow,
        puzzles,
        words: { yes: w.YES_WORDS, no: w.NO_WORDS, unsure: w.UNSURE_WORDS, repeat: w.REPEAT_WORDS, follow: w.FOLLOW_WORDS, hide: w.HIDE_WORDS },
        symbols: { letters: w.LETTER_WORDS, turns: w.TURN_WORDS, sos: w.SOS_WORDS, notes: w.HL_WORDS },
        chapters: w.CHAPTERS,
        reprompts: require(path.join(GAMES, "alien-invasion", "reprompts.js")),
    };
}

fs.mkdirSync(OUT, { recursive: true });
for (const make of [noodleRush, frootopia, signalDecoders]) {
    const data = make();
    const file = path.join(OUT, `${data.game}.json`);
    fs.writeFileSync(file, JSON.stringify(data, null, 1) + "\n");
    say(`${data.game}: ${data.flow.length} flow nodes -> ${path.relative(ROOT, file)}`);
}
