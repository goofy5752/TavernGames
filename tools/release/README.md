# Releases

A version goes out by itself once it reaches `master`. The workflow is `.github/workflows/release.yml`.

1. In a branch, run `python tools/release/release.py bump 1.0.2`. It changes the version in
   `TavernGames.toc`, `core/Const.lua` and README's "**Version …**" line. It also turns
   CHANGELOG's `## Unreleased` heading into `## 1.0.2 (today)`.
2. Open a PR and merge it.
3. The push to `master` finds a version that has no tag yet. The workflow then:
   - runs the tests;
   - builds `TavernGames-1.0.2.zip`, with the addon inside a `TavernGames/` folder;
   - creates the tag `v1.0.2` and its GitHub release (the install note followed by the CHANGELOG section);
   - uploads the same zip to CurseForge as a release.

A push that leaves the version unchanged finds the tag already there and does nothing.

## CurseForge

- **Project:** the toc's `## X-Curse-Project-ID`.
- **Key:** the repository secret `CF_API_KEY`, an API token from <https://authors.curseforge.com/account/api-tokens>.
  Without it, CurseForge is skipped and the GitHub release still goes out.
- **Game version:** taken from the toc's Interface (16001 is 1.60.1), among CurseForge's WoW Forever versions.
  If CurseForge names it differently, set the repository variable `CF_GAME_VERSION`.
  A failed upload lists the names CurseForge has.
- **Upload again:** if a CurseForge upload failed after its GitHub release, run the workflow by hand
  (Actions → release → Run workflow) with "curseforge only" ticked.

## By hand

- `release.py zip 1.0.2 dist` builds the same zip locally.
- `release.py body 1.0.2` prints the release text.
