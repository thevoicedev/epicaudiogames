// Plays random answers through the real Alexa skill and records, turn by turn, the game clips Alexa plays.
// The engine's AlexaReplayTest replays the same answers through the maps and must play the same clips, so the maps
// are checked against the skill itself, not against our reading of it.
//
// The skill is all-minigames-sites/alexa/lambda (or MINIGAMES_DIR), loaded read-only the way its own
// alexa/tools/<game>/test_lambda.js harnesses do: its database, the other lambdas and GameOn are stubbed, so
// nothing leaves this machine. Each walk starts a game from the lobby as a subscriber on a speaker (no screen),
// answers with words the map's questions take (and some they don't), and stops when the game ends or is left.
// Then a grid: every question in the map, put straight into the skill's saved state, with every word in its pool
// (a walk of one answer, whose first turn is "@at").
//
// Usage (from the repo root): node tools/parity.js [--walks 150] [--turns 60] [--seed 1]
// Writes tools/cache/parity/<game>.json.
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const MINI = process.env.MINIGAMES_DIR || path.join(ROOT, "..", "all-minigames-sites");
const LAMBDA = path.join(MINI, "alexa", "lambda");
const OUT = path.join(__dirname, "cache", "parity");
const arg = (name, def) => {
    const i = process.argv.indexOf(`--${name}`);
    return i > 0 ? Number(process.argv[i + 1]) : def;
};
const WALKS = arg("walks", 150);
const TURNS = arg("turns", 60);
const SEED = arg("seed", 1);

const say = (s) => process.stdout.write(s + "\n");
const logs = [];
console.log = (...a) => logs.push(a.join(" "));
console.warn = console.log;

function stubAll(proto) {
    for (const k of Object.getOwnPropertyNames(proto)) {
        if (k !== "constructor" && typeof proto[k] === "function") proto[k] = async () => null;
    }
}
stubAll(require(path.join(LAMBDA, "Libraries/DynamoDB.js")).prototype);
stubAll(require(path.join(LAMBDA, "Libraries/LambdaInvoker.js")).prototype);
for (const f of fs.readdirSync(path.join(LAMBDA, "Libraries/GameOn"))) {
    try {
        const m = require(path.join(LAMBDA, "Libraries/GameOn", f));
        if (m && m.prototype) stubAll(m.prototype);
    } catch (e) { /* not a class */ }
}
const { handler } = require(path.join(LAMBDA, "index.js"));
require(path.join(LAMBDA, "Games/alien-invasion/index.js")).comingSoon = false;
const { SkillStates } = require(path.join(LAMBDA, "Constants/Constants.js"));
const fixture = require(path.join(LAMBDA, "Libraries/test.json")).handler.requestEnvelope;

// at(node): the game's saved state at a question, as the skill keeps it.
const GAMES = [
    { id: "noodle-rush", launch: "noodle rush", key: "noodleRush", prefix: "noodle-rush/v5/", activeId: "NR",
        playing: ["NOODLE_RUSH"], over: ["NOODLE_GAME_OVER"],
        at: (node) => ({ currentNode: node, hasStartedBefore: true, inProgress: true }) },
    { id: "frootopia", launch: "frootopia", key: "frootopia", prefix: "frootopia/v11/", activeId: "FROOTOPIA",
        playing: ["FROOTOPIA"], over: ["FROOTOPIA_GAME_OVER", "FROOTOPIA_STORY_UPSELL"],
        at: (node) => ({ story: 1, currentNode: node, inProgress: true }) },
    { id: "signal-decoders", launch: "alien invasion", key: "alienInvasion", prefix: "alien-invasion/v4/", activeId: "AINV",
        playing: ["ALIEN_INVASION"], over: ["ALIEN_INVASION_GAME_OVER"], next: "next chapter",
        at: (node) => ({ chapter: Number((node.match(/^ai(\d)-/) || [0, 1])[1]), currentNode: node, inProgress: true, tries: 0 }) },
];
// Clips the app leaves out: coins, outros ("play again, or a different game?"), offers and welcomes.
const APP_DROPS = /^common\/(outro|upsell|gate|welcome|resume|next-reprompt|chat)/;
// Commands handled everywhere, before a game sees them. In the skill, "off" and "home" leave (SkillFlow.doAnswer)
// and "stop" and "cancel" are Alexa's own Stop and Cancel; in the app, "stop" and "cancel" pause the game
// (Commands.kt), leaving is a button, and "off" is just one of a game's words.
const SKILL_COMMANDS = new Set(["off", "home", "stop playing", "joe", "stop", "cancel"]);
// Words the questions don't take, or take in a tricky way.
const EXTRA = ["banana", "i'm not sure", "i guess not", "don't follow it", "let's not hide", "i'm fine", "fine",
    "two two one one", "c a c again", "say that again", "repeat", "no thanks", "yes please", "i don't know",
    "no let's go", "yes no", "no yes", "follow or hide", "don't hide", "sure", "okay", "maybe",
    "probably not", "never", "not now", "of course not", "the first one", "option two", "number one", "hi", "left right",
    "one two", "a c", "s o s", "high high", "low", "yeah no", "no way", "let's do it", "nah let's go"];

function rng(seed) {   // mulberry32
    return () => {
        seed = (seed + 0x6D2B79F5) | 0;
        let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function envelope(attrs, request) {
    const e = JSON.parse(JSON.stringify(fixture));
    e.session.new = false;
    e.session.attributes = attrs;
    e.request = { requestId: `parity.${Math.random()}`, timestamp: new Date().toISOString(), locale: "en-GB", ...request };
    const si = e.context.System.device.supportedInterfaces;
    delete si["Alexa.Presentation.APL"];
    delete si["Alexa.Presentation.HTML"];
    return e;
}

const intent = (name, slots) => ({ type: "IntentRequest", intent: { name, confirmationStatus: "NONE", slots: slots || {} } });
function request(said) {
    if (said === "yes") return intent("AMAZON.YesIntent");
    if (said === "no") return intent("AMAZON.NoIntent");
    return intent("AnswerOnlyIntent", { Answer: { name: "Answer", value: said } });
}

async function turn(game, g, said) {
    logs.length = 0;
    const res = await handler(envelope(g.attrs, request(said)), {});
    g.attrs = res.sessionAttributes;
    const text = JSON.stringify((res.response || {}).directives || []);
    const urls = text.match(/https:\/\/x9gq2b7lta\.com\/en\/audio2\/[^"?\\]+\.mp3/g) || [];
    const clips = urls.filter((u) => u.includes(`/audio2/${game.prefix}`))
        .map((u) => u.split(`/audio2/${game.prefix}`)[1].replace(/\.mp3$/, ""))
        .filter((c) => !APP_DROPS.test(c));
    const errors = logs.filter((l) => /Error handled|SKILL_ORIGINAL_ERROR|SKILL_HANDLED_ERROR/.test(l));
    const state = Object.keys(SkillStates).find((k) => SkillStates[k] === g.attrs._STATE) || String(g.attrs._STATE);
    const node = ((g.attrs.Settings || {})[game.key] || {}).currentNode;
    const phase = game.playing.includes(state) ? "playing" : game.over.includes(state) ? "over" : "left";
    return { said, clips, phase, state, node, ...(errors.length ? { errors } : {}) };
}

// What a player might say at a node: what its buttons send, a phrase for each answer (all of them, for the grid),
// and some extras.
function pool(map, nodeId, all) {
    const ask = map.nodes[nodeId] && map.nodes[nodeId].ask;
    const out = new Set(["yes", "no", "yeah", "nope"]);
    if (ask) {
        for (const b of ask.buttons || []) out.add(b.value);
        for (const a of ask.answers) {
            const words = a.words || (a.yes ? map.words.yes : a.no ? map.words.no : a.repeat ? map.words.repeat : null);
            if (words) {
                for (const w of all ? words : [words[Math.floor(Math.random() * words.length)]]) out.add(w.replace(/^=/, ""));
            }
            if (a.digits) out.add(a.digits.split("").join(" "));
            if (a.seq) out.add(a.seq.split("").map((c) => map.symbols[a.symbols][c][0]).join(" "));
        }
    }
    return [...out, ...EXTRA].filter((w) => !SKILL_COMMANDS.has(w));
}

function newGame() {
    const attrs = JSON.parse(JSON.stringify(fixture.session.attributes));
    attrs._STATE = SkillStates.HEAR_GAMES;
    attrs.activeId = null;
    attrs.Settings = { ...attrs.Settings, isSubscriber: true, globalGamePlayCount: 0 };
    for (const g of GAMES) delete attrs.Settings[g.key];
    return { attrs };
}

(async () => {
    fs.mkdirSync(OUT, { recursive: true });
    for (const game of GAMES) {
        const map = JSON.parse(fs.readFileSync(path.join(ROOT, "games", game.id, "map.json"), "utf8"));
        const random = rng(SEED);
        Math.random = random;          // the skill's random picks too, so a run can be repeated
        const walks = [];
        let errors = 0;
        const seen = new Set();
        for (let w = 0; w < WALKS; w++) {
            const g = newGame();
            const turns = [await turn(game, g, game.launch)];
            for (let t = 0; t < TURNS; t++) {
                const last = turns[turns.length - 1];
                if (last.errors) { errors++; break; }
                if (last.phase === "over") {
                    // A chapter's end: on to the next one (Signal Decoders); a story's end: done.
                    if (!game.next || last.node === map.start) break;
                    turns.push({ ...(await turn(game, g, game.next)), said: "@next" });
                    continue;
                }
                if (last.phase === "left") break;
                seen.add(last.node);
                const words = pool(map, last.node);
                turns.push(await turn(game, g, words[Math.floor(random() * words.length)]));
            }
            walks.push({ turns });
        }
        // The grid: every question, every word in its pool.
        let grid = 0;
        for (const [nodeId, node] of Object.entries(map.nodes)) {
            if (!node.ask || nodeId.startsWith("_")) continue;
            for (const said of pool(map, nodeId, true)) {
                const g = newGame();
                g.attrs._STATE = SkillStates[game.playing[0]];
                g.attrs.activeId = game.activeId;
                g.attrs.Settings[game.key] = game.at(nodeId);
                const answer = await turn(game, g, said);
                if (answer.errors) errors++;
                walks.push({ turns: [{ said: "@at", node: nodeId }, answer] });
                grid++;
            }
        }
        const file = path.join(OUT, `${game.id}.json`);
        fs.writeFileSync(file, JSON.stringify({ game: game.id, walks }, null, 0) + "\n");
        const nTurns = walks.reduce((a, w) => a + w.turns.length, 0);
        say(`${game.id}: ${walks.length - grid} walks and a grid of ${grid} answers, ${nTurns} turns, ` +
            `${seen.size} of ${Object.keys(map.nodes).length} nodes asked on the walks` +
            `${errors ? `, ${errors} handler errors` : ""} -> ${path.relative(ROOT, file)}`);
    }
    process.exit(0);
})().catch((e) => {
    say(String(e && e.stack || e));
    process.exit(1);
});
