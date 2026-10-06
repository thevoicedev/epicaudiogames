# The game map format (version 1)

Every Epic Audio Game is a **map**: a JSON graph of turns. The app's engine walks the map. It plays each turn's
audio with its transcript, listens for an answer, and follows that answer to the next turn. A map is content only
(JSON and audio). All the logic that reads it lives in the app.

A game folder (or a downloaded pack) holds:

```
games/<id>/map.json      the turns
games/<id>/pack.json     what is free and what is in each paid pack
content/<id>/<path>.*    the audio (built by tools/, kept out of git)
```

## The map

```json
{
  "format": 1,
  "id": "noodle-rush",
  "title": "Noodle Rush",
  "start": "Page1",
  "vars": { "nana": false },
  "repeat": "reprompt",
  "who": { "NARRATOR": "Narrator", "CHEF": "Chef" },
  "words": { "yes": ["yes", "yeah", "sure"], "no": ["no", "nope"], "repeat": ["repeat", "say that again"] },
  "symbols": { "letters": { "c": ["c", "see", "sea"], "a": ["a", "ay", "eh"] } },
  "nodes": { "Page1": { "...": "..." } }
}
```

| Field | Meaning |
|---|---|
| `format` | always `1` for this version |
| `id`, `title` | the game's id (also its content folder) and the name shown in the app |
| `start` | the first node |
| `vars` | the game's variables and their starting values: numbers, true/false or text |
| `keep` | optional: variables that keep their values when the game starts again (see Saving) |
| `repeat` | what "repeat" does at a question: `"say"` plays the node's `say` again; `"reprompt"` (the default) plays the reprompt |
| `who` | the speaker keys used in transcripts, with the name to show for each |
| `words` | the shared word lists for `yes`, `no` and `repeat` answers, and optionally `mixed` (see Matching) |
| `symbols` | named tables for `seq` answers: each symbol and the words that mean it |
| `nodes` | the turns, by id |

## A node

A node is one turn. In order, the engine:

1. follows `redirect` if one applies (before anything plays);
2. applies `set`;
3. plays `say`;
4. then does exactly one of these: waits for an answer (`ask`), moves on (`go`), or finishes the game (`end`).

A node with `go` flows straight into the next node in the same turn, just as an Alexa response plays several clips
in a row.

```json
"queue": {
  "say": [
    { "play": "scenes/queue", "dur": 21.4, "lines": [
        { "at": 0.25, "len": 2.9, "who": "NARRATOR", "text": "The line is huge." },
        { "at": 3.5,  "len": 0.8, "who": "CHEF",     "text": "Next!" } ] }
  ],
  "ask": {
    "reprompt": [ { "play": "prompts/queue", "dur": 3.9, "lines": [
        { "at": 0.25, "len": 3.3, "who": "NARRATOR", "text": "Will you wait your turn? Say yes, or no." } ] } ],
    "answers": [
      { "yes": true, "go": "wait" },
      { "no": true, "go": "cut" },
      { "words": ["wait", "wait patiently", "queue"], "go": "wait" },
      { "words": ["cut", "cut the line", "skip"], "go": "cut" }
    ],
    "buttons": [ { "label": "Yes", "value": "yes" }, { "label": "No", "value": "no" } ]
  }
}
```

### `say`: what plays

A list of steps, played in order:

| Step | Meaning |
|---|---|
| `{ "play": path, "dur": s, "lines": [...] }` | a clip: a pre-mixed turn (voices, music and sound effects in one), a line, or a sound, with its transcript. Music and sound effects have `"sfx": true` and no lines |
| `{ "bed": path, "volume": 0.25, "dur": s }` | a sound under the rest of the turn: it starts here, plays once at this volume (0 to 1) while the following steps play, and stops when the turn's audio ends. A bed that is already playing keeps playing. `{ "bed": null }` stops the beds |
| `{ "pick": [[steps], [steps], ...] }` | one of these step lists, at random |
| `{ "by": "var", "cases": { "10": [steps], ... }, "else": [steps] }` | the steps for the variable's value (whole numbers without ".0", true/false, or text) |
| `{ "num": "var" }` | reads out a number variable with the shared number clips |
| `{ "pause": s }` | silence |

Any step can have `"when": condition`: it only plays when the condition holds. `when`, `pick` and `by` are worked
out as the turn plays, with the variables as they are then.

- **`path`** is relative to the game's content folder and has no extension. `scenes/queue` is
  `content/noodle-rush/scenes/queue.m4a` (or `.mp3`, `.opus`: the app takes whichever is there).
- **`dur`** is the clip's length in seconds.
- **`lines`** is the transcript, one entry per spoken line:
  - `at`: seconds from the start of the clip;
  - `len`: how long the line takes;
  - `who`: a key in `who`;
  - `text`: the words.

  A line may also carry `w`, the start time of each of its words (relative to `at`). Without it, the app spreads
  the words over `len`.

### `ask`: waiting for an answer

| Field | Meaning |
|---|---|
| `reprompt` | steps played when the player says nothing (or isn't understood, if there is no `else`) |
| `answers` | the answers this question accepts (see below) |
| `else` | what happens when nothing matches (see below) |
| `buttons` | the answer buttons: `{ "label", "value" }`. Tapping one sends its `value` through the same matching as speech and typing |

An **answer** matches in one way:

| Match | Meaning |
|---|---|
| `"yes": true` / `"no": true` | a phrase from `words.yes` / `words.no`, or from the answer's own `words` |
| `"words": [...]` | one of these phrases |
| `"repeat": true` | a phrase from `words.repeat` |
| `"seq": "cac", "symbols": "letters"` | the words, turned into symbols with the named table, contain this sequence. Options: `"exact": true` (they are exactly this sequence); `"spelled": true` (a word made only of symbol letters, such as "ac", counts letter by letter); `"least": 2` (at least this many symbols, whatever they are: "it looks like an answer") |
| `"digits": "42211"` | the digits said, in order, contain these. Options: `"exact": true` (they are exactly these); `"least": 2` (at least this many digits). "four two two one one", "4 2 2 1 1" and "forty two thousand two hundred and eleven" all give 42211 |
| `"re": "\\bsos\\b"` | a regular expression that finds a match in the normalised text |
| `"any": true` | anything at all |

Phrases match as whole words: "red" doesn't match "ready". A phrase starting with `=` must be the whole answer:
`"=fine"` matches "fine" but not "I'm fine".

An answer can also have:

| Field | Meaning |
|---|---|
| `go` | where to go next. An answer without `go` counts as not understood: after its `set`, the question's `else` runs |
| `set` | variables to change first |
| `when` | a condition: the answer only counts while it is true |
| `rank` | a whole number, 0 if left out: answers of a higher rank are tried first (see Matching). "No" answers ranked above "yes" make "yeah no" a no |
| `opposite` | for "don't follow"-style answers: the index of the answer to take instead when the matched phrase is negated ("don't", "dont", "not" or "never" up to three words before it) |

**`else`** is either a `go` target or an object `{ "say": [...], "set": {...}, "go": ... }`.
- With a `go`, the game moves on.
- Without one, the engine plays the `say` (or, if there is no `say`, the reprompt) and waits on the same question
  again.
- With no `else` at all, it plays the reprompt and waits.

### `go`: where next

- a node id: `"wait"`;
- `{ "random": ["oranges", "pigeon"] }`: one of these at random (a target listed twice is twice as likely);
- `{ "if": [ { "when": "tries >= 2", "go": "reveal" } ], "else": "hint" }`: the first case whose condition holds;
- `{ "restart": "fr-1" }`: start the game again at this node, with the starting variables (except `keep`);
- `{ "draw": ["q1", "q2", ...], "deck": "main" }`: one of these nodes that the deck hasn't drawn yet, at random.
  When all of them have been drawn, the deck starts again. The draws are kept in the variable `deck_<deck>`, so
  declare it in `vars`, and list it in `keep` to carry the deck over to the next play;
- `{ "end": "quit" }`: leave the game (the player said no to starting, or gave up). The app goes back to its list.
- `{ "end": "leave" }`: leave the game for now, keeping the player's place: the game is saved at the question just
  answered, and picks up there next time (as an Alexa game did after "no, not now" ended the session).

### `redirect`

A list of `{ "when": condition, "go": target }`, checked before the node plays. The first that holds sends the
player there instead.

### `set`

Variables to change: `{ "nana": true }`, `{ "tries": "+1" }`, `{ "hope": "-5" }`, `{ "choice": "hide" }`,
`{ "roll": "rand(1,6)" }`, `{ "best": "=streak > best ? streak : best" }`. A string of `+` or `-` and a number adds
to the variable; a string starting with `=` is an expression (see Conditions); anything else replaces it. They are
applied in the order listed.

### `end`: the end of a game

```json
"end": { "kind": "chapter", "title": "Chapter 1: The First Signal", "next": "ai2-title" }
```

| Field | Meaning |
|---|---|
| `kind` | `ending` (a story ending), `chapter` (a chapter is done and another follows) or `gameover` (try again) |
| `title` | shown on the end screen |
| `next` | for `chapter`: the node where the next chapter starts. The end screen offers it, and the variables carry over |
| `retry` | for `gameover`: the node that "try again" goes back to |
| `locked` | a pack id, when `next` is in a paid pack. The end screen offers the pack instead |

The node's `say` plays first. The app then shows its end screen.

## Conditions

`when`, `if`, `redirect` and `=` values are small expressions on the variables:

- `nana`: the variable is true (or non-zero, or non-empty); `!nana`: it isn't;
- `tries >= 2`, `hope < 10`, `choice == "hide"`, `streak > best`: comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`);
- `a && b`, `a || b`: both, either (`&&` binds tighter);
- `+ - * / %` and brackets, `max(a, b)`, `min(a, b)`, `floor(a)`; `cond ? a : b`;
- numbers, `"text"`, `true` and `false`. A missing variable is 0 in sums and false in tests.

## Matching what the player says

Speech, typed text and buttons are matched the same way:

1. **Normalise:**
   - lower case;
   - curly apostrophes become `'`;
   - everything that isn't a letter, a digit or an apostrophe becomes a space;
   - runs of spaces are collapsed.
2. **Skip** answers whose `when` doesn't hold.
3. **Mixed yes and no** (if the map has `words.mixed`): an answer of two or more words, all of them `mixed.yes`
   words, `mixed.no` words or `mixed.filler` words, counts as its last yes or no word: "no yes" is the question's
   `yes` answer, "yeah no" and "no thanks" its `no` answer. A `mixed` phrase of two words ("why not") counts as one
   word. This is the Alexa skill's own rule for kids who change their mind mid-answer.
4. **Rank by rank,** highest first (answers without a `rank` are rank 0):
   1. **exact checks:** `seq`, `digits` and `re` answers, in the order listed. The first that matches wins;
   2. **phrases:** `yes`, `no`, `words` and `repeat` answers. The longest phrase found wins over phrases inside it:
      "no rehearsal" beats "rehearsal". If the winner has `opposite` and its phrase is negated, the opposite answer
      is taken instead. Two answers that would do different things, said apart ("follow or hide"), are unclear:
      this rank gives no answer, and the next rank is tried.
5. **The map's repeat words**, if the question has no `repeat` answer: they do what the map's `repeat` says.
6. **`any`** answers.
7. **Nothing matched:** `else`.

**Silence** (no answer before the app's timeout) plays the reprompt and waits again.

**App commands:** the app handles "stop" and "cancel" itself, when they are the whole answer: they pause the game,
as Alexa's Stop and Cancel end a skill. Maps never see them, so they can't be answers (the validator warns about
them). "Pause" is left to the games: Leaning Tower of Pizza takes it as a mishear of "false".

## Packs (`pack.json`)

```json
{
  "game": "werewolf",
  "packs": [
    { "id": "werewolf-base", "free": true, "title": "5 stories" },
    { "id": "werewolf-more", "product": "werewolf_more_stories", "title": "45 more stories", "nodes": "werewolf-more.json" }
  ]
}
```

A paid pack adds nodes (merged into the map) and their audio. An `end` with `"locked": "<pack id>"` offers the pack
when it's reached without it.

## Saving

The app saves, per game: the current node, the variables, and the end the player reached. A game picked up again
plays its question's node again (or, when that node says nothing itself because the turn before it did the
talking, its reprompt). A game that starts again (from its end screen, or `go: { "restart" }`) starts with the
starting variables, except those listed in `keep`. A chapter's `next` keeps all of them.
