"""Rules the Alexa skill applies to every game, before the game sees an answer (all-minigames-sites,
alexa/lambda/Functions/SkillFlow.js), for every map the tools build."""

# getYesNoPhraseAnswer, copied by hand (its lists are local to that function): answers of two or more words that
# are all yes words, no words and fillers count as their last yes or no word ("no yes" is a yes, "yeah no" a no),
# and a few whole phrases are a yes.
MIXED = {"yes": ["yes", "yeah", "yep", "yup", "ya", "yah", "sure", "why not"], "no": ["no", "nope", "nah"],
         "filler": ["alexa", "sir", "please", "ok", "okay", "thank", "thanks", "you", "hell", "i", "said"]}
YES_PHRASES = ["=yes i am", "=i'm ready to play", "=yes i'm ready to play", "=yes i did"]


def words(yes, no, repeat):
    """A map's "words": its yes, no and repeat lists, with the skill's yes phrases and mixed rule."""
    return {"yes": yes + [p for p in YES_PHRASES if p not in yes], "no": no, "repeat": repeat, "mixed": MIXED}
