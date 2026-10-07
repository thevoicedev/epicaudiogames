# Engine golden fixtures

These files pin what the Kotlin engine (`android/engine/src/main`) does with the real maps, packs and Nuclear War
audio table in `games/`. The Swift engine (`ios/EpicEngine`) must reproduce them exactly. Everything in this folder
except this README is written by `android/engine/src/test/kotlin/com/epicaudiogames/engine/golden/GoldenTest.kt`
(with `Canon.kt`, `LoggingRandom.kt`, `GoldenBots.kt` and `Corpora.kt` beside it); never edit the generated files by
hand.

```
cd android
./gradlew :engine:goldens          # write the fixtures (after changing the engine, a map, a pack or clips.json)
./gradlew :engine:goldensCheck     # regenerate in memory; fail if anything differs from what is committed
./gradlew :engine:goldens -Pgoldens.dump=the-werewolf+packs/walk/7     # debugging: see section 11
./gradlew :engine:goldensCheck -Pgames.dir=/some/copy/of/games        # check against another games folder
```

`JAVA_HOME` must point at a JDK 17, for example `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`
(and `sh ./gradlew` if the wrapper has no exec bit). A plain `./gradlew :engine:test` skips GoldenTest. After
`goldens`, commit the whole folder, new files included. `goldens` takes about 20 seconds.

This README is the format's specification: a reader of the fixtures needs nothing else. "§N" refers to its sections.

## 1. Files

| File | What it pins |
|---|---|
| `random.json` | Kotlin's seeded `Random(seed)` (XorWow): raw draws, bounded draws, doubles, booleans, bits, shuffles |
| `text.json` | `Text.normalise`, `Text.digits`, `Commands.isPause`, `Text.phraseLength`, `Text.longest`, `Text.negated`, `Text.symbols`, `Matcher.mixed`, `String.toDoubleOrNull`, `Double.toString`, kotlinx `JsonElement.toString()` and the kotlinx primitive accessors |
| `expr.json` | every `when` and `=` expression in the maps and packs, evaluated under 4 sets of variables; hand-written expressions; parse errors |
| `map-errors.json` | small maps (and packs) that fail to load, with the `MapException` message, some that load, and runtime errors |
| `maps/<variant>.digest.json` | the parsed map: its top-level fields and the hash of every node's canonical form |
| `maps/<variant>.matcher.json` | `Matcher.match` for up to 28 inputs at every question |
| `maps/<variant>.walks.jsonl` | Tier 1: 6 bot walks, turn by turn, with every random choice logged |
| `maps/hashes.json` | Tier 2: the hash of each of 500 bot walks per variant |
| `nuclear-war/games.jsonl` | Tier 1: Nuclear War games for seeds 1-10, turn by turn, with every random draw logged |
| `nuclear-war/fanout.jsonl` | 68 saved Nuclear War games (up to 3 at each question), each answered with each of 143 utterances |
| `nuclear-war/hashes.json` | Tier 2: the hash of each Nuclear War game for seeds 1-3000 |

A **variant** is a map as the app loads it: the 7 free maps by their folder name (`alien-customs`, `frootopia`,
`leaning-tower-of-pizza`, `noodle-rush`, `pirate-quest`, `signal-decoders`, `the-werewolf`), and the 3 games that
have packs with every `games/<id>/packs/*.json` merged in, sorted by file name (`GameMap.load(map, packs)`, as
MapsTest and PacksTest load them): `alien-customs+packs`, `frootopia+packs`, `the-werewolf+packs`. Lists of variants
are in this order: folders by name, each free variant followed by its `+packs` variant.

Nuclear War uses the real `games/nuclear-war/clips.json` (`NuclearAudio.load`), never the placeholder audio, which
changes which clips exist and so the random draws.

## 2. Canonical encoding

Every value in the fixtures is written by one encoder, `Canon.kt`. The Swift side needs an identical encoder, because
it hashes and compares strings it makes itself (§3, §7).

### 2.1 JSON text

- Compact JSON (RFC 8259): no spaces and no newlines inside a canonical value.
- Object keys are written in the order this README lists for each object; no other keys appear.
- **Strings** are written between `"` with exactly these escapes: `"` as `\"`, `\` as `\\`, and every UTF-16 code unit
  below U+0020 as `\u00xx` with **lowercase** hex (U+000A is `\u000a`, not `\n`). Everything else, U+007F, U+2028
  and all non-ASCII included, is written as itself, UTF-8 encoded in the file. The fixtures never contain an unpaired
  surrogate (the generator fails if one would be written).
- **Integers** (Kotlin `Int`: indexes, counts, bounds, draws, ranks) are written in decimal, with a leading `-` when
  negative.
- **Doubles** are never written as float text. A Kotlin `Double` `d` is written:
  - as an integer (`d.toLong()` in decimal) when `d` is finite, `d == floor(d)`, `abs(d) < 2^53` and `d` is not
    `-0.0`. So `3.0` is `3`, `-2.0` is `-2`, `0.0` is `0`;
  - otherwise as the JSON string `"x"` followed by the 16 lowercase hex digits of its IEEE 754 bits:
    `0.5` is `"x3fe0000000000000"`, `0.2` is `"x3fc999999999999a"`, `-0.0` is `"x8000000000000000"`, `1e300` is
    `"x7e37e43c8800759c"`, infinity is `"x7ff0000000000000"`. **Every NaN is written `"x7ff8000000000000"`**
    (`java.lang.Double.doubleToLongBits`), whatever its payload or sign: the NaN that `0.0 / 0.0` makes differs
    between CPUs.

  Where this README says "a double" it means this encoding. A reader turns an integer into the Double of that value
  and an `"x…"` string into the Double with those bits.
- **Booleans** are `true` / `false`; Kotlin `null` is `null`.

### 2.2 Files

- All files are UTF-8 without a byte-order mark, and end with a newline.
- A `.jsonl` file holds one canonical JSON value per line; lines end with `\n` (never `\r\n`). Line 1 is the header
  (§4). The lines are canonical byte for byte: a reader may compare its own encoding of a turn with a line as strings.
- A `.json` file holds one JSON object. For readable diffs the generator puts a newline before each element of the
  object's large top-level arrays and before such an array's closing `]`. Those newlines are insignificant
  whitespace: read `.json` files with a JSON parser, never by comparing bytes. Every value inside them is canonical.

## 3. Hashes: FNV-1a 64

`fnv(s)` for a string `s` is 64-bit FNV-1a over the **UTF-16 code units** of `s` (not its UTF-8 bytes):

```
h = 0xcbf29ce484222325
for each UTF-16 code unit u of s:  h = (h XOR u) * 0x100000001b3    (wrapping, modulo 2^64)
```

It is written as 16 lowercase hex digits, zero padded: `fnv("")` is `cbf29ce484222325`, `fnv("a")` is
`af63dc4c8601ec8c`, `fnv("é😀")` is `d7bced195d50c881`. In Swift:
`for u in s.utf16 { h = (h ^ UInt64(u)) &* 0x100000001b3 }`.

"The hash of" a value means `fnv` of the value's canonical JSON text (§2.1).

## 4. The header and staleness

Every file begins with the same three fields, in this order:

```
{"format":1,"games_sha256":"<64 hex>","engine_sha256":"<64 hex>", …}
```

In a `.json` file they are the object's first three keys; in a `.jsonl` file line 1 is this object, with the extra
keys listed per file in §9.

- `format`: this README's format, `1`. A reader must fail on any other value.
- `games_sha256`: SHA-256 (lowercase hex) of the game data. Take every regular file under `games/` (recursively) whose
  name ends in `.json`, skipping any file or folder whose name starts with `.`. Take each one's path relative to
  `games/`, with `/` separators (for example `alien-customs/packs/alien-customs-levels.json`). Sort the files by that
  path (code-unit order; the paths are ASCII). Feed SHA-256, for each file in order: the path's UTF-8 bytes, one byte
  `0x00`, the file's size in bytes as ASCII decimal digits, one byte `0x00`, then the file's bytes exactly as on disk.
- `engine_sha256`: the same over every file ending in `.kt` under `android/engine/src/main/kotlin/`, with paths
  relative to that folder (for example `com/epicaudiogames/engine/Session.kt`).

A reader recomputes both from the repository and, when either differs, fails with
`fixtures stale: cd android && ./gradlew :engine:goldens`. (The engine hash changes with any edit to the Kotlin engine,
comments included; that is deliberate.)

## 5. Values

A variable's value (Kotlin `Any`: `Double`, `Boolean` or `String`) is a 2-element array:

| Kotlin | Fixture |
|---|---|
| `Double` | `["n",<double>]`: `["n",3]`, `["n","x3fe0000000000000"]` |
| `Boolean` | `["b",true]` |
| `String` | `["s","text"]` |

A missing value (Kotlin `null`: a variable that isn't set) is `null`. The engine never stores an `Int` in a variable.

A **variable list** is `[["name",<value>],…]` in the Kotlin iteration order of the variables, the insertion order of
the `LinkedHashMap`: `put` on an existing key keeps its place, a new key goes last, `clear` empties it.

Two values are **the same** when their canonical encodings are identical (this is Kotlin's boxed `==`:
`java.lang.Double.equals` compares `doubleToLongBits`, so every NaN is the same as every NaN and `-0.0` differs from
`0.0`; values of different kinds always differ).

## 6. Map canon

The parsed map (GameMap.kt) has one canonical form. Lists keep their Kotlin order; Kotlin maps (`set`, `cases`, `who`,
`vars`, `symbols`, `nodes`) keep their key order, which is the JSON file's order (with packs merged as `Map.plus` does:
a key already present keeps its place and takes the pack's value; a new key goes last).

A condition or an expression is written as its source text (`Condition.source`, `Expr.source`): for a `when`, the text
in the map; for a computed value (`"=n * 2"`), the text after the `=`.

- **Line** (a transcript line): `[at,len,who,text,words,more]`: `at` and `len` doubles; `words` null or a list of
  doubles (the map's `w`); `more` a boolean.
- **Clip**: `[path,dur,sfx,[line,…]]`. A clip's **clip hash** is the hash of this.
- **Step** (also used in turns, §7):
  - `Step.Play`: `["p",path,more,clipHash]`. `more` is a string with one character per line of the clip: `"1"` if that
    line's `more` is true, else `"0"` (`""` for a clip without lines). `clipHash` is the clip hash above.
  - `Step.Num`: `["n",variable]`
  - `Step.Pause`: `["z",seconds]` (a double)
  - `Step.Bed`: `["b",path,volume,dur]`: `path` a string or null; `volume` and `dur` doubles.
  - `Step.When`: `["w",condition,[step,…]]`
  - `Step.Pick`: `["k",[[step,…],…]]`
  - `Step.By`: `["y",variable,[[case,[step,…]],…],[otherwise step,…]]`
- **Go**:
  - `Go.To`: `["to",node]`
  - `Go.Random`: `["random",[go,…]]`
  - `Go.If`: `["if",[[condition,go],…],otherwise go]`
  - `Go.Restart`: `["restart",node]`
  - `Go.Quit`: `["quit"]`
  - `Go.Leave`: `["leave"]`
  - `Go.Draw`: `["draw",[node,…],deck]`
- **Set** (a node's, an answer's or an else's `set`): `[[variable,set value],…]`, where a set value is
  `SetValue.Assign` `["=",<value §5>]`, `SetValue.Add` `["+",amount]` (a double), `SetValue.Rand` `["rand",from,to]`
  (integers) or `SetValue.Calc` `["calc",expression]`.
- **Phrase**: `[text,exact]` (the normalised text).
- **Match**: `Match.Yes` `["yes",[phrase,…]]` (its `extra`), `Match.No` `["no",[phrase,…]]`, `Match.Words`
  `["words",[phrase,…]]`, `Match.Repeat` `["repeat"]`, `Match.Seq` `["seq",seq,table,exact,spelled,least]`,
  `Match.Digits` `["digits",digits,exact,least]` (`least` an integer or null), `Match.Re` `["re",pattern]`,
  `Match.AnyText` `["any"]`.
- **Answer**: `[match,go,set,when,opposite,rank]`: `go` null or a go; `when` null or a condition; `opposite` null or an
  integer; `rank` an integer.
- **Button**: `[label,value]`.
- **Else**: `[[say step,…],set,go]` (`go` null or a go).
- **Ask**: `[[reprompt step,…],[answer,…],else,[button,…]]` (`else` null or an Else).
- **End**: `[kind,title,next,retry,locked]` (the last three null or strings).
- **Node**: `[id,[[condition,go],…],set,[say step,…],ask,go,end]`: the second element is its `redirect`; `ask`, `go` and
  `end` are each null or as above. A node's **node hash** is the hash of this.
- **Map header**: an object with these keys, in this order:
  `{"id":…,"title":…,"start":…,"vars":<variable list>,"keep":[name,…],"repeatSays":<bool>,"who":[[key,name],…],"words":{"yes":[phrase,…],"no":[phrase,…],"repeat":[phrase,…],"mixed":null or {"yes":[word,…],"no":[word,…],"filler":[word,…]}},"symbols":[[table,[[symbol,[word,…]],…]],…]}`.
  `keep` is in its set's iteration order (first appearance in the JSON `keep` lists, the map's then the packs').
- **Map**: `[header,[node,…]]`, nodes in map order. The **map hash** is the hash of this.

Example, a node of noodle-rush (as `-Pgoldens.dump=noodle-rush/nodes` prints it, abridged):
`["Page1",[],[],[["p","scenes/title","000","998ce49735409f87"]],[[["p","prompts/title","0","9d96ffe300354dc3"]],[[["yes",[["ready",true],["i'm ready",true],…]],["to","Page2"],[],null,null,0],…],null,[["Yes","yes"],["No","no"]]],null,null]`.

## 7. Turn lines

A turn line records one call into a game and the `Turn` it returned. It is one canonical object with these keys in
this order:

```
{"t":<int>,"in":<input>,"rng":[<draw>,…],"node":"…","visited":["…",…],"quit":<bool>,"keep":<bool>,
 "end":null|[kind,title,next,retry,locked],"heard":null|[said,answer,how],"steps":[<step>,…],
 "ask":null|{"b":[[label,value],…],"r":[<step>,…],"a":"<hash>"},
 "save":{"node":"…","ended":<bool>,"vars":"<hash>","delta":[[name,<value>|null],…]}}
```

- `t`: the turn's number in its walk or game: `0` for the first call, then `1`, `2`, ….
- `in`: the call (§7.1).
- `rng`: every random draw the game made during the call, in order (§7.2).
- `node`, `visited`, `quit`, `keep`: `Turn.node`, `Turn.visited`, `Turn.quit`, `Turn.keep`.
- `end`: `Turn.end` as an End (§6), or null.
- `heard`: `Turn.heard` as `[said,answer,how]`, `answer` an integer or null; null when the call wasn't an answer.
- `steps`: `Turn.steps` (§6 Step). A map's turn steps are resolved (no `w`, `k` or `y`); Nuclear War's are only `p`,
  `b` and `z`.
- `ask`: `Turn.ask`, or null. `b` is its buttons; `r` its reprompt steps **as stored** (for a map, unresolved: `w`, `k`
  and `y` can appear); `a` the hash of `[[answer,…],else]` (§6), the rest of the Ask.
- `save`: the game's `save()` right after the call: `Saved.node` and `Saved.ended` (for a map, true at an end and after
  a quit that isn't a "leave"); `vars` is the hash of the full variable list of `Saved.vars` (§5), so it pins their
  order too. `delta` lists what changed since the previous line of the same walk or game (for `t` = 0: since an
  empty list): first, in the current order, every variable that is new or not the same (§5) as before, as
  `[name,<value>]`; then, in the previous line's order, every variable that is gone, as `[name,null]`.

Example (noodle-rush, walk 0, `t` = 0):

```
{"t":0,"in":["start"],"rng":[],"node":"Page1","visited":["Page1"],"quit":false,"keep":false,"end":null,"heard":null,"steps":[["p","scenes/title","000","998ce49735409f87"]],"ask":{"b":[["Yes","yes"],["No","no"]],"r":[["p","prompts/title","0","9d96ffe300354dc3"]],"a":"c0b3f88822601ee9"},"save":{"node":"Page1","ended":false,"vars":"51ce9fb89d4a914c","delta":[["nana",["b",false]]]}}
```

### 7.1 Inputs

| `in` | Call |
|---|---|
| `["start"]` | `game.start()` |
| `["answer",said]` | `game.answer(said)` |
| `["silence"]` | `game.silence()` |
| `["next"]` | `game.nextChapter()` |
| `["restart",at]` | `game.restart(at)`; `at` a node id, or null for `restart()` |
| `["resume",node]` | (map walks) `game.resume(Saved(node, {}, true))`: back at a saved chapter end, with the map's starting variables |
| `["reopen"]` | leave and come back: `saved = game.save()`, then a **new** game object (§8 says with which random), then `new.open(saved)` |
| `["return"]` | (map walks) come back after the game quit: `saved = game.save()` (the app stores the save after a quit too, GameController.kt `finishTurn`: a "leave" is picked up again, a plain quit saves as ended and starts again with the map's `keep` variables), then a new `Session` with the same chooser, then `open(saved)` |
| `["open"]` | (fanout) a new game object's `open(saved)`, with the line's save |

### 7.2 Random draws

**Maps.** A `Session`'s random choices all go through its `choose: (Int) -> Int`. Each call is one draw `[n,r]`: `n`
is the argument and `r` the value `choose` returned (before the Session's own `coerceIn`). To replay a line, give the
Session a chooser that, for its k-th call in the turn, checks that its argument equals the k-th draw's `n` and returns
its `r`; at the end of the turn every draw must have been used.

**Nuclear War.** `NuclearWar` gets a `kotlin.random.Random`. Each call the game makes on it (itself, or through the
Kotlin standard library: `shuffled`, `random`, `randomOrNull`) is one draw, logged at the outermost call only (a
`nextInt(n)` is one draw even though XorWow makes it from `nextBits` or `nextInt()` inside):

| Draw | Kotlin call | Result |
|---|---|---|
| `["nextInt",r]` | `nextInt()` | an integer |
| `["nextInt",until,r]` | `nextInt(until)` | an integer |
| `["nextInt",from,until,r]` | `nextInt(from, until)` | an integer |
| `["nextBits",bitCount,r]` | `nextBits(bitCount)` | an integer |
| `["nextDouble",r]` | `nextDouble()` | a double (§2.1) |
| `["nextBoolean",r]` | `nextBoolean()` | a boolean |

The game makes no other kind of call (the generator fails if it does). Nuclear War in fact only calls
`nextInt(until)` and `nextDouble()`. Kotlin's helpers draw like this: `list.random(rnd)` and `list.randomOrNull(rnd)`
are one `nextInt(size)`, and `randomOrNull` on an empty list draws nothing; `list.shuffled(rnd)` copies the list and,
for `i` from `size - 1` down to `1`, draws `j = nextInt(i + 1)` and swaps elements `i` and `j`. To replay, a
`ReplayRandom` returns the logged results in order and fails on the first call whose method or bound differs from the
log, naming the draw's index.

Example: `"rng":[["nextInt",2,0],["nextInt",3,2],["nextDouble","x3fe2d9e03c9b612d"]]`.

## 8. The bots

The bots are the generator's own copies of MapsTest's walk and of NuclearWarTest's player (`GoldenBots.kt`; the tests
themselves are unchanged). Every random number comes from a seeded `Random(seed)`, Kotlin's XorWow (`random.json` pins
it), so the bots are deterministic.

### 8.1 Map walks (`maps/*.walks.jsonl`, `maps/hashes.json`)

`entries(M)`, for a `+packs` variant `M`: the ids of the nodes of `M`, in map order, whose `end` has kind `"chapter"`
and a `next` that is a node of `M` defined by one of its packs (a key of a pack file's `nodes`). They are the chapter
ends where a pack's chapters begin (for `alien-customs+packs`: `L4_win`, `L5_win`, …; for `frootopia+packs`: `fr-55`,
`fr-54`, `fr2-end`, …). For a free variant, and for `the-werewolf+packs`, `entries` is empty. The walks file's header and
`hashes.json` list them.

Walk `w` (0-based) of a variant `M`:

```
seed = w + 1
rng = Random(seed)                         // one XorWow, shared by the bot and the session
choose(n) = rng.nextInt(n), logged as [n, r] in the current line's "rng"
s = Session(M, choose)
if entries(M) is not empty and w % 2 == 1:
    e = entries(M)[(w / 2) % entries(M).size]          // integer division
    t = s.resume(Saved(e, {}, true))                    // line t=0, ["resume", e]
else:
    t = s.start()                                       // line t=0, ["start"]
last = null
for i in 0 until 80:
    if t.quit:
        saved = s.save()
        s = Session(M, choose); t = s.open(saved)                            // ["return"]
    else if (i + 1) % 25 == 0:                                               // i = 24, 49, 74
        saved = s.save(); s = Session(M, choose); t = s.open(saved)          // ["reopen"]
    else if t.end != null:
        e = t.end
        if e.kind == "chapter" and e.next != null and e.next is a node of M:  t = s.nextChapter()   // ["next"]
        else if e.kind == "gameover" and e.retry != null:                    t = s.restart(e.retry) // ["restart", e.retry]
        else:                                                                t = s.restart(null)    // ["restart", null]
    else:
        options = inputs(t.ask)
        taken = options without its first 3 elements, or options itself if that leaves nothing
        if w % 2 == 1 and last is in options and rng.nextBoolean():  said = last
        else if rng.nextInt(4) > 0:                                   said = taken[rng.nextInt(taken.size)]
        else:                                                          said = options[rng.nextInt(options.size)]
        last = said
        t = said == null ? s.silence() : s.answer(said)              // ["silence"] or ["answer", said]
    the turn must ask, end or quit (else the generator fails)
    write line t = i + 1
```

So every walk has exactly 81 lines (`t` = 0 to 80). The conditions are evaluated left to right and stop early (`&&`):
`nextBoolean` is drawn only in odd walks when `last` is in `options`. `options` always contains null (silence), so
`last == null` (before the first answer, or after a silence) counts as being in `options`. `last` carries on across
`reopen` and `return`. The bot's own draws (`nextBoolean`, `nextInt(4)`, the index) are made on the same `rng` as
`choose` but are **not** logged; only `choose` calls are. Each new `Session` gets the same `choose` (the same `rng`).

Compared with MapsTest's walk: MapsTest stops a walk at a quit, never starts at a chapter end, and never leaves and
comes back; the rest is MapsTest's, line for line.

`inputs(ask)`, MapsTest's list of one answer of each kind the question takes:

```
out = [null, "zzz", M.words.repeat[0].text]          // silence, nonsense, the map's first repeat phrase
out += the value of each of ask.buttons, in order
for each answer a of ask.answers, in order:
    Match.Yes      -> "yes"
    Match.No       -> "no"
    Match.Words    -> the text of its first phrase
    Match.Repeat   -> M.words.repeat[0].text
    Match.Seq      -> for each UTF-16 unit c of seq: the first word of M.symbols[table][c]; joined with " "
    Match.Digits   -> the UTF-16 units of digits joined with " " ("314" -> "3 1 4")
    Match.Re       -> nothing
    Match.AnyText  -> "something else entirely"
keep null and every string that is not blank (blank: empty or only whitespace, Kotlin Char.isWhitespace)
remove duplicates, keeping the first of each
```

### 8.2 Nuclear War games (`nuclear-war/games.jsonl`, `nuclear-war/hashes.json`)

Game `seed` (1-based):

```
game = NuclearWar(audio, Random(seed))      // its draws are logged in each line's "rng"
r = Random(seed * 7919 + 1)                 // the bot's own; not logged
t = game.start()                            // line t=0, ["start"]
n = 0
while t.end == null:
    n += 1                                  // the generator fails at n == 600 (n == 900 after the reopen)
    if n == 37:
        saved = game.save()
        game = NuclearWar(audio, Random(seed + 37))          // ["reopen"]: the new game's draws are logged from here on
        t = game.open(saved)                                 // (the generator fails if t.ask == null)
    else:
        buttons = t.ask.buttons
        if r.nextInt(20) == 0:                                  t = game.silence()                                      // ["silence"]
        else if buttons is not empty and r.nextInt(10) < 7:     t = game.answer(buttons[r.nextInt(buttons.size)].value) // ["answer", value]
        else:                                                   t = game.answer(EXTRAS[r.nextInt(EXTRAS.size)])         // ["answer", extra]
    write line t = n
```

`EXTRAS`, in order (27 strings; the last is empty): `yes`, `no`, `yeah`, `nope`, `shield`, `research`, `all of them`,
`next`, `next round`, `none`, `3`, `two`, `twenty`, `repeat`, `banana`, `france`, `the uk`, `america`, `china`,
`russia`, `paris`, `new york`, `moscow`, `london`, `shanghai`, `st petersburg`, ``.

This is NuclearWarTest's player exactly: it leaves and comes back once, at turn 37, with `Random(seed + 37)`.

## 9. The files

`…` stands for text left out of this README; `<h>` for a 16-hex-digit hash.

### 9.1 `random.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,
 "vectors":[{"seed":<int>,"draws":[<draw>,…]},…],
 "shuffles":[{"seed":<int>,"size":<int>,"result":[<int>,…]},…]}
```

- `vectors`: for each seed, a fresh `Random(seed)` (`XorWowRandom(seed, seed shr 31)`), then the draws in order, in the
  Nuclear War draw encoding of §7.2, with the result Kotlin returned. Each vector mixes raw `nextInt()`, `nextInt(n)`
  for powers of two (1 included: `nextInt(1)` draws and returns 0) and other bounds (some close to 2^31, where the
  rejection loop can run more than once), `nextInt(from, until)` (negative ranges, and ranges wider than `Int`, which
  loop on `nextInt()`), `nextBits(0…32)`, `nextDouble()` and `nextBoolean()`.
- `shuffles`: `(0 until size).toList().shuffled(Random(seed))`.

Example: `{"seed":42,"draws":[["nextInt",972016666],…,["nextInt",1,0],…]}`;
`{"seed":1,"size":5,"result":[4,3,1,2,0]}`.

### 9.2 `text.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,
 "strings":[[s,normalise,digits,isPause],…],
 "phraseLength":[[text,[phrase,exact],result],…],
 "longest":[[text,[[phrase,exact],…],result],…],
 "negated":[[text,phrase,result],…],
 "tables":{"<name>":[[symbol,[word,…]],…],…},
 "symbols":[[said,table,spelled,result],…],
 "mixed":[[variant,text,result],…],
 "toDouble":[[s,result],…],
 "doubleString":[[d,javaString],…],
 "json":[[jsonText,toString],…],
 "primitives":[[jsonText,content,isString,doubleOrNull,booleanOrNull,intOrNull,longOrNull],…],
 "dropped":[…]}
```

- `strings`: every raw phrase, button label and value and symbol word in the maps and packs, TextTest's inputs, the
  Nuclear War utterances and edge cases (`"99999999999 thousand"`, `"9223372036854775807 hundred"`, `"twenty to"`,
  `"I want to play"`, `"one's"`, curly quotes, accents, `İ`, the Kelvin sign, `ß`, `ﬁ`, full-width digits, controls,
  `""`, …):
  `Text.normalise(s)`, `Text.digits(s)` and `Commands.isPause(s)`.
- `phraseLength`: `Text.phraseLength(text, Phrase(phrase, exact))`, an integer (-1: not said).
- `longest`: `Text.longest(text, phrases)`: the phrase `[text,exact]` it returns, or null.
- `negated`: `Text.negated(text, phrase)`.
- `symbols`: `Text.symbols(said, tables[table], spelled)`. `tables` holds TextTest's two tables (`test-letters`,
  `test-turns`) and the maps' symbol tables by name (Signal Decoders' `letters`, `turns`, `sos`, `notes`), each in
  map order.
- `mixed`: `Matcher.mixed(map, text)` with the free variant's map: `true`, `false` or null. `text` is already
  normalised.
- `toDouble`: Kotlin `String.toDoubleOrNull()` (the JVM grammar: `"1e5"`, `" 2 "`, `"1d"`, `"0x1p3"`, `"NaN"`, …): a
  double or null.
- `doubleString`: `java.lang.Double.toString(d)` on JDK 17, the text Kotlin's `"$d"` gives, for values where it has the
  shortest digits (§10).
- `json`: `Json.parseToJsonElement(jsonText).toString()` with kotlinx.serialization 1.6.3, the text that the map errors
  embed (§9.4). Literals keep their raw text (`1.0` stays `1.0`, `1E+2` stays `1E+2`); strings are re-escaped the
  kotlinx way (`\"`, `\\`, `\n`, `\t`, `\b`, `\f`, `\r`, the other controls `\u00xx` in lowercase, everything else
  as itself, `/` and U+007F included); a duplicate key keeps the last value at the first key's place.
- `primitives`: for JSON text that parses to a primitive: its `content` (a string; JSON null's is `"null"`),
  `isString`, `doubleOrNull` (a double or null), `booleanOrNull` (kotlinx's: `true`/`false` ignoring case, on strings
  too), `intOrNull` (an integer or null) and `longOrNull` (**a string** of decimal digits, or null, since it can pass
  2^53). The last two are kotlinx's own number reader (`StringJsonLexer.consumeNumericLiteral`), which
  `State.fromJson` uses through `.int` and `.long` (those throw where these give null).
- `dropped`: `["doubleString",d,javaString]` for each double left out of `doubleString` (§10).

### 9.3 `expr.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,
 "varsets":[{"name":"initial"|"missing"|"mixed"|"numbers","game":<variant>|null,"vars":<variable list>},…],
 "exprs":[[variant,source,kind,[name,…],[[value,test,key],…]],…],
 "extra":[[source,[name,…],[[value,test,key],…]],…],
 "errors":[[source,message],…],
 "dropped":[[variant|null,source],…]}
```

- `exprs`: for each game, under its fullest variant (in variant order: `alien-customs+packs`, `frootopia+packs`,
  `leaning-tower-of-pizza`, `noodle-rush`, `pirate-quest`, `signal-decoders`, `the-werewolf+packs`), every distinct
  `when` (`kind` `"when"`; a string value of a `"when"` key anywhere) and computed value (`kind` `"calc"`; a string
  value starting with `=` in a `"set"` object, without the `=`) in its map and packs, in order of first appearance: the
  map file, then the packs in file-name order; within a file, a depth-first walk of objects in key order.
- `[name,…]`: `Expr.names`, in its set's order.
- The results: one `[value,test,key]` per var set, in this order: the game's `initial`, then `missing`, `mixed`,
  `numbers`. `value` is `Expr.eval(vars)` as a value (§5; null when it's a missing variable), `test` is
  `Expr.test(vars)` and `key` is `Expr.key(value)` (the `by` key: `""` for null, a whole number's digits via
  `toLong()` (which saturates), Java's `Double.toString` for any other number, `"NaN"` included, else `toString()`).
- `varsets`: `initial` is a game's `map.vars` (one per game, `game` its variant); `missing` is empty; `mixed` gives
  every name used by any expression (the games' first, then `extra`'s, in first-use order) the values `true`, `false`,
  `""`, `"abc"`, `"12"` in turn; `numbers` gives them `NaN`, `-0.0`, `1e7`, `-Infinity`, `2.5`, `1e-5`, `0.1` in turn.
- `extra`: hand-written expressions (operators, `same()`, string comparisons, `%` on negatives, NaN, `max`/`min` on NaN
  and `-0.0`, numeric strings, whitespace oddities), with results under `missing`, `mixed` and `numbers`, in that order.
- `errors`: `Expr.parse(source)` failing: the `MapException` message.
- `dropped`: expressions left out because a result's text holds a double whose JDK 17 text isn't the shortest (§10).

### 9.4 `map-errors.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,
 "cases":[{"name":…,"map":<json text>,"packs":[<json text>,…],"ok":"<map hash>"}
          | {"name":…,"map":…,"packs":[…],"error":"<MapException message>"}
          | {"name":…,"map":…,"packs":[…],"error":true},…],
 "runtime":[{"name":…,"map":<json text>,"calls":[<input>,…],"error":"<message>"},…]}
```

- `cases`: `GameMap.parse(map, packs)`. `ok` holds the map hash (§6) when it loads. When it throws a `MapException`,
  `error` is its message, exactly (many embed kotlinx `toString()` text cut to 120 UTF-16 units by `take(120)`; one cut
  ends just after a backslash). Any other exception (a failed `.jsonObject` cast, `toInt()`, a bad regex) gives
  `"error":true`: compare only that it fails. All the texts are RFC 8259 JSON.
- `runtime`: the map loads; the calls (§7.1 inputs: `start`, `answer`, `silence`, `next`, `restart`) are made in order
  on one `Session(map) { 0 }`, and the last one throws: `error` is the exception's message (a `MapException` or an
  `IllegalStateException`).

### 9.5 `maps/<variant>.digest.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,"variant":"noodle-rush","files":["noodle-rush/map.json"],
 "map":<map header §6>,"hash":"<map hash>","nodes":[[id,"<node hash>"],…]}
```

`files` are the files loaded, relative to `games/`, in load order. `nodes` is every node in map order. On a mismatch a
reader should print its own canonical text for the node, to compare with `-Pgoldens.dump=<variant>/nodes`.

### 9.6 `maps/<variant>.matcher.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,"variant":"noodle-rush",
 "asks":[[node,[[said,index,repeat,how,aside],…]],…]}
```

For every node with an `ask`, in map order (for a `+packs` variant, only the nodes its pack files define, since the
others give the same results as in the free variant): `Matcher.match(map, node.ask, map.vars, said)` for each input,
with `map.vars` the variant's starting variables. `index` is `Result.index` (null for none), `repeat` is
`Result.repeat`, `how` is `Result.how` and `aside` is `Result.aside` (no answer taken, but the answer was heard: it is
unsure, or a phrase in it is negated and doesn't count). The inputs are the buttons' values and labels, the walk's
`inputs` (§8.1), `""`, `"yeah no"`, `"no yes"`, `"um yes"`, `"Say that AGAIN?"`, `"stop"`, then more phrases and
renderings of each answer (other phrases, `not …`, `I don’t want to …`, upper case with `!`, the seq's symbols run
together, digits as one number), without repeats and cut to the first 24; then always `"I'm not sure"`,
`"of course not"`, `"I want to play"` and `"one more time"` (each unless already there), so at most 28 per
question.

Example: `["Page2",[["yes",0,false,"\"yes\"",false],…,["yeah no",1,false,"mixed: no",false],…,`
`["not inside",null,false,"not understood",true],…,["I'm not sure",null,false,"not understood",true],…]]`.

### 9.7 `maps/<variant>.walks.jsonl`

Line 1 is the header with three more keys:
`{"format":1,"games_sha256":…,"engine_sha256":…,"variant":"noodle-rush","walks":6,"entries":[…]}` (`entries` as in
§8.1). Then, for each walk `w` = 0 to 5 (§8.1): a walk line `{"walk":<w>,"seed":<seed>}`, then its 81 turn lines (§7),
with `rng` draws `[n,r]`. Example:

```
{"walk":0,"seed":1}
{"t":0,"in":["start"],"rng":[],"node":"Page1",…}
…
{"t":3,"in":["return"],"rng":[],"node":"Page1","visited":["Page1"],…}
```

and, from pirate-quest: `{"t":27,"in":["answer","dice"],"rng":[[6,1],[6,2],[6,0],[6,5],[6,2],[6,1]],"node":"ac-8b",…}`.

### 9.8 `maps/hashes.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,"walks":500,"turns":80,"reopen":25,
 "variants":[{"variant":"alien-customs","entries":[…],"lines":<int>,"visited":<int>,"nodes":<int>,"walks":["<h>",…]},…]}
```

For each variant, `walks[w]` (w = 0 to 499) is the hash of walk `w` (§8.1): `fnv` of the walk's turn lines, each
followed by `"\n"`, concatenated (the `{"walk":…}` line is not included). `lines` is the number of turn lines of the
500 walks; `visited` the number of distinct node ids in their `visited` lists, and `nodes` the map's node count (a
measure of how much of the map the walks cover). Walks 0-5 are the ones in `walks.jsonl`, so a reader can check its
line encoding there first.

### 9.9 `nuclear-war/games.jsonl`

Line 1 is the header with one more key: `{"format":1,…,"seeds":[1,10]}`. Then for each seed: a game line
`{"seed":<seed>,"turns":<number of turn lines>,"end":<the last turn's end title>}`, then its turn lines (§7, §8.2) with
Nuclear War draws (§7.2). The save's variables are `state` (the State JSON, `State.toJson().toString()`, kotlinx text)
and `settings` (`State.settingsJson().toString()`). `node` is the state's question (a `Q` name); `visited` is always
empty; `quit` and `keep` are always false. Example: `{"seed":1,"turns":39,"end":"Your cities were destroyed"}`, then
`{"t":0,"in":["start"],"rng":[["nextInt",5,0],["nextInt",4,2],…],"node":"CHOOSE_COUNTRY",…,"save":{…,"delta":[["state",["s","{\"q\":\"CHOOSE_COUNTRY\",…}"]],["settings",["s","{\"playedNuclear\":true,\"rundown\":false,\"completed\":false}"]]]}}`.

### 9.10 `nuclear-war/fanout.jsonl`

Line 1 is the header with one more key, the utterance corpus: `{"format":1,…,"utterances":[u0,u1,…]}`. Then one line
per sampled save:

```
{"save":{"node":…,"ended":<bool>,"vars":<variable list>},"seed":<int>,"open":"<h>","results":[[i,answer,how,node,understands,"<h>"],…]}
```

The saves: going through the games of §8.2 for seeds 1 to 3000 in order, and each game's turns in order, every save
(the `save()` after each line, the reopened game's included) whose `node` has been taken fewer than 3 times so far.
Ended saves (`GAME_OVER`) are among them. Line `k` (1-based, after the header) has `seed` = `k`. For each utterance `i`:

```
game = NuclearWar(audio, Random(seed))      // draws logged
t0 = game.open(save)                        // turn line t=0, in ["open"]; "open" is the hash of this line
understands = game.understands(utterances[i])
t1 = game.answer(utterances[i])             // turn line t=1, in ["answer", u], its delta against line t=0
```

`results[i]` is `[i, t1.heard.answer, t1.heard.how, t1.node, understands, the hash of line t=1]`. The game is made
afresh for every utterance, so `open` is the same each time.

### 9.11 `nuclear-war/hashes.json`

```
{"format":1,"games_sha256":…,"engine_sha256":…,"seeds":[1,3000],"games":[["<h>",<turn lines>,<end title>],…]}
```

`games[k]` is game `seed = k + 1`: the hash is `fnv` of its turn lines, each followed by `"\n"`, concatenated (the game
line is not included), as in `games.jsonl` for seeds 1 to 10.

## 10. JDK 17 `Double.toString`

Kotlin's `"$d"` is Java's `Double.toString`, and the engine builds with JDK 17, which doesn't always give the shortest
digits (JDK-4511638, fixed in JDK 19). Swift's `Kt.doubleString` is specified as Java's layout over the shortest
round-tripping digits: plain decimal with at least one digit after the point when `1e-3 <= |d| < 1e7` (`"0.001"`,
`"2.5"`, `"1234567.0"`), else `d.dddE±n` with at least one digit after the point and no `+` (`"1.0E7"`, `"1.0E-5"`,
`"-1.2345E-4"`); and `"NaN"`, `"Infinity"`, `"-Infinity"`, `"0.0"`, `"-0.0"`.

The generator checks every double the corpora turn into text (`doubleString`, and every `key` and string result in
`expr.json`, whose texts it scans for Java double text): it rounds the double's exact value half-even to 1, 2, …
significant digits until the result reads back as the same double (as JDK 19 chooses) and drops any value whose JDK 17
text has other digits, listing it under `dropped`. Found so far, in `text.json`: `1e23` (JDK 17:
`9.999999999999999E22`, shortest `1.0E23`) and `±4.9E-324` (shortest `5E-324`, so `"4.9E-324"` has other digits). No
expression result was dropped.

## 11. Dump mode

`-Pgoldens.dump=<spec>` makes `goldens` (or `goldensCheck`) write only the dump, to
`android/engine/build/golden-dump/<spec with each "/" replaced by "_">.jsonl`, and leave the fixtures alone:

| Spec | Lines |
|---|---|
| `<variant>/walk/<w>` | walk `w` of §8.1 (any `w`, not only 0-5): its walk line and turn lines, as in `walks.jsonl` |
| `<variant>/nodes` | each node's canonical text (§6), one per line, in map order |
| `nuclear-war/game/<seed>` | the game line and turn lines of §8.2 (any seed) |

`eag --dump <spec>` on the Swift side writes the same lines, so the two files can be compared with `diff`.

## 12. What the fixtures leave out

- Unpaired surrogates: `take(120)` in a map error can cut a surrogate pair in two in Kotlin, which a Swift `String`
  can't hold. No case in `map-errors.json` does.
- JSON that only kotlinx accepts (unquoted literals and the like): every text in the corpora is RFC 8259.
- `MapException` messages are pinned; other exceptions only as "it fails".
- MapsTest's explore (`Bot.explore`) and its printed numbers: they are not deterministic in Kotlin
  (MapsTest.kt:109), so nothing here pins them; the walks of §8.1 are the deterministic sweep.
