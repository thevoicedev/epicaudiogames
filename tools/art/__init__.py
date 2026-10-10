"""The store-art tool's package (tools/make_art.py runs it): the app icon, the Play feature graphic, the website's
icons and social image and the framed store screenshots, from AI concept art to the exact files each app, store and
page wants. docs/STORE_ART.md walks through it.

  brand.py     where everything lives; brand/brand.json and its friends
  api.py       the OpenAI Images API: the key, the calls, the retry rules
  cache.py     every paid image kept for good (tools/cache/art/), the cost ledger and the budget guard
  concepts.py  concept art from brand/prompts/, model probing, refinements
  layers.py    the picked icon's emblem cut out on a transparent background
  compose.py   pixels: gradients, masks, placing the emblem, contrast, colour-vision simulation
  text.py      Atkinson Hyperlegible Next, kerned, with a contrast guard
  icons.py     every icon and store/web image, cut from the emblem (deterministic, offline)
  sheet.py     the review sheets for the approval gates
  shots.py     store screenshots framed with their captions
  check.py     checks of everything above
"""
