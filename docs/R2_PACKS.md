# Packs on Cloudflare R2

The three paid packs download from `https://packs.epicaudiogames.com/<pack>-<version>.zip`, an R2 bucket on the
Cloudflare account that runs epicaudiogames.com. The website itself stays on Railway; `railway up` can't take the
zips (174 MB, The Werewolf's alone is 133 MB).

Both apps check a downloaded zip against its size and SHA-256 in `games/catalog.json` before installing it. So the
zips in the bucket, and the catalog in git, must come from the same run of `tools/make_pack.py`. Never remake a zip
without uploading it and committing the catalog it wrote.

Do these steps in order, from the repo root, on a machine with Python 3, ffmpeg, Node and JDK 17.

## 1. Get the repo

```
git checkout main && git pull
```

## 2. Rebuild the Alien Customs pack

A fix made the free map set absolute levels (it used to add 1 to `level`, which drifted after level 5).
`build/packs/alien-customs/` was built before that fix, so rebuild it. The builder reuses `tools/cache/`, so no
voice is paid for again; it takes about three minutes.

```
python tools/games/aliencustoms.py --levels 15 --build build/packs
```

Frootopia's and The Werewolf's builds in `build/packs/` are current.

## 3. Make the three zips

Each run writes `dist/packs/<pack>-1.zip`, `games/<game>/packs/<pack>.json`, and the pack's size and checksum in
`games/catalog.json`. The titles and descriptions are the ones already in the catalog.

```
python tools/make_pack.py frootopia --id frootopia-stories --title "Stories 2 to 5" \
  --description "The Stowaway, The Mould Moon, The Edge of Everything and The Last Star: the rest of Cosmo, Gribbo and Pip's adventure." \
  --product frootopia_stories --version 1
python tools/make_pack.py alien-customs --id alien-customs-levels --title "10 more levels" \
  --description "Levels 6 to 15, from a sports tournament to a business trip: 30 more items to talk past the officer, from marshmallows to rizz books." \
  --product alien_customs_levels --version 1
python tools/make_pack.py the-werewolf --id the-werewolf-stories --title "45 more mysteries" \
  --description "Stories 6 to 50, from The Haunted Mill to The Cursed Well: 45 more villages, each with two werewolves hiding among the villagers." \
  --product the_werewolf_stories --version 1
ls -l dist/packs/
```

`games/catalog.json` changed, and the engine fixtures hash `games/`, so regenerate them and check both engines:

```
cd android && sh ./gradlew :engine:goldens :engine:test && cd ..
swift test --package-path ios/EpicEngine
```

## 4. Create the bucket and its domain

```
npx wrangler login
npx wrangler r2 bucket create epicaudiogames-packs2
```

Then connect the domain in the Cloudflare dashboard: R2 › `epicaudiogames-packs2` › Settings › Custom Domains ›
Connect Domain › `packs.epicaudiogames.com`. (With wrangler instead: `npx wrangler r2 bucket domain add
epicaudiogames-packs2 --domain packs.epicaudiogames.com --zone-id <epicaudiogames.com's zone id>`.) Leave the
r2.dev public URL off.

## 5. Upload the zips

```
for f in dist/packs/*.zip; do
  npx wrangler r2 object put "epicaudiogames-packs2/$(basename "$f")" --file "$f" --remote \
    --content-type application/zip --cache-control "public, max-age=31536000, immutable"
done
```

Or drag the zips into the bucket in the Cloudflare dashboard: that's how version 1 went up, without giving wrangler
access to the whole account (its login asks for Workers, DNS, email and more).

A zip's name carries its version, so it never changes once uploaded. A new pack version is a new file
(`make_pack.py --version 2`), and the old one stays for the builds that still ask for it.

## 6. Check them

Each must return 200, the same SHA-256 as the catalog, and 206 for a range (iOS resumes an interrupted download):

```
for p in frootopia-stories alien-customs-levels the-werewolf-stories; do
  url="https://packs.epicaudiogames.com/$p-1.zip"
  echo "$p: $(curl -s -o /dev/null -w '%{http_code}' "$url") range $(curl -s -r 0-99 -o /dev/null -w '%{http_code}' "$url")"
  echo "  served  $(curl -s "$url" | shasum -a 256 | cut -d' ' -f1)"
  echo "  catalog $(python3 -c "import json;print(next(p2['sha256'] for g in json.load(open('games/catalog.json'))['games'] for p2 in g.get('packs',[]) if p2['id']=='$p'))")"
done
```

## 7. Point the apps at it

- iOS: in `ios/Config/Base.xcconfig`, set `EPIC_PACKS_URL = https:/$()/packs.epicaudiogames.com` (the `$()` keeps
  `//` from starting a comment). It's public, so it can live in git; `Local.xcconfig` can still override it.
- Android: in `android/gradle.properties`, add `epicPacksUrl=https://packs.epicaudiogames.com`.

The apps ask for `<url>/<pack>-<version>.zip`, so the URL has no trailing slash and no `/packs`.

## 8. Commit and push

```
git add games/catalog.json games/*/packs/*.json build/packs/alien-customs fixtures/engine \
  ios/Config/Base.xcconfig android/gradle.properties
git commit -m "Packs on R2: the zips' checksums, and the apps' pack URL"
git push
```

## Then

- Try a purchase in each app: a sandbox Apple ID in a TestFlight build, a license tester on Google Play. Each pack
  should download, install and carry on at NEXT CHAPTER.
- `dist/packs/` stays out of git (GitHub's 100 MB file limit). Keep the zips somewhere safe; the bucket holds the
  only other copy.
