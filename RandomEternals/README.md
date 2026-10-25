# RandomEternals

Start a run with the jokers you name, and gain more at the end of every ante.

Lovely only — Steamodded is not needed, and is not installed here.

Everything is driven by one file: **`src/Config.lua`**. Edit it and the next new run begins with
the board you wrote down — no restart. The file is read off the disk again every time a run
begins, so the game only has to be relaunched when the mod's own code changes.

---

## What it does

Three independent features, any of which can be left empty:

- **`start`** — granted once, the moment a new run begins. Not on Continue and not on a save
  load, so reopening a run never stacks a second copy.
- **`per_round`** — granted at every cash-out: once per round, so three times an ante, or twice
  when a blind was skipped (a skipped blind never reaches a cash-out).
- **`per_ante`** — granted at the cash-out after each boss blind: once per ante, as the ante
  ends. Nothing is granted after the small or big blind. A per-ante override table can replace
  that list for a specific ante, or suppress it entirely.

`per_round` and `per_ante` are independent. A boss cash-out fires both, the round list first.

All 150 jokers are supported, with any of the four editions (foil, holographic, polychrome,
negative) and any of the stickers the game allows on them (eternal, perishable, rental, plus
pinning).

## Random Eternals Challenge

The New Run screen gains a **Random Eternals Challenge** toggle below the deck and stake
selection (in both Steamodded's paged run select and the vanilla one). Ticking it shows a count
cycle, default 5. Starting a new run with it ticked draws that many distinct jokers, uniformly,
from every joker that can be eternal, and writes them as eternal entries into `start` in
`src/Config.lua`, between the `>>> random eternals` / `<<< random eternals` markers. The file is
then reloaded as usual, so the draw is what the run starts with.

The last option in the count cycle is **1 per ante**: one random eternal to start, then one more
at the end of each ante 1 through 39, written as `per_ante_overrides` entries between their own
`>>> random eternals per ante` markers. All 40 are distinct.

Starting a new run with it unticked comments the last draw out instead. Challenge runs never
draw. Only the lines between the markers are touched. The toggle and count last for the session
and are not saved across launches.

## Installing

Drop the folder into `Mods/`. There is nothing to configure outside `src/Config.lua`.

```
Mods/RandomEternals/
  lovely/randometernals.toml  Lovely manifest, priority 122
  src/Core.lua                namespace, logging, validation
  src/Config.lua              the file you edit
  src/Reload.lua              re-reads that file at the start of each new run
  src/Grant.lua               config entry -> card on the board
  src/Eternals.lua            random eternals draw, written into Config.lua
  src/Hooks.lua               Game.start_run and G.FUNCS.cash_out wrappers
  src/Menu.lua                the New Run screen toggle
  src/Command.lua             optional DebugPlus commands
  src/Init.lua                deferred install
  test/grant.lua              offline test harness
  test/reload.lua             offline tests for the config reload
```

## Config

```lua
RandomEternals.config = {
   enabled = true,

   start = {
      { key = "j_blueprint",  edition = "negative" },
      { key = "j_brainstorm", edition = "foil", eternal = true },
      { key = "j_egg",        sell = 20 },
   },

   per_round = {
      { key = "j_joker" },
   },

   per_ante = {
      { key = "j_hologram" },
   },

   per_ante_overrides = {
      [3] = { { key = "j_dna", edition = "polychrome" } },
      [8] = {},
   },

   log_grants = true,
}
```

### Entry fields

| field | values | meaning |
|---|---|---|
| `key` | `"j_..."` | **Required.** The joker's center id. Full list below. |
| `edition` | `"foil"`, `"holo"`, `"polychrome"`, `"negative"` | Omit, or use `"none"`/`"base"`, for a plain joker. Only one — the game cannot hold two. |
| `eternal` | `true` | Unsellable, undestroyable. |
| `perishable` | `true` | Debuffed after 5 rounds. Cannot be combined with `eternal`. |
| `rental` | `true` | Costs $3 at the end of every round. |
| `pinned` | `true` | Pinned to the left of the joker row. |
| `sell` | number | Pins the joker's sell value, in dollars. Omit to leave the value alone entirely. `0` is allowed; negatives are clamped to `0`. |
| `count` | number | How many copies of this entry. Default 1. |

### Top-level fields

- **`enabled`** — set `false` to keep the mod loaded but grant nothing, without emptying the
  lists.
- **`start`** — the run-start list. `{}` for none.
- **`per_round`** — granted at every cash-out. `{}` for none.
- **`per_ante`** — the default end-of-ante list. `{}` for none.
- **`per_ante_overrides`** — keyed by the ante that was just **completed**, so `[1]` fires at the
  first boss cash-out (when ante 1 is over and ante 2 is next). An entry of `{}` means "nothing
  at the end of that ante"; an ante with no entry falls back to `per_ante`.
- **`log_grants`** — whether each grant writes a line to the log. Rejected entries and refused
  stickers are logged either way.

## Behaviour worth knowing

**Joker slots are not enforced.** A grant goes onto the board whether or not there is room, so a
five-slot run can end up holding seven jokers. This is deliberate: the config is a statement of
what you want on the board, and `CardArea:emplace` has no limit check to begin with — the game
enforces slots at the shop, not at the card area. Negative-edition entries cost no slot at all,
since a negative card raises the limit as it lands.

**Some stickers are impossible on some jokers.** The game's own setters consult an
`eternal_compat` / `perishable_compat` flag on each joker and silently do nothing when it is
false — eleven jokers can never be eternal, eighteen can never be perishable. RandomEternals asks anyway,
then reads the field back and writes a line to the log saying it was refused, so a config that
is not doing what it says says so. The joker is still granted, just without that sticker. The
table below marks every one of these.

**Eternal and perishable are mutually exclusive.** Asking for both keeps eternal and logs the
other as dropped, rather than leaving the outcome to whichever setter happened to run last. The
one exception is a joker that cannot be eternal at all: there the perishable is applied, since
refusing it on the strength of a sticker that never landed would leave the card with neither.

**`sell` pins the value; everything else is left alone.** `sell_cost` is not a field the game
stores, it is one it derives — `max(1, floor(cost/2)) + ability.extra_value` (`card.lua:382`) —
recomputed from scratch every time anything touches the card. A card the config pinned keeps its
target stored in `ability.randometernals_sell` and has it re-applied after every recompute, so shop
discounts, inflation, rentals and save/load cannot move it. An Egg or Gift Card still raises it
from the pin, because those add to `extra_value` and the pin leaves that channel free. A card
with no `sell` in its entry is never touched: its value tracks its cost exactly as vanilla.

> **Why it is a pin and not an offset.** It used to be an offset written into `extra_value`,
> which agreed with the target only while the cost stayed put. Buying Clearance Sale
> (`discount_percent = 25`) cut a negative Troubadour's cost from 11 to 8 and its natural value
> from 5 to 4, so a card pinned at $0 through an offset of −5 became worth **−$1**. Vanilla
> `sell_cost` can never be negative — the only vanilla writers of `extra_value`, Egg
> (`card.lua:3021`) and Gift Card (`card.lua:3031`), add to it — so nothing in the game guards
> against one. Temperance (`card.lua:4260`) simply sums `sell_cost` across the jokers with no
> lower clamp, so five cards at −$1 cancelled four real jokers to exactly $0. Swashbuckler
> (`card.lua:4336`), Ceremonial Dagger (`card.lua:2598`) and selling itself (`card.lua:1617`)
> read the same field and would have gone the same way.
>
> Runs that granted cards before the fix are repaired on load: a joker carrying a negative
> `extra_value` — a signature only this mod could leave — is re-pinned at `max(0, sell_cost)`
> and logged. That restores a `sell = 0` card exactly; a card pinned at some other number lands
> at whatever it had drifted to.

**A bad key is never fatal.** The game's `add_joker` would take the run down with a nil index on
a typo, so every key is checked against `G.P_CENTERS` first. A key that names nothing, or names a
tarot, is skipped with a line in the log naming it.

**Granted jokers are ordinary cards.** They are created by the same `add_joker` that challenge
decks use for their starting jokers, so unlocks, scoring and saving all behave as they do in a
challenge run.

## Interaction with the other mods here

**RouteRec** — jokers appearing at a boss cash-out are cards a recording never saw. Recording a
route with RandomEternals on and replaying it with RandomEternals off (or the reverse) will diverge at the
first grant. Use one or the other for a given run.

**Handy** — Handy's insta-cash-out makes `G.FUNCS.cash_out` fire twice for one cash-out, once as
a no-op. RandomEternals grants once regardless, using markers stored on `G.GAME`; because `save_run`
serialises `G.GAME` wholesale, those markers also survive closing and reopening the run.

The per-round marker is keyed on `G.GAME.round`, which the game advances when a blind is
*selected*, not when it ends — so at cash-out time it already names the round that just
finished, and it never repeats for the life of a run. That matters because the obvious
alternative, the ante plus the blind, *is* reused when a Hieroglyph walks the ante backwards.

## Logging

Everything the mod says goes through `print`, which lands in
`Mods/lovely/log/lovely-<date>.log` prefixed `INFO - [G] `, and in the DebugPlus console. Look
for `[RandomEternals]`.

## DebugPlus commands (optional)

Only registered when DebugPlus is loaded. They exist for checking a config without playing to a
boss blind:

- `randometernals_reload` — re-read `src/Config.lua` from disk now. Happens on its own at the start of
  every new run; the command is for picking up an edit mid-run, or without starting one. A file
  that will not load leaves the current config in place and says why.
- `randometernals_start` — grant the `start` list onto the current board now.
- `randometernals_round [n]` — grant the `per_round` list. Defaults to the current round. Ignores the
  once-per-round marker.
- `randometernals_ante [n]` — grant what the end of ante `n` would grant (the override if there is one,
  otherwise `per_ante`). Ignores the once-per-ante marker, so it can be run repeatedly.

## Tests

```
cd Mods/RandomEternals/test && luajit grant.lua && luajit reload.lua
```

Runs the grant logic against a stubbed `G` that models the three game behaviours the mod is
written around: `add_joker`'s ordering (which is what makes a negative joker pay for its own
slot), the `*_compat` flags silently refusing stickers, and `emplace` not enforcing `card_limit`.

---

## Every joker key

The game's own ids carry a few oddities — `j_gluttenous_joker` (Gluttonous), `j_selzer`
(Seltzer), `j_ring_master` (Showman), `j_trousers` (Spare Trousers), `j_flash` (Flash Card),
`j_wee` (Wee Joker). Use the key, not the printed name.

### Common (61)

| key | name | notes |
|---|---|---|
| `j_joker` | Joker |  |
| `j_greedy_joker` | Greedy Joker |  |
| `j_lusty_joker` | Lusty Joker |  |
| `j_wrathful_joker` | Wrathful Joker |  |
| `j_gluttenous_joker` | Gluttonous Joker |  |
| `j_jolly` | Jolly Joker |  |
| `j_zany` | Zany Joker |  |
| `j_mad` | Mad Joker |  |
| `j_crazy` | Crazy Joker |  |
| `j_droll` | Droll Joker |  |
| `j_sly` | Sly Joker |  |
| `j_wily` | Wily Joker |  |
| `j_clever` | Clever Joker |  |
| `j_devious` | Devious Joker |  |
| `j_crafty` | Crafty Joker |  |
| `j_half` | Half Joker |  |
| `j_credit_card` | Credit Card |  |
| `j_banner` | Banner |  |
| `j_mystic_summit` | Mystic Summit |  |
| `j_8_ball` | 8 Ball |  |
| `j_misprint` | Misprint |  |
| `j_raised_fist` | Raised Fist |  |
| `j_chaos` | Chaos the Clown |  |
| `j_scary_face` | Scary Face |  |
| `j_abstract` | Abstract Joker |  |
| `j_delayed_grat` | Delayed Gratification |  |
| `j_gros_michel` | Gros Michel | cannot be eternal |
| `j_even_steven` | Even Steven |  |
| `j_odd_todd` | Odd Todd |  |
| `j_scholar` | Scholar |  |
| `j_business` | Business Card |  |
| `j_supernova` | Supernova |  |
| `j_ride_the_bus` | Ride the Bus | cannot be perishable |
| `j_egg` | Egg |  |
| `j_runner` | Runner | cannot be perishable |
| `j_ice_cream` | Ice Cream | cannot be eternal |
| `j_splash` | Splash |  |
| `j_blue_joker` | Blue Joker |  |
| `j_faceless` | Faceless Joker |  |
| `j_green_joker` | Green Joker | cannot be perishable |
| `j_superposition` | Superposition |  |
| `j_todo_list` | To Do List |  |
| `j_cavendish` | Cavendish | cannot be eternal |
| `j_red_card` | Red Card | cannot be perishable |
| `j_square` | Square Joker | cannot be perishable |
| `j_riff_raff` | Riff-raff |  |
| `j_photograph` | Photograph |  |
| `j_reserved_parking` | Reserved Parking |  |
| `j_mail` | Mail-In Rebate |  |
| `j_hallucination` | Hallucination |  |
| `j_fortune_teller` | Fortune Teller |  |
| `j_juggler` | Juggler |  |
| `j_drunkard` | Drunkard |  |
| `j_golden` | Golden Joker |  |
| `j_popcorn` | Popcorn | cannot be eternal |
| `j_walkie_talkie` | Walkie Talkie |  |
| `j_smiley` | Smiley Face |  |
| `j_ticket` | Golden Ticket |  |
| `j_swashbuckler` | Swashbuckler |  |
| `j_hanging_chad` | Hanging Chad |  |
| `j_shoot_the_moon` | Shoot the Moon |  |

### Uncommon (64)

| key | name | notes |
|---|---|---|
| `j_stencil` | Joker Stencil |  |
| `j_four_fingers` | Four Fingers |  |
| `j_mime` | Mime |  |
| `j_ceremonial` | Ceremonial Dagger | cannot be perishable |
| `j_marble` | Marble Joker |  |
| `j_loyalty_card` | Loyalty Card |  |
| `j_dusk` | Dusk |  |
| `j_fibonacci` | Fibonacci |  |
| `j_steel_joker` | Steel Joker |  |
| `j_hack` | Hack |  |
| `j_pareidolia` | Pareidolia |  |
| `j_space` | Space Joker |  |
| `j_burglar` | Burglar |  |
| `j_blackboard` | Blackboard |  |
| `j_sixth_sense` | Sixth Sense |  |
| `j_constellation` | Constellation | cannot be perishable |
| `j_hiker` | Hiker |  |
| `j_card_sharp` | Card Sharp |  |
| `j_madness` | Madness | cannot be perishable |
| `j_seance` | Seance |  |
| `j_vampire` | Vampire | cannot be perishable |
| `j_shortcut` | Shortcut |  |
| `j_hologram` | Hologram | cannot be perishable |
| `j_cloud_9` | Cloud 9 |  |
| `j_rocket` | Rocket | cannot be perishable |
| `j_midas_mask` | Midas Mask |  |
| `j_luchador` | Luchador | cannot be eternal |
| `j_gift` | Gift Card |  |
| `j_turtle_bean` | Turtle Bean | cannot be eternal |
| `j_erosion` | Erosion |  |
| `j_to_the_moon` | To the Moon |  |
| `j_stone` | Stone Joker |  |
| `j_lucky_cat` | Lucky Cat | cannot be perishable |
| `j_bull` | Bull |  |
| `j_diet_cola` | Diet Cola | cannot be eternal |
| `j_trading` | Trading Card |  |
| `j_flash` | Flash Card | cannot be perishable |
| `j_trousers` | Spare Trousers | cannot be perishable |
| `j_ramen` | Ramen | cannot be eternal |
| `j_selzer` | Seltzer | cannot be eternal |
| `j_castle` | Castle | cannot be perishable |
| `j_mr_bones` | Mr. Bones | cannot be eternal |
| `j_acrobat` | Acrobat |  |
| `j_sock_and_buskin` | Sock and Buskin |  |
| `j_troubadour` | Troubadour |  |
| `j_certificate` | Certificate |  |
| `j_smeared` | Smeared Joker |  |
| `j_throwback` | Throwback |  |
| `j_rough_gem` | Rough Gem |  |
| `j_bloodstone` | Bloodstone |  |
| `j_arrowhead` | Arrowhead |  |
| `j_onyx_agate` | Onyx Agate |  |
| `j_glass` | Glass Joker | cannot be perishable |
| `j_ring_master` | Showman |  |
| `j_flower_pot` | Flower Pot |  |
| `j_merry_andy` | Merry Andy |  |
| `j_oops` | Oops! All 6s |  |
| `j_idol` | The Idol |  |
| `j_seeing_double` | Seeing Double |  |
| `j_matador` | Matador |  |
| `j_satellite` | Satellite |  |
| `j_cartomancer` | Cartomancer |  |
| `j_astronomer` | Astronomer |  |
| `j_bootstraps` | Bootstraps |  |

### Rare (20)

| key | name | notes |
|---|---|---|
| `j_dna` | DNA |  |
| `j_vagabond` | Vagabond |  |
| `j_baron` | Baron |  |
| `j_obelisk` | Obelisk | cannot be perishable |
| `j_baseball` | Baseball Card |  |
| `j_ancient` | Ancient Joker |  |
| `j_campfire` | Campfire |  |
| `j_blueprint` | Blueprint |  |
| `j_wee` | Wee Joker | cannot be perishable |
| `j_hit_the_road` | Hit the Road |  |
| `j_duo` | The Duo |  |
| `j_trio` | The Trio |  |
| `j_family` | The Family |  |
| `j_order` | The Order |  |
| `j_tribe` | The Tribe |  |
| `j_stuntman` | Stuntman |  |
| `j_invisible` | Invisible Joker | cannot be eternal |
| `j_brainstorm` | Brainstorm |  |
| `j_drivers_license` | Driver's License |  |
| `j_burnt` | Burnt Joker |  |

### Legendary (5)

| key | name | notes |
|---|---|---|
| `j_caino` | Caino |  |
| `j_triboulet` | Triboulet |  |
| `j_yorick` | Yorick |  |
| `j_chicot` | Chicot |  |
| `j_perkeo` | Perkeo |  |
