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

// Loads a module with `module.exports.__eag = { names }` appended, so its module-level constants can be read
// (and `extra` code before that, which can wrap the module's own functions).
function internals(file, names, extra = "") {
    const src = fs.readFileSync(file, "utf8") + `\n${extra}\nmodule.exports.__eag = { ${names.join(", ")} };\n`;
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

// What a Werewolf villager says at one point of a story: each recording it can pick, with the condition (on the map's
// variables) under which the skill picks it. The story's speech functions read the jail, the dead and the found
// werewolves (prison.includes, dead.includes, werewolves.includes, werewolves.length, prison[0]); they are run on
// every combination of what they read, and the results are split into a decision tree. Map variables: st_<villager>
// (0 in play, 1 eaten, 2 in jail, 3 a werewolf found and jailed), found (werewolves found), first_jail (the first
// villager jailed, or "").
function werewolfVariants(fn, keyOf, allIds) {
    const domains = new Map();   // atom -> its possible values, in the order the functions read them
    const run = (assign) => {
        const read = (atom, domain) => {
            if (!domains.has(atom)) domains.set(atom, domain);
            return atom in assign ? assign[atom] : domain[0];
        };
        const list = (kind) => new Proxy([], {
            get(_, prop) {
                if (prop === "includes") return (x) => read(`${kind}:${keyOf(x)}`, [false, true]);
                if (prop === "length") {
                    if (kind !== "w") throw new Error(`${kind}.length isn't mapped`);
                    return read("w#", [0, 1, 2]);
                }
                if (prop === "0") {
                    if (kind !== "p") throw new Error(`${kind}[0] isn't mapped`);
                    return read("p0", [undefined, ...allIds]);
                }
                throw new Error(`werewolf state .${String(prop)} isn't mapped`);
            },
        });
        const ad = { Session: { werewolf: { werewolves: list("w"), dead: list("d"), prison: list("p") } } };
        const r = fn(ad);
        return { id: r.id, text: r.speech };
    };
    // Every combination of the atoms read, until running them reads nothing new.
    let combos;
    for (let size = -1; size !== domains.size;) {
        size = domains.size;
        combos = [{}];
        for (const [atom, dom] of domains) combos = combos.flatMap((c) => dom.map((v) => ({ ...c, [atom]: v })));
        combos.forEach(run);
    }
    const results = combos.map((c) => ({ assign: c, out: run(c) }));
    const sameOut = (rs) => rs.every((r) => r.out.id === rs[0].out.id && r.out.text === rs[0].out.text);

    // A branch as the values each map variable may have (st_<villager> 0-3, found 0-2, first_jail "" or a villager).
    const ALL = { st: [0, 1, 2, 3], found: [0, 1, 2], first_jail: ["", ...allIds.map(keyOf)] };
    const allowed = (atom, v) => {
        if (atom === "w#") return ["found", [v]];
        if (atom === "p0") return ["first_jail", [v === undefined ? "" : keyOf(v)]];
        const [kind, who] = atom.split(":");
        const yes = { w: [3], d: [1], p: [2, 3] }[kind];
        return [`st_${who}`, v ? yes : ALL.st.filter((x) => !yes.includes(x))];
    };
    // Split on the atoms in the order they were read, until each branch always says the same.
    const leaves = [];
    const split = (rs, cons, atoms) => {
        if (sameOut(rs)) {
            leaves.push({ out: rs[0].out, cons });
            return;
        }
        const [atom, ...rest] = atoms;
        for (const v of domains.get(atom)) {
            const sub = rs.filter((r) => r.assign[atom] === v);
            const [name, vals] = allowed(atom, v);
            const now = (cons[name] || vals).filter((x) => vals.includes(x));
            if (sub.length && now.length) split(sub, { ...cons, [name]: now }, rest);
        }
    };
    split(results, {}, [...domains.keys()]);

    // Branches that say the same and differ in one variable become one.
    const full = (name) => name.startsWith("st_") ? ALL.st : ALL[name];
    const get = (l, name) => l.cons[name] || full(name);
    for (let merged = true; merged;) {
        merged = false;
        outer: for (let i = 0; i < leaves.length; i++) {
            for (let j = i + 1; j < leaves.length; j++) {
                const a = leaves[i], b = leaves[j];
                if (a.out.id !== b.out.id || a.out.text !== b.out.text) continue;
                const names = [...new Set([...Object.keys(a.cons), ...Object.keys(b.cons)])];
                const diff = names.filter((n) => JSON.stringify(get(a, n)) !== JSON.stringify(get(b, n)));
                if (diff.length > 1) continue;
                const cons = { ...a.cons };
                for (const n of diff) {
                    const u = full(n).filter((x) => get(a, n).includes(x) || get(b, n).includes(x));
                    if (u.length === full(n).length) delete cons[n]; else cons[n] = u;
                }
                leaves.splice(j, 1);
                leaves[i] = { out: a.out, cons };
                merged = true;
                break outer;
            }
        }
    }

    // The tests as map conditions, as short as they can be.
    const test = (name, vals) => {
        const all = full(name);
        const q = (x) => typeof x === "string" ? `"${x}"` : x;
        if (vals.length === 1) return `${name} == ${q(vals[0])}`;
        const not = all.filter((x) => !vals.includes(x));
        if (not.length === 1) return `${name} != ${q(not[0])}`;
        if (typeof vals[0] === "number" && vals.every((x, i) => i === 0 || x === vals[i - 1] + 1)) {
            if (vals[vals.length - 1] === all[all.length - 1]) return `${name} >= ${vals[0]}`;
            if (vals[0] === all[0]) return `${name} <= ${vals[vals.length - 1]}`;
        }
        return `(${vals.map((x) => `${name} == ${q(x)}`).join(" || ")})`;
    };
    return leaves.map((l) => {
        const parts = Object.entries(l.cons).map(([n, v]) => test(n, v));
        return { id: l.out.id, text: l.out.text, when: parts.length ? parts.join(" && ") : null };
    });
}

function werewolf() {
    const dir = path.join(LAMBDA, "Games", "the-werewolf");
    const { WEREWOLF_STORY_META, WEREWOLF_STORIES } = require(path.join(dir, "stories.js"));
    const { WERE_CHARACTER_MAP } = require(path.join(LAMBDA, "Constants", "Constants.js"));
    const w = internals(path.join(dir, "index.js"), ["WEREWOLF_EXACT_ALIASES"]);
    const { audio, speech } = tables();
    const keyOf = (id) => WERE_CHARACTER_MAP[id].key;
    const allIds = Object.keys(WERE_CHARACTER_MAP);
    return {
        game: "the-werewolf",
        cdn: "en/audio2/the-werewolf/",
        characters: Object.fromEntries(Object.values(WERE_CHARACTER_MAP).map((c) => [c.key,
            { name: c.name, voice: c.voice, display: c.display, pronoun: c.pronoun, wereName: c.wereName, synonyms: c.synonyms }])),
        exactAliases: w.WEREWOLF_EXACT_ALIASES,
        meta: WEREWOLF_STORY_META,
        stories: WEREWOLF_STORIES.map((s) => ({
            id: s.id,
            werewolves: s.werewolves.map(keyOf),
            order: Object.keys(s.stories).map(keyOf),
            lines: Object.fromEntries(Object.entries(s.stories).map(([cid, c]) =>
                [keyOf(cid), c.story.map((line) => werewolfVariants(line.speech, keyOf, allIds))])),
        })),
        speech: { ...speech.werewolf, caughtWerewolf: undefined, hereComes: speech.hereComesWereChar("{v}") },
        audio: audio.theWerewolf,
        getters: { ...getters("getWerewolf", "theWerewolf"), ...getters("getWere", "theWerewolf"),
            ...getters("getWolf", "theWerewolf"), ...getters("getLongFound", "theWerewolf"),
            ...getters("getLittleFound", "theWerewolf"), ...getters("getRandomWerewolf", "theWerewolf"),
            ...getters("getCharacterDenial", "theWerewolf") },
    };
}

// Stands in for the skill's response builder (Libraries/ResponseUtil.js): records what a node says and plays, in
// order, with its mixers, and the node changes and stat updates the hooks mark in the same stream.
class Recorder {
    constructor() {
        this.items = [];
        this.stack = [this.items];
        this.reprompt = null;
        this.asked = null;
    }
    get cur() { return this.stack[this.stack.length - 1]; }
    get last() { return this.cur[this.cur.length - 1]; }
    mark(x) { this.cur.push(x); return this; }
    addVoice(text) { return this.mark({ voice: text }); }
    addAudio(url, trim) { return this.mark({ audio: String(url).replace(/^https:\/\/[^/]+\/en\/audio2\//, "").replace(/\?.*$/, ""), trim: !!trim }); }
    addSilence(ms) { return this.mark({ silence: ms }); }
    beginMixer() { const m = { mixer: [] }; this.cur.push(m); this.stack.push(m.mixer); return this; }
    endMixer() { this.stack.pop(); return this; }
    beginSequencer() { const s = { seq: [] }; this.cur.push(s); this.stack.push(s.seq); return this; }
    endSequencer() { this.stack.pop(); return this; }
    changeVolume(v) { this.last.volume = v; return this; }
    addFadeIn(ms) { this.last.fadeIn = ms; return this; }
    addReprompt(text) { this.reprompt = text; return this; }
    addHTMLMessage() { return this; }
    addHTML() { return this; }
    Ask() { this.asked = true; return {}; }
    DontAsk() { this.asked = false; return {}; }
}

// Pirate Quest: each node of PIRATE_GAME_FLOW run on its own, with the module's stat updates, dice, stat reads and
// node changes marked in what it says. A node that reads a stat runs again with other values (a full purse, an
// empty one, a good reputation, the royal information), so its builder sees each branch.
async function pirateQuest() {
    const dir = path.join(LAMBDA, "Games", "pirate-quest");
    const hooks = `
        updatePirateStat = function (ad, stat, value, saveNode = true) { ad.Response.mark({ stat, value, once: saveNode }); };
        setCurrentNode = function (ad, node) { ad.Response.mark({ node }); ad.Session[SessionVars.Settings].pirateQuest.currentNode = node; };
        getPirateStat = function (ad, stat) { ad.Response.mark({ read: stat }); return ad.Session[SessionVars.Settings].pirateQuest[stat]; };
        getDiceOutcome = function () { return globalThis.__eagDice; };
    `;
    const w = internals(path.join(dir, "index.js"), ["PIRATE_GAME_FLOW", "PIRATE_UTTERANCE_MAP", "PIRATE_STATS"], hooks);
    const { SessionVars, SkillStates } = require(path.join(LAMBDA, "Constants", "Constants.js"));
    const { audio } = tables();
    const START = { health: 80, coins: 50, crewMorale: 55, reputation: 10, journalQuest: ["First sail"],
        firedNavigator: false, royalInfo: false };
    const SCENARIOS = { coins: [0, 50], reputation: [10, 50], royalInfo: [false, true], firedNavigator: [false, true],
        health: [80] };
    globalThis.__eagDice = { captainRolls: [5, 4, 3], willRolls: [1, 2, 3], captainTotal: 12, willTotal: 6, outcome: "win" };

    // The story flags are read and set directly on the saved state (not through getPirateStat): marked by a proxy.
    const FLAGS = ["royalInfo", "firedNavigator"];
    async function run(node, stats) {
        const rec = new Recorder();
        const pirateQuest = new Proxy({ ...START, ...stats, currentNode: node.id, processedNodes: {} }, {
            get(t, k) {
                if (FLAGS.includes(k)) rec.mark({ read: k });
                return t[k];
            },
            set(t, k, v) {
                if (FLAGS.includes(k)) rec.mark({ flag: k, value: v });
                t[k] = v;
                return true;
            },
        });
        const ad = {
            Session: {
                [SessionVars.Settings]: { pirateQuest, isSubscriber: true, coins: 0 },
                [SessionVars.SkillState]: SkillStates.PIRATE_QUEST,
            },
            Response: rec,
            Audio: audio,
            Util: { supportsHTML: () => false, supportsAPL: () => false, isSubscriber: () => true, getLocale: () => "en-US" },
            Save: () => {},
            displayAPL: false,
        };
        let error = null;
        try {
            await node.prompt(ad);
        } catch (e) {
            error = String(e && e.message || e);
        }
        const r = ad.Response;
        return { stats, items: r.items, reprompt: r.reprompt, asked: r.asked, error };
    }

    const nodes = [];
    for (const node of w.PIRATE_GAME_FLOW) {
        const first = await run(node, {});
        const reads = new Set(JSON.stringify(first.items).match(/"read":"\w+"/g) || []);
        const runs = [first];
        for (const r of reads) {
            const stat = r.slice(8, -1);
            for (const v of SCENARIOS[stat] || []) {
                if (v !== START[stat]) runs.push(await run(node, { [stat]: v }));
            }
        }
        const options = Object.fromEntries(Object.entries(node)
            .filter(([k]) => !["id", "description", "prompt", "reprompt"].includes(k)));
        nodes.push({ id: node.id, description: node.description, reprompt: node.reprompt || null, options, runs });
    }
    return {
        game: "pirate-quest",
        cdn: "en/audio2/",
        start: START,
        utterances: w.PIRATE_UTTERANCE_MAP,
        nodes,
        audio: audio.pirateGame,
        intro: audio.getPirateVoice(audio.pirateGame.pirateIntro).replace(/^https:\/\/[^/]+\/en\/audio2\//, "").replace(/\?.*$/, ""),
    };
}

// Nuclear War is ported to Kotlin (android/engine/.../nuclear); what it needs from the skill is the audio table its
// getters choose from, with every path made relative to en/audio2/ (most are under nuclear-war/, a few aren't).
function nuclearWar() {
    const { audio } = tables();
    const strip = (url) => String(url).replace(/^https:\/\/[^/]+\/en\/audio2\//, "").replace(/\?.*$/, "")
        .replace(/%20/g, " ");
    const t = audio.nuclear;
    const under = (v) => (typeof v === "string" ? `nuclear-war/${v.replace(/\?.*$/, "")}`
        : Array.isArray(v) ? v.map(under) : Object.fromEntries(Object.entries(v).map(([k, x]) => [k, under(x)])));
    const countries = {};
    for (const ref of ["France", "USA", "UK", "China", "Russia"]) countries[ref] = under(t[ref]);
    const sfx = {};
    for (const [k, v] of Object.entries(t)) if (!countries[k] && (typeof v === "string" || Array.isArray(v))) sfx[k] = under(v);
    // Not under nuclear-war/: the getters' own folders (Audio.js getNuclearKaching, getHalo).
    sfx.kaching = strip(audio.getNuclearKaching());
    sfx.halo = strip(audio.getHalo());
    return { game: "nuclear-war", cdn: "en/audio2/", table: { ...countries, sfx } };
}

const GAMES = { "leaning-tower-of-pizza": ltop, "alien-customs": alienCustoms, "the-werewolf": werewolf,
    "pirate-quest": pirateQuest, "nuclear-war": nuclearWar };

(async () => {
    fs.mkdirSync(OUT, { recursive: true });
    const wanted = process.argv.slice(2);
    for (const [name, make] of Object.entries(GAMES)) {
        if (wanted.length && !wanted.includes(name)) continue;
        const data = await make();
        const file = path.join(OUT, `${name}.json`);
        fs.writeFileSync(file, JSON.stringify(data, null, 1) + "\n");
        say(`${name} -> ${path.relative(ROOT, file)}`);
    }
})();
