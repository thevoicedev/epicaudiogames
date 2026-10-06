// Plays a scripted path through the real Alexa skill and prints each response's audio as a tree (mixers,
// sequencers, clips with their volume and fades, Alexa's lines), to check a game's map against what Alexa plays.
//
// The skill is loaded read-only and offline, as in parity.js (database, other lambdas and GameOn stubbed). The
// player is a subscriber on a speaker; Math.random is seeded, so a path plays the same every time.
//
// Usage (from the repo root): node tools/capture.js "<launch words>" [answer ...] [--seed 3]
//   e.g. node tools/capture.js "leaning tower of pizza" yes false true
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const MINI = process.env.MINIGAMES_DIR || path.join(ROOT, "..", "all-minigames-sites");
const LAMBDA = path.join(MINI, "alexa", "lambda");
const say = (s) => process.stdout.write(s + "\n");
console.log = () => {};
console.warn = () => {};

const args = process.argv.slice(2);
const seedAt = args.indexOf("--seed");
let seed = seedAt >= 0 ? Number(args.splice(seedAt, 2)[1]) : 1;
// --settings '{"alienCustoms":{"completedLevelIds":[]}}': saved settings the player starts with.
const settingsAt = args.indexOf("--settings");
const startSettings = settingsAt >= 0 ? JSON.parse(args.splice(settingsAt, 2)[1]) : {};
Math.random = () => {   // mulberry32
    seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

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
const { SkillStates } = require(path.join(LAMBDA, "Constants/Constants.js"));
const fixture = require(path.join(LAMBDA, "Libraries/test.json")).handler.requestEnvelope;

function envelope(attrs, request) {
    const e = JSON.parse(JSON.stringify(fixture));
    e.session.new = false;
    e.session.attributes = attrs;
    e.request = { requestId: `capture.${Math.random()}`, timestamp: new Date().toISOString(), locale: "en-GB", ...request };
    const si = e.context.System.device.supportedInterfaces;
    delete si["Alexa.Presentation.APL"];
    delete si["Alexa.Presentation.HTML"];
    return e;
}

const intent = (name, slots) => ({ type: "IntentRequest", intent: { name, confirmationStatus: "NONE", slots: slots || {} } });
const request = (said) => said === "yes" ? intent("AMAZON.YesIntent") : said === "no" ? intent("AMAZON.NoIntent")
    : intent("AnswerOnlyIntent", { Answer: { name: "Answer", value: said } });

function tree(item, depth, out) {
    const pad = "  ".repeat(depth);
    const filters = (item.filters || []).map((f) => f.type === "Volume" ? `vol ${f.amount}` : f.type === "FadeIn"
        ? `fade-in ${f.duration}` : f.type === "FadeOut" ? `fade-out ${f.duration}` : f.type).join(", ");
    const extra = [item.duration === "trimToParent" ? "trim" : "", filters].filter(Boolean).join(", ");
    if (item.type === "Mixer" || item.type === "Sequencer") {
        out.push(`${pad}${item.type}${extra ? ` (${extra})` : ""}`);
        for (const child of item.items || []) tree(child, depth + 1, out);
    } else if (item.type === "Audio") {
        out.push(`${pad}audio ${String(item.source).replace(/^https:\/\/[^/]+\/en\/audio2\//, "").replace(/\?.*$/, "")}${extra ? ` (${extra})` : ""}`);
    } else if (item.type === "Speech") {
        out.push(`${pad}say "${String(item.content).replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim()}"${extra ? ` (${extra})` : ""}`);
    } else if (item.type === "Silence") {
        out.push(`${pad}silence ${item.duration}`);
    } else {
        out.push(`${pad}${item.type}`);
    }
}

(async () => {
    const attrs = JSON.parse(JSON.stringify(fixture.session.attributes));
    attrs._STATE = SkillStates.HEAR_GAMES;
    attrs.activeId = null;
    attrs.Settings = { ...attrs.Settings, isSubscriber: true, globalGamePlayCount: 0, ...startSettings };
    let g = { attrs };
    // Leaning Tower of Pizza: "@lie" and "@truth" answer the current question (from its map) with a lie or the truth.
    const ltopMap = (() => {
        try { return JSON.parse(fs.readFileSync(path.join(ROOT, "games", "leaning-tower-of-pizza", "map.json"), "utf8")); }
        catch (e) { return null; }
    })();
    function answerFor(token) {
        const id = ((g.attrs || {}).ltop || {}).currentQuestionId;
        const node = ltopMap && id && ltopMap.nodes[`q_${id}`];
        if (!node) return "true";
        const wanted = token === "@lie" ? "lie" : "honest";
        const a = node.ask.answers.find((x) => x.words && x.go === wanted);
        return a.words[0];
    }
    for (const word of args) {
        const said = word.startsWith("@") ? answerFor(word) : word;
        const res = await handler(envelope(g.attrs, request(said)), {});
        g.attrs = res.sessionAttributes;
        const state = Object.keys(SkillStates).find((k) => SkillStates[k] === g.attrs._STATE) || g.attrs._STATE;
        say(`\n=== "${said}" -> ${state}`);
        const doc = ((res.response || {}).directives || []).find((d) => d.type === "Alexa.Presentation.APLA.RenderDocument");
        const items = doc ? [doc.document.mainTemplate.item] : [];
        const out = [];
        for (const item of items) tree(item, 1, out);
        const speech = res.response && res.response.outputSpeech;
        if (speech && (speech.ssml || speech.text)) {
            const plain = String(speech.ssml || speech.text).replace(/<audio src\s*=\s*'([^']*)'\s*\/>/g, " [$1] ")
                .replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
            if (plain) out.push(`  speech: ${plain}`);
        }
        say(out.join("\n") || "  (no audio)");
        const rp = res.response && res.response.reprompt;
        if (rp) say(`  reprompt: ${JSON.stringify(rp).replace(/<[^>]+>/g, "").match(/"(?:ssml|text|content)":"([^"]*)"/)?.[1] || "(audio)"}`);
    }
    process.exit(0);
})().catch((e) => {
    say(String(e && e.stack || e));
    process.exit(1);
});
