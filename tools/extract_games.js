// Reads the coded Mini Games (not the radio plays: those are extract_flows.js) out of the skill: each game's content
// tables, its speech lists, and the audio files its getters choose from, as JSON in tools/flows/<game>.json for its
// builder in tools/games/.
//
// Read-only, from all-minigames-sites/alexa/lambda (or MINIGAMES_DIR). Nothing from it runs in the app.
//
// Usage (from the repo root): node tools/extract_games.js [game ...]   (default: all)
const fs = require("fs");
const path = require("path");
const Module = require("module");

const ROOT = path.join(__dirname, "..");
const MINI = process.env.MINIGAMES_DIR || path.join(ROOT, "..", "all-minigames-sites");
const LAMBDA = path.join(MINI, "alexa", "lambda");
const OUT = path.join(__dirname, "flows");
const say = (s) => process.stdout.write(s + "\n");

// Loads a module with `module.exports.__eag = { names }` appended, so its module-level constants can be read.
function internals(file, names) {
    const src = fs.readFileSync(file, "utf8") + `\nmodule.exports.__eag = { ${names.join(", ")} };\n`;
    const m = new Module(file, module);
    m.filename = file;
    m.paths = Module._nodeModulePaths(path.dirname(file));
    m._compile(src, file);
    return m.exports.__eag;
}

// The skill's Audio and Speech tables, made for one locale.
const alexaUtil = { getLocale: () => "en-US", supportsAPL: () => false, supportsHTML: () => false };
function tables() {
    const Audio = require(path.join(LAMBDA, "Constants", "Audio.js"));
    const Speech = require(path.join(LAMBDA, "Constants", "Speech.js"));
    return { audio: new Audio(alexaUtil), speech: new Speech(alexaUtil) };
}

// Every getter of the Audio class whose name starts with `prefix`: the fields of the game's table it reads, whether
// it picks one at random, and the folder it puts in front ("leaning-tower-of-pizza/"), or none.
function getters(prefix, table) {
    const src = fs.readFileSync(path.join(LAMBDA, "Constants", "Audio.js"), "utf8");
    const out = {};
    const re = new RegExp(`\\n    (${prefix}\\w*)\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}`, "g");
    for (const m of src.matchAll(re)) {
        const body = m[3];
        const fields = [...new Set([...body.matchAll(new RegExp(`this\\.${table}\\.(\\w+)`, "g"))].map((x) => x[1]))];
        const folder = (body.match(/"([\w-]+\/)"\s*\+/) || [])[1] || null;
        out[m[1]] = { args: m[2].trim(), fields, random: /getRandomElement\(/.test(body), folder, body: body.trim() };
    }
    return out;
}

function ltop() {
    const dir = path.join(LAMBDA, "Games", "leaning-tower-of-pizza");
    const w = internals(path.join(dir, "index.js"), ["LTOP_QUESTIONS", "DOUBLE_NEGATIVE_QUESTIONS", "EASY_QUESTIONS",
        "TRICK_QUESTIONS", "TRUTH_OR_LIE_PROMPTS", "WIN_THRESHOLD", "GROWTH_PER_CORRECT", "MAX_QUESTIONS"]);
    const speech = require(path.join(dir, "Speech.js"));
    const { audio, speech: shared } = tables();
    return {
        game: "leaning-tower-of-pizza",
        cdn: "en/audio2/leaning-tower-of-pizza/",
        rules: { win: w.WIN_THRESHOLD, growth: w.GROWTH_PER_CORRECT, maxQuestions: w.MAX_QUESTIONS },
        questions: { main: w.LTOP_QUESTIONS, easy: w.EASY_QUESTIONS, trick: w.TRICK_QUESTIONS, dn: w.DOUBLE_NEGATIVE_QUESTIONS },
        truthOrLie: w.TRUTH_OR_LIE_PROMPTS,
        speech,
        sharedSpeech: shared.ltop,
        audio: audio.ltop,
        getters: getters("getLtop", "ltop"),
    };
}

function alienCustoms() {
    const dir = path.join(LAMBDA, "Games", "alien-customs");
    const w = internals(path.join(dir, "index.js"), ["PASS_THRESHOLD", "FAIL_THRESHOLD", "QUESTIONS_PER_ITEM", "ITEM_IDS",
        "ITEM_AUDIO_SUFFIX", "ITEM_NAMES", "ANNOUNCEMENT_RULE_COUNTS", "ITEM_FLOWS", "LEVELS"]);
    const { audio, speech } = tables();
    return {
        game: "alien-customs",
        cdn: "en/audio2/alien-customs/",
        rules: { pass: w.PASS_THRESHOLD, fail: w.FAIL_THRESHOLD, questions: w.QUESTIONS_PER_ITEM },
        items: w.ITEM_FLOWS,
        // The audio's names, from the Audio class itself (the game's ITEM_AUDIO_SUFFIX differs: "magnifying glass").
        suffix: Object.fromEntries(Object.values(w.ITEM_IDS).map((id) => [id, audio._getAlienCustomsSuffix(id)])),
        names: w.ITEM_NAMES,
        ruleCounts: w.ANNOUNCEMENT_RULE_COUNTS,
        levels: w.LEVELS,
        audio: audio.alienCustoms,
        dangerWarnings: speech.alienCustomsDangerWarnings,
        getters: { ...getters("getAlienCustoms", "alienCustoms"), ...getters("getAlien", "alienCustoms"),
            ...getters("getSlug", "alienCustoms") },
    };
}

const GAMES = { "leaning-tower-of-pizza": ltop, "alien-customs": alienCustoms };

fs.mkdirSync(OUT, { recursive: true });
const wanted = process.argv.slice(2);
for (const [name, make] of Object.entries(GAMES)) {
    if (wanted.length && !wanted.includes(name)) continue;
    const data = make();
    const file = path.join(OUT, `${name}.json`);
    fs.writeFileSync(file, JSON.stringify(data, null, 1) + "\n");
    say(`${name} -> ${path.relative(ROOT, file)}`);
}
