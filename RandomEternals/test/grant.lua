--- RandomEternals - test/grant.lua
--
--   luajit Mods/RandomEternals/test/grant.lua
--
-- The decisions the mod makes before it touches a card, against a stubbed G: which config
-- entries are refused and why, what happens when a sticker the center forbids is asked for, and
-- the once-per-ante accounting that stands between the cash-out hook and a duplicated board.
--
-- The stub models the three things the real game does that the mod is written around:
--   * add_joker applies the edition itself, after add_to_deck, so a negative card raises the
--     joker slot limit as it lands (card.lua:409-416);
--   * set_eternal and set_perishable consult a *_compat flag on the center and silently do
--     nothing when it is false (card.lua:506-518);
--   * emplace does not enforce card_limit, so a grant can overfill the board;
--   * sell_cost is derived by set_cost from the cost and ability.extra_value, and is
--     recomputed from scratch every time anything touches the card (card.lua:369-385) -- so
--     the stub's set_cost ends by calling Grant.repin, exactly as the installed wrapper does.
-- Anything the stub gets wrong here, the mod gets wrong in the game.
local here = (arg and arg[0]) or "Mods/RandomEternals/test/grant.lua"
local prefix = here:match("^(.*)test[/\\]grant%.lua$")
local SRC = prefix and (prefix .. "src/") or "../src/"

-- ---------------------------------------------------------------------------
-- The stub board.
-- ---------------------------------------------------------------------------
local CENTERS = {
   j_joker      = { name = "Joker",      set = "Joker", rarity = 1, cost = 2,  eternal_compat = true,  perishable_compat = true },
   j_blueprint  = { name = "Blueprint",  set = "Joker", rarity = 3, cost = 10, eternal_compat = true,  perishable_compat = true },
   j_hologram   = { name = "Hologram",   set = "Joker", rarity = 2, cost = 7,  eternal_compat = true,  perishable_compat = false },
   j_ice_cream  = { name = "Ice Cream",  set = "Joker", rarity = 1, cost = 5,  eternal_compat = false, perishable_compat = true },
   -- The joker from the bug report, at its real cost (game.lua:486).
   j_troubadour = { name = "Troubadour", set = "Joker", rarity = 2, cost = 6,  eternal_compat = true,  perishable_compat = true },
   -- Not jokers: a tarot and the collection placeholder, both of which have to be refused.
   c_fool       = { name = "The Fool",   set = "Tarot" },
   j_locked     = { name = "Locked",     set = "Joker", eternal_compat = true, perishable_compat = true },
}

local events = {}

Event = function(t) return t end

G = {
   STAGE = "RUN", STAGES = { RUN = "RUN" },
   P_CENTERS = CENTERS,
   E_MANAGER = { add_event = function(_, ev) events[#events + 1] = ev end },
   jokers = { cards = {}, config = { card_limit = 5 } },
   GAME = { round = 1, round_resets = { ante = 1, blind_states = {} },
            inflation = 0, discount_percent = 0 },
}

-- functions/common_events.lua:374, reduced to what the mod depends on. The ordering is the part
-- that matters: add_to_deck happens before set_edition, which is why a negative joker pays for
-- its own slot instead of taking one.
local materialize_log = {}
function add_joker(key, edition, silent)
   local center = G.P_CENTERS[key]
   local card = {
      config = { center = center },
      ability = { set = "Joker", extra_value = 0 },
      edition = nil,
      base_cost = center.cost,
      added_to_deck = true,
   }
   -- card.lua:369-385, reduced to the joker path.
   function card:set_cost()
      self.extra_cost = 0 + G.GAME.inflation
      if self.edition then
         self.extra_cost = self.extra_cost
            + (self.edition.type == "holo" and 3 or 0)
            + (self.edition.type == "foil" and 2 or 0)
            + (self.edition.type == "polychrome" and 5 or 0)
            + (self.edition.type == "negative" and 5 or 0)
      end
      self.cost = math.max(1, math.floor((self.base_cost + self.extra_cost + 0.5)
                                         * (100 - G.GAME.discount_percent) / 100))
      if self.ability.rental then self.cost = 1 end
      self.sell_cost = math.max(1, math.floor(self.cost / 2)) + (self.ability.extra_value or 0)
      self.sell_cost_label = self.sell_cost
      -- Stands in for the Card:set_cost wrapper that Hooks installs in the real game.
      RandomEternals.Grant.repin(self)
   end
   function card:set_edition(e)
      self.edition = nil
      if not e then return end
      if e.holo then self.edition = { type = "holo" }
      elseif e.foil then self.edition = { type = "foil" }
      elseif e.polychrome then self.edition = { type = "polychrome" }
      elseif e.negative then
         self.edition = { type = "negative" }
         if self.added_to_deck then
            G.jokers.config.card_limit = G.jokers.config.card_limit + 1
         end
      end
   end
   function card:set_eternal(v)
      self.ability.eternal = nil
      if self.config.center.eternal_compat and not self.ability.perishable then
         self.ability.eternal = v
      end
   end
   function card:set_perishable()
      self.ability.perishable = nil
      if self.config.center.perishable_compat and not self.ability.eternal then
         self.ability.perishable = true
         self.ability.perish_tally = 5
      end
   end
   function card:set_rental(v) self.ability.rental = v; self:set_cost() end

   materialize_log[#materialize_log + 1] = silent and "silent" or "sound"
   if edition then card:set_edition({ [edition] = true }) end
   card:set_cost()
   -- emplace: no card_limit check, deliberately (cardarea.lua:32).
   G.jokers.cards[#G.jokers.cards + 1] = card
   card.area = G.jokers
   return card
end

-- ---------------------------------------------------------------------------
for _, f in ipairs({ "Core", "Config", "Grant" }) do
   assert(loadfile(SRC .. f .. ".lua"))()
end

local logged = {}
RandomEternals.log = function(m) logged[#logged + 1] = tostring(m) end

local failures = 0
local function check(name, got, want)
   if got ~= want then
      failures = failures + 1
      print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
   else
      print(("ok   %s = %s"):format(name, tostring(got)))
   end
end

local function logged_match(pat)
   for _, m in ipairs(logged) do if m:match(pat) then return true end end
   return false
end

-- Empties the board and the log, and drains any events the last case queued.
local function reset()
   G.jokers.cards = {}
   G.jokers.config.card_limit = 5
   G.GAME = { round = 1, round_resets = { ante = 1, blind_states = {} },
              inflation = 0, discount_percent = 0 }
   for i = #events, 1, -1 do events[i] = nil end
   for i = #logged, 1, -1 do logged[i] = nil end
   for i = #materialize_log, 1, -1 do materialize_log[i] = nil end
end

-- Runs the events a Grant.list queued, the way the game's event manager would.
local function drain()
   while #events > 0 do
      local ev = table.remove(events, 1)
      ev.func()
   end
end

print("-- a good entry becomes a card, with its edition and stickers")
reset()
check("granted", RandomEternals.Grant.one({ key = "j_blueprint", edition = "foil", eternal = true }), 1)
check("on board", #G.jokers.cards, 1)
check("edition", G.jokers.cards[1].edition.type, "foil")
check("eternal", G.jokers.cards[1].ability.eternal, true)

print("\n-- a negative joker raises the slot limit, so it costs no slot")
reset()
RandomEternals.Grant.one({ key = "j_blueprint", edition = "negative" })
check("limit raised", G.jokers.config.card_limit, 6)

print("\n-- count repeats the entry, and only the first copy makes a sound")
reset()
check("granted", RandomEternals.Grant.one({ key = "j_joker", count = 3 }), 3)
check("on board", #G.jokers.cards, 3)
check("sounds", table.concat(materialize_log, ","), "sound,silent,silent")

print("\n-- the board is allowed to overfill: five slots, seven jokers")
reset()
RandomEternals.Grant.one({ key = "j_joker", count = 7 })
check("on board", #G.jokers.cards, 7)
check("limit untouched", G.jokers.config.card_limit, 5)

print("\n-- a key that names nothing is refused without reaching add_joker")
reset()
check("granted", RandomEternals.Grant.one({ key = "j_nonesuch" }), 0)
check("logged", logged_match("no such center"), true)
reset()
check("tarot refused", RandomEternals.Grant.one({ key = "c_fool" }), 0)
check("logged", logged_match("is a Tarot, not a Joker"), true)
reset()
check("placeholder refused", RandomEternals.Grant.one({ key = "j_locked" }), 0)
check("logged", logged_match("placeholder"), true)
reset()
check("missing key refused", RandomEternals.Grant.one({}), 0)
check("non-table refused", RandomEternals.Grant.one("j_joker"), 0)

print("\n-- an unknown edition drops the whole entry rather than granting a plain joker")
reset()
check("granted", RandomEternals.Grant.one({ key = "j_joker", edition = "sparkly" }), 0)
check("on board", #G.jokers.cards, 0)
check("logged", logged_match("unknown edition"), true)

print("\n-- but a blank edition is just 'no edition'")
reset()
check("granted", RandomEternals.Grant.one({ key = "j_joker", edition = "none" }), 1)
check("no edition", G.jokers.cards[1].edition, nil)

print("\n-- a sticker the center forbids is dropped by the game, and said so in the log")
reset()
RandomEternals.Grant.one({ key = "j_ice_cream", eternal = true })
check("not eternal", G.jokers.cards[1].ability.eternal, nil)
check("logged", logged_match("eternal refused by the game"), true)
check("card still granted", #G.jokers.cards, 1)
reset()
RandomEternals.Grant.one({ key = "j_hologram", perishable = true })
check("not perishable", G.jokers.cards[1].ability.perishable, nil)
check("logged", logged_match("perishable refused by the game"), true)

print("\n-- eternal and perishable together resolve to eternal, not to whichever ran last")
reset()
RandomEternals.Grant.one({ key = "j_joker", eternal = true, perishable = true })
check("eternal", G.jokers.cards[1].ability.eternal, true)
check("not perishable", G.jokers.cards[1].ability.perishable, nil)
check("logged", logged_match("allows only one"), true)

print("\n-- but an eternal the center forbids does not take the perishable down with it")
reset()
RandomEternals.Grant.one({ key = "j_ice_cream", eternal = true, perishable = true })
check("not eternal", G.jokers.cards[1].ability.eternal, nil)
check("perishable instead", G.jokers.cards[1].ability.perishable, true)

print("\n-- rental and pinned")
reset()
RandomEternals.Grant.one({ key = "j_joker", rental = true, pinned = true })
check("rental", G.jokers.cards[1].ability.rental, true)
check("pinned", G.jokers.cards[1].pinned, true)

print("\n-- sell sets the value exactly, and survives the next set_cost")
reset()
RandomEternals.Grant.one({ key = "j_joker", sell = 25 })
check("sell cost", G.jokers.cards[1].sell_cost, 25)
G.jokers.cards[1]:set_cost()
check("still 25 after a recompute", G.jokers.cards[1].sell_cost, 25)

print("\n-- an Egg raising the value afterwards still stacks on top")
G.jokers.cards[1].ability.extra_value = G.jokers.cards[1].ability.extra_value + 3
G.jokers.cards[1]:set_cost()
check("raised", G.jokers.cards[1].sell_cost, 28)

-- The reported bug. A pinned value used to be stored as an offset into extra_value, so anything
-- that moved the cost moved the value with it -- and a cut took it below zero, which vanilla
-- sell_cost can never be and nothing in the game guards against.
print("\n-- a pinned value holds through a shop discount, which is what broke Temperance")
reset()
RandomEternals.Grant.one({ key = "j_troubadour", edition = "negative", sell = 0 })
check("pinned at 0", G.jokers.cards[1].sell_cost, 0)
G.GAME.discount_percent = 25                      -- Clearance Sale
G.jokers.cards[1]:set_cost()
check("still 0 after Clearance Sale", G.jokers.cards[1].sell_cost, 0)
G.GAME.discount_percent = 50                      -- Liquidation
G.jokers.cards[1]:set_cost()
check("still 0 after Liquidation", G.jokers.cards[1].sell_cost, 0)
G.GAME.discount_percent = 0
G.GAME.inflation = 4
G.jokers.cards[1]:set_cost()
check("still 0 under inflation", G.jokers.cards[1].sell_cost, 0)
G.GAME.inflation = 0

print("\n-- a card the config never pinned keeps tracking its cost, exactly as vanilla does")
reset()
RandomEternals.Grant.one({ key = "j_blueprint" })
local natural = G.jokers.cards[1].sell_cost
G.GAME.discount_percent = 50
G.jokers.cards[1]:set_cost()
check("moved with the discount", G.jokers.cards[1].sell_cost < natural, true)
check("never negative", G.jokers.cards[1].sell_cost >= 0, true)
G.GAME.discount_percent = 0

print("\n-- the reported board: five pinned-0 jokers no longer cancel the rest")
reset()
G.GAME.discount_percent = 25
RandomEternals.Grant.one({ key = "j_troubadour", edition = "negative", sell = 0, count = 5 })
for _, k in ipairs({ "j_joker", "j_joker", "j_joker", "j_hologram" }) do
   RandomEternals.Grant.one({ key = k })
end
local temperance = 0                              -- card.lua:4256-4262
for _, c in ipairs(G.jokers.cards) do temperance = temperance + c.sell_cost end
check("Temperance sees the other jokers", temperance > 0, true)
check("no card is worth less than nothing", (function()
   for _, c in ipairs(G.jokers.cards) do if c.sell_cost < 0 then return false end end
   return true
end)(), true)
G.GAME.discount_percent = 0

print("\n-- migrate repairs a card granted before values were pinned")
reset()
G.GAME.discount_percent = 25                      -- the state the reported save was in
RandomEternals.Grant.one({ key = "j_joker" })           -- a vanilla card, must be left alone
local vanilla = G.jokers.cards[1].sell_cost
RandomEternals.Grant.one({ key = "j_troubadour", edition = "negative" })
local legacy = G.jokers.cards[2]
legacy.ability.extra_value = -5                   -- what the old offset left behind
legacy:set_cost()
check("legacy card is negative", legacy.sell_cost, -1)
RandomEternals.Grant.migrate()
check("repaired to 0", legacy.sell_cost, 0)
check("now pinned", legacy.ability.randometernals_sell, 0)
check("offset cleared", legacy.ability.extra_value, 0)
check("vanilla card untouched", G.jokers.cards[1].sell_cost, vanilla)
check("vanilla card not pinned", G.jokers.cards[1].ability.randometernals_sell, nil)
check("logged", logged_match("repaired a stale sell value"), true)

print("\n-- and a repaired card stays repaired through the next discount")
G.GAME.discount_percent = 50                      -- Liquidation, on top of Clearance Sale
legacy:set_cost()
check("still 0", legacy.sell_cost, 0)
G.GAME.discount_percent = 0

print("\n-- the pin lands on the target whatever else moved the card's price")
reset()
RandomEternals.Grant.one({ key = "j_blueprint", edition = "negative", sell = 4 })
check("edition did not shift it", G.jokers.cards[1].sell_cost, 4)
reset()
-- Rental forces cost to 1, so the natural value drops to 1 -- the target has to be measured
-- after that, not before.
RandomEternals.Grant.one({ key = "j_blueprint", rental = true, sell = 9 })
check("rental did not shift it", G.jokers.cards[1].sell_cost, 9)
check("rental still set", G.jokers.cards[1].ability.rental, true)

print("\n-- sell = 0 is allowed; a negative one is clamped and logged")
reset()
RandomEternals.Grant.one({ key = "j_joker", sell = 0 })
check("zero", G.jokers.cards[1].sell_cost, 0)
reset()
RandomEternals.Grant.one({ key = "j_joker", sell = -5 })
check("clamped", G.jokers.cards[1].sell_cost, 0)
check("logged", logged_match("below 0"), true)

print("\n-- a non-numeric sell leaves the card at its natural value")
reset()
RandomEternals.Grant.one({ key = "j_blueprint", sell = "lots" })
check("natural value", G.jokers.cards[1].sell_cost, 5)
check("logged", logged_match("not a number"), true)

print("\n-- with no sell field the card keeps whatever the game gave it")
reset()
RandomEternals.Grant.one({ key = "j_joker" })
check("natural value", G.jokers.cards[1].sell_cost, 1)

print("\n-- a list is granted one queued event per entry")
reset()
RandomEternals.Grant.list({ { key = "j_joker" }, { key = "j_blueprint" } }, "test")
check("queued", #events, 2)
check("nothing yet", #G.jokers.cards, 0)
drain()
check("on board", #G.jokers.cards, 2)

print("\n-- a malformed list is refused whole rather than iterated into nothing")
reset()
RandomEternals.Grant.list({ key = "j_joker" }, "test")
check("queued", #events, 0)
check("logged", logged_match("not an array"), true)

print("\n-- disabled grants nothing")
reset()
RandomEternals.config.enabled = false
RandomEternals.Grant.list({ { key = "j_joker" } }, "test")
check("queued", #events, 0)
RandomEternals.config.enabled = true

print("\n-- per-round grants once per round, and again on the next round")
reset()
RandomEternals.config.per_round = { { key = "j_joker" } }
RandomEternals.Grant.for_round(1)
RandomEternals.Grant.for_round(1)
drain()
check("granted once", #G.jokers.cards, 1)
RandomEternals.Grant.for_round(2)
drain()
check("next round grants", #G.jokers.cards, 2)

print("\n-- the per-round marker is its own, so a boss cash-out grants both lists")
reset()
RandomEternals.config.per_round = { { key = "j_joker" } }
RandomEternals.config.per_ante = { { key = "j_blueprint" } }
RandomEternals.config.per_ante_overrides = {}
RandomEternals.Grant.for_round(3)          -- what a boss cash-out does, in order
RandomEternals.Grant.for_ante(1)
drain()
check("both granted", #G.jokers.cards, 2)
check("round list first", G.jokers.cards[1].config.center.name, "Joker")
check("then the ante list", G.jokers.cards[2].config.center.name, "Blueprint")

print("\n-- the two markers are separate, and both live on G.GAME")
check("round marker", G.GAME.randometernals_granted_round[3], true)
check("ante marker", G.GAME.randometernals_granted[1], true)

print("\n-- an empty per_round list queues nothing")
reset()
RandomEternals.config.per_round = {}
RandomEternals.Grant.for_round(9)
check("queued", #events, 0)

print("\n-- per-ante: the override wins, and an empty override means nothing this ante")
reset()
RandomEternals.config.per_ante = { { key = "j_joker" } }
RandomEternals.config.per_ante_overrides = { [3] = { { key = "j_blueprint" } }, [8] = {} }
local list = RandomEternals.Grant.list_for_ante(1)
check("ante 1 falls back", list[1].key, "j_joker")
list = RandomEternals.Grant.list_for_ante(3)
check("ante 3 overridden", list[1].key, "j_blueprint")
list = RandomEternals.Grant.list_for_ante(8)
check("ante 8 suppressed", #list, 0)

print("\n-- per-ante grants once per ante, however many times the cash-out hook fires")
reset()
RandomEternals.Grant.for_ante(1)
RandomEternals.Grant.for_ante(1)
RandomEternals.Grant.for_ante(1)
drain()
check("granted once", #G.jokers.cards, 1)
RandomEternals.Grant.for_ante(2)
drain()
check("next ante grants", #G.jokers.cards, 2)

print("\n-- the marker lives on G.GAME, so it survives a save and load")
check("marker recorded", G.GAME.randometernals_granted[1], true)
local saved = G.GAME
reset()
G.GAME = saved                      -- what save_run/load restores (misc_functions.lua:1473)
RandomEternals.Grant.for_ante(1)
drain()
check("no regrant after load", #G.jokers.cards, 0)

print("\n-- the command's force flag ignores the marker on purpose")
RandomEternals.Grant.for_ante(1, true)
drain()
check("forced grant", #G.jokers.cards, 1)

print("\n-- an ante with no list queues nothing")
reset()
RandomEternals.config.per_ante = {}
RandomEternals.Grant.for_ante(4)
check("queued", #events, 0)

print("")
if failures > 0 then
   print(("%d failure(s)"):format(failures))
   os.exit(1)
end
print("all ok")
