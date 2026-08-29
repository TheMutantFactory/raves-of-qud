extends Node

## SINGLE SOURCE OF TRUTH for the project's name and the fixed external facts around
## it (the base game, store links, legal placeholders). Registered as the "Brand"
## autoload (see project.godot) so every script refers to `Brand.GAME_NAME` instead
## of hardcoding the string — the name may change, and when it does this is the ONE
## place to edit.
##
## Anything marked with «guillemets» is a deliberate PLACEHOLDER awaiting a real
## value (exact legal entity, org name, donation link). They render literally so a
## placeholder is never mistaken for a finished string.

# ── the project ──────────────────────────────────────────────────────────────
## THE NAME, and the only place it lives. Renamed from "Raves of Qud" to "Raves of Mud" on
## 2026-08-25: the old name leaned on Freehold's trademark to say what the project is, and it
## does not need to — the description does that job ("a Caves of Qud modpack…") without putting
## someone else's mark in the product name.
##
## WHAT DELIBERATELY DID **NOT** CHANGE WITH IT, and must not be "fixed" later:
##   * the support directory, still ~/Library/Application Support/RavesOfQud — it holds the
##     player's own custom art, settings, colour edits, build library and statues. A rename
##     orphans all of it silently, which is a data loss dressed as tidiness.
##   * the mod folder RavesOfQudBridge, for the same reason one level over: Qud loads what is
##     deployed there, and renaming leaves the old copy behind to load instead.
##   * the bundle identifier com.dazzlingdukeoflazers.ravesofqud — macOS treats a changed id as
##     a different application (permissions, window state, crash-report identity all reset).
##   * the repository and its remote.
## Those are STORAGE KEYS and IDENTIFIERS, not the name. The rule: anything a player reads uses
## GAME_NAME; anything a machine keys on stays put.
const GAME_NAME := "Raves of Mud"
## The old name, kept for one job only: telling a returning player that the thing they installed
## and the thing they are running are the same project.
const FORMER_GAME_NAME := "Raves of Qud"
## Shown in the 1:1 title version corner under Qud's build — and, since 2026-08-10, stamped into
## every feedback report as `app_version`. A report you cannot pin to an exact build is close to
## worthless, so this has to be bumped WITH the tag, not after it.
const RAVES_VERSION := "0.8.2"
const GAME_TAGLINE := "a 3D viewer for Caves of Qud"   # the SEO link: says what it is without taking the mark
## Spelled "Mutant Factory" — two words, matching mutantfactory.net and the 13 uses on the site.
## The GitHub org is `TheMutantFactory` -- `MutantFactory` and `mutantfactory` are both taken by
## dormant accounts, and GitHub also refuses `mutant-factory` for differing from one only by a
## hyphen. That is a HANDLE, not the name: display text uses this constant, never the handle.
const ORG_NAME := "Mutant Factory"
const LICENSE := "MIT"

## The base Caves of Qud release this 1:1 build was reconstructed against — shown on the
## title screen's version corner in 1:1 mode (in place of Raves' own name/licence), matching
## Qud. Reference build (measured off a 1.0.5 title capture); TODO: source dynamically from the
## mod's title export so it tracks the player's actual install instead of being pinned here.
const QUD_VERSION := "1.0.5"
const QUD_BUILD := "2.0.211.50"

# ── the base game it renders ─────────────────────────────────────────────────
const BASE_GAME := "Caves of Qud"
const BASE_GAME_RIGHTS_HOLDER := "Freehold Games"   # confirm the exact legal suffix (LLC?) for formal use
const STEAM_APPID := "333640"

# ── links (open in the user's browser) ───────────────────────────────────────
const URL_STEAM := "https://store.steampowered.com/app/333640/Caves_of_Qud/"
const URL_GOG := "https://www.gog.com/game/caves_of_qud"
const URL_ELSEWHERE := "https://www.cavesofqud.com/"
const URL_STEAM_RUN := "steam://rungameid/333640"   # launches an installed copy
const URL_DONATE := "«donation link for Raves of Mud»"   # placeholder
## The project's own source. A public repo under an open licence should be reachable FROM the
## credits that claim it — a licence nobody can go and read is a claim, not a licence.
const URL_REPO := "https://github.com/TheMutantFactory/raves-of-qud"
## SIL's own text, for the two fonts that ship under it. Linked rather than paraphrased.
const URL_OFL := "https://openfontlicense.org/"

## Where in-game feedback is submitted (feedback-service; see its schema/envelope.v1.md).
## A CUSTOM DOMAIN on purpose -- this was feedback-service.daniel-dee.workers.dev, and a personal
## subdomain compiled into a shipped client is not something you can take back.
## EMPTY DISABLES SUBMISSION, and the outbox still accumulates: that is the correct behaviour for a
## build that ships before the service exists, or for anyone forking this who has no server.
const FEEDBACK_ENDPOINT := "https://feedback.mutantfactory.net"

## Convenience: the window/title string. Kept here so a rename only touches Brand.
static func title() -> String:
	return GAME_NAME

## THE CREDITS TREE — who made what, in two branches.
##
## Daniel: "It's a tree that contains a node with Freehold Games images and credit and another node
## that displays open images and credits."
##
## The split is the one that matters legally and is the one a reader needs: assets that belong to
## someone else and are only RENDERED from the copy you own, against assets that ship in this
## repository under an open licence. Everything Raves draws falls in one or the other.
##
## Lives here because Brand.gd is where the project's fixed external facts live, and a credit is
## exactly that — a fact about someone else that a rename or a new screen must not be able to drift
## from. `tile` names a Qud sprite to show beside the row (resolved at runtime from the player's own
## export, so nothing is redistributed); `art` is a res:// path for art this repo does ship.
static func credit_branches() -> Array:
	return [
		{
			"head": "%s — %s" % [BASE_GAME, BASE_GAME_RIGHTS_HOLDER],
			"note": ("Every tile, glyph and colour %s draws is %s's, read live from the copy of "
				+ "%s you own. None of it is contained in or redistributed by this project.") % [
					GAME_NAME, BASE_GAME_RIGHTS_HOLDER, BASE_GAME],
			"url": URL_ELSEWHERE,
			"entries": [
				{"name": "Creature, item and terrain tiles", "tile": "Creatures/sw_farmer.bmp",
					"note": "Rendered from your install at runtime"},
				{"name": "World-map terrain art", "tile": "Terrain/sw_joppa.bmp",
					"note": "Used to mark places you have found"},
				{"name": "UI frames and category icons", "tile": "Items/sw_book_3.bmp",
					"note": "polat-category-frame and FilterBarCategoryButton art"},
				{"name": "The 18-colour palette and CP437 glyphs", "tile": "",
					"note": "Read from your install; see docs/decisions"},
			],
		},
		{
			"head": "Open assets shipped with %s" % GAME_NAME,
			"note": ("These are the only assets contained in this repository. Each is used under "
				+ "an open licence, and each licence text ships beside it."),
			"entries": [
				{"name": "Look", "art": "res://art/look.svg",
					"note": ("The interaction cursor. Icon 2400060 from Noun Project — "
						+ "«creator name» / «licence: free-tier credit or royalty-free»"),
					"url": "https://thenounproject.com/icon/2400060/"},
				{"name": "Source Code Pro", "art": "",
					"note": "© 2023 Adobe, Reserved Font Name 'Source' — SIL Open Font License 1.1",
					"url": "https://github.com/adobe-fonts/source-code-pro"},
				{"name": "Atkinson Hyperlegible", "art": "",
					"note": ("© 2020 Braille Institute of America, Inc. — "
						+ "SIL Open Font License 1.1"),
					"url": "https://www.brailleinstitute.org/freefont/"},
				{"name": "SIL Open Font License 1.1", "art": "",
					"note": "The licence both fonts above ship under",
					"url": URL_OFL},
				{"name": "%s itself" % GAME_NAME, "art": "",
					"note": "%s, by %s — see the licence panel on the title screen" % [LICENSE, ORG_NAME],
					"url": URL_REPO},
			],
		},
	]

## The right-hand-panel legal / attribution copy. Best-faith, plain-language summary —
## NOT legal advice. Assembled from the constants so a rename or a confirmed rights
## holder flows through automatically. Returned as an Array of {head, body} sections
## so the menu can style headings distinctly from body text.
static func attribution_sections() -> Array:
	return [
		{
			"head": "%s artwork & content" % BASE_GAME,
			"body": ("All %s artwork, tiles, text, audio, and game content are the "
				+ "property of %s and are used here only to render a copy the player "
				+ "already owns. No such assets are redistributed by %s.") % [
					BASE_GAME, BASE_GAME_RIGHTS_HOLDER, GAME_NAME],
		},
		{
			"head": "No AI-generated assets",
			"body": ("No artwork or content in %s was created with generative AI. "
				+ "%s renders the original assets from your installed copy of %s.") % [
					GAME_NAME, GAME_NAME, BASE_GAME],
		},
		{
			"head": "%s is %s-licensed" % [GAME_NAME, LICENSE],
			"body": ("%s itself is released under the %s license: anyone may use it for "
				+ "anything — as-is or refactored, free or commercial.") % [GAME_NAME, LICENSE],
		},
		{
			"head": "The license does NOT extend to %s" % BASE_GAME,
			"body": ("The %s license covers only %s's own code. It grants no rights to "
				+ "%s's artwork, content, or licenses. Anyone using %s has a fiduciary "
				+ "due-diligence duty to ensure NO %s assets are released or distributed.") % [
					LICENSE, GAME_NAME, BASE_GAME, GAME_NAME, BASE_GAME],
		},
		{
			"head": "Requires a purchased copy",
			"body": ("%s requires a purchased and downloaded copy of %s and will not "
				+ "run without it.") % [GAME_NAME, BASE_GAME],
		},
	]
