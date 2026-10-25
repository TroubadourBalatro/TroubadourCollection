--- RandomEternals - Grant.lua
--
-- Turning config entries into cards on the board.
--
-- The work is done by the game's own add_joker (functions/common_events.lua:374), which is the
-- same function challenge decks use to hand you their starting jokers (game.lua:2067-2078). It
-- builds the Card, materializes it, calls add_to_deck(), applies the edition and emplaces it in
-- G.jokers -- in that order, which is what makes a negative joker pay for its own slot rather
-- than stealing one.
--
-- Slot limits are deliberately not enforced. CardArea:emplace does not check card_limit --
-- vanilla checks it at the call sites instead, which is why a full board cannot be bought into
-- but can be granted into. A config that asks for seven jokers gets seven jokers.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Grant = {}

-- Pins a card's sell value at a chosen number.
--
-- sell_cost is not a field you set, it is one the game derives: set_cost recomputes it as
-- max(1, floor(cost/2)) + ability.extra_value (card.lua:382), from scratch, every time anything
-- touches the card.
--
-- This used to write the difference into extra_value and let the derivation land on the target.
-- That was wrong, and the bug it caused is worth recording: extra_value is an offset, and the
-- target is an absolute number, so the two only agree while the cost stays put. Buying
-- Clearance Sale (G.GAME.discount_percent = 25) cut a negative Troubadour's cost from 11 to 8,
-- its natural value from 5 to 4, and a card pinned at 0 through an offset of -5 became worth
-- -1. Vanilla sell_cost can never be negative -- the only vanilla writers of extra_value, Egg
-- (card.lua:3021) and Gift Card (card.lua:3031), add to it -- so nothing in the game guards
-- against one. Temperance (card.lua:4260) just sums sell_cost across the jokers, and five cards
-- at -1 cancelled four real jokers to exactly $0.
--
-- So the target is stored on the card instead, and re-applied after each recompute by repin
-- below. extra_value is left alone at 0 as the vanilla growth channel, which keeps an Egg or a
-- Gift Card raising a pinned card from its pin.
local function set_sell_value(card, want, key)
   want = tonumber(want)
   if not want then
      RandomEternals.log("  " .. key .. ": sell value is not a number, leaving it alone")
      return
   end
   want = math.floor(want)
   if want < 0 then
      RandomEternals.log("  " .. key .. ": sell value below 0, using 0")
      want = 0
   end

   card.ability.extra_value = 0
   card.ability.randometernals_sell = want
   RandomEternals.pcall(card.set_cost, card)
end

-- Re-applies a pinned sell value after the game has recomputed one. Installed over Card:set_cost
-- by Hooks, so it runs for every card in the game -- hence the single field test first: a card
-- the config never pinned leaves here untouched and behaves exactly as vanilla does, its value
-- still tracking shop discounts and inflation.
function RandomEternals.Grant.repin(card)
   local pin = card and card.ability and card.ability.randometernals_sell
   if not pin then return end
   card.sell_cost = pin + (card.ability.extra_value or 0)
   -- Mirrors card.lua:384, so the number printed on the card matches the one it will pay.
   card.sell_cost_label = card.facing == "back" and "?" or card.sell_cost
end

-- Applies one sticker and reports whether the game accepted it.
--
-- set_eternal and set_perishable both consult a *_compat flag on the center and silently do
-- nothing when it is false (card.lua:506-518) -- Ice Cream can never be eternal, Hologram can
-- never be perishable. Silently is the problem: without reading the field back afterwards, a
-- config asking for an eternal Ice Cream looks like it worked and the joker is sellable.
local function apply_sticker(card, name, setter, field)
   RandomEternals.pcall(setter, card, true)
   if not card.ability[field] then
      RandomEternals.log("  " .. name .. " refused by the game: " ..
                   tostring(card.config.center.name) .. " is not " .. name .. "-compatible")
      return false
   end
   return true
end

-- Creates one card for one config entry. Returns the number of cards actually granted.
--
-- Everything is validated before add_joker is reached, because add_joker indexes
-- G.P_CENTERS[key] with no guard and would error out of Game.start_run on a typo.
function RandomEternals.Grant.one(entry, silent)
   if type(entry) ~= "table" then
      RandomEternals.log("skipping a config entry that is not a table")
      return 0
   end

   local center, why = RandomEternals.joker_center(entry.key)
   if not center then
      RandomEternals.log("skipping entry: " .. tostring(why))
      return 0
   end

   local edition, bad_edition = RandomEternals.edition_name(entry.edition)
   if bad_edition then
      RandomEternals.log("skipping " .. entry.key .. ": " .. bad_edition)
      return 0
   end

   local count = tonumber(entry.count) or 1
   if count < 1 then return 0 end

   local granted = 0
   for _ = 1, count do
      -- add_joker applies the edition itself, and would apply eternal too -- but not the other
      -- two stickers, so all three are done together below for one consistent order.
      local card = add_joker(entry.key, edition, silent or granted > 0)
      if not card then
         RandomEternals.log("add_joker returned nothing for " .. entry.key)
         return granted
      end

      -- Eternal first. The game treats the two as mutually exclusive -- each setter checks the
      -- other field -- so the order decides the winner rather than leaving it to whichever
      -- happens to run second.
      --
      -- Perishable is dropped only when eternal actually stuck. An eternal the center forbids
      -- leaves the card with nothing, and there is no reason to refuse the perishable the
      -- config also asked for on the strength of a sticker that never landed.
      local got_eternal = false
      if entry.eternal then
         got_eternal = apply_sticker(card, "eternal", card.set_eternal, "eternal")
      end
      if entry.perishable then
         if got_eternal then
            RandomEternals.log("  " .. entry.key ..
                         " asked for eternal and perishable; the game allows only one, keeping eternal")
         else
            apply_sticker(card, "perishable", card.set_perishable, "perishable")
         end
      end
      if entry.rental then RandomEternals.pcall(card.set_rental, card, true) end
      -- After rental only so the log line below reads in the order the fields were applied;
      -- a pin no longer cares what the cost was doing when it was set.
      if entry.sell ~= nil then set_sell_value(card, entry.sell, entry.key) end
      if entry.pinned then card.pinned = true end

      granted = granted + 1

      if RandomEternals.config.log_grants then
         local bits = {}
         if edition then bits[#bits + 1] = edition end
         if card.ability.eternal then bits[#bits + 1] = "eternal" end
         if card.ability.perishable then bits[#bits + 1] = "perishable" end
         if card.ability.rental then bits[#bits + 1] = "rental" end
         if card.pinned then bits[#bits + 1] = "pinned" end
         if entry.sell ~= nil then bits[#bits + 1] = "sells for $" .. tostring(card.sell_cost) end
         RandomEternals.log("granted " .. entry.key ..
                      (#bits > 0 and " (" .. table.concat(bits, ", ") .. ")" or ""))
      end
   end

   return granted
end

-- Queues one event per entry, the way the challenge-joker loop in Game:start_run does. The
-- event queue matters at both call sites: at run start a wipe is still in flight and
-- G.CONTROLLER.locks.load is held, and at cash-out the round-eval UI is being torn down inside
-- an immediate event of its own. Creating cards inline in either place lands them mid-animation.
--
-- Only the first card makes a materialize sound. Six jokers appearing at once otherwise arrive
-- as one flat noise.
function RandomEternals.Grant.list(entries, why)
   if not RandomEternals.enabled() then return end
   if entries == nil then return end
   if not RandomEternals.is_list(entries) then
      RandomEternals.log(tostring(why) .. ": config list is not an array of entries, ignoring it")
      return
   end
   if #entries == 0 then return end

   RandomEternals.log(why .. ": granting " .. #entries .. " entr" .. (#entries == 1 and "y" or "ies"))
   for i, entry in ipairs(entries) do
      G.E_MANAGER:add_event(Event({
         func = function()
            RandomEternals.pcall(RandomEternals.Grant.one, entry, i ~= 1)
            return true
         end
      }))
   end
end

-- Repairs cards granted before sell values were pinned.
--
-- Those carry the old offset in extra_value and no target, and the target itself cannot be
-- recovered from them. A negative extra_value is a RandomEternals-only signature -- every vanilla
-- writer adds -- so it is safe to key on, and the drift that made it wrong only ever came from
-- a cost cut, so the card is never worth more now than it was pinned at. Pinning max(0,
-- sell_cost) therefore restores the common case exactly (a card pinned at 0 sitting at -1 goes
-- back to 0) and can never lower a card further.
--
-- Best effort, and only for cards from before the fix: a card pinned at some other number lands
-- at whatever it had drifted to rather than at its original target.
function RandomEternals.Grant.migrate()
   if not (G.jokers and G.jokers.cards) then return end
   for _, card in ipairs(G.jokers.cards) do
      local ability = card.ability
      if ability and not ability.randometernals_sell
         and type(ability.extra_value) == "number" and ability.extra_value < 0 then
         ability.randometernals_sell = math.max(0, card.sell_cost or 0)
         ability.extra_value = 0
         RandomEternals.pcall(card.set_cost, card)
         RandomEternals.log("repaired a stale sell value on " ..
                      tostring(card.config.center.name) .. ": now $" .. tostring(card.sell_cost))
      end
   end
end

-- Granted at every cash-out, once per round -- three times an ante, or twice when a blind is
-- skipped, since a skipped blind has no cash-out to be granted at.
--
-- Keyed on G.GAME.round, which ease_round(1) advances when a blind is SELECTED
-- (button_callbacks.lua:2542), not when it ends. So by the time a cash-out runs it already
-- names the round that just finished, and it never repeats for the life of the run -- which is
-- what makes it a better marker than the ante plus the blind, that pair being reused by a
-- Hieroglyph walking the ante backwards.
function RandomEternals.Grant.for_round(round, force)
   if not RandomEternals.enabled() then return end
   if type(round) ~= "number" then return end

   G.GAME.randometernals_granted_round = G.GAME.randometernals_granted_round or {}
   if G.GAME.randometernals_granted_round[round] and not force then return end
   G.GAME.randometernals_granted_round[round] = true

   RandomEternals.Grant.list(RandomEternals.config.per_round, "end of round " .. tostring(round))
end

-- Which list belongs to an ante: the override for that ante if one is written, otherwise the
-- shared per_ante list. An override of {} is a deliberate "nothing this ante" and must not fall
-- through to the default, which is why this tests for the key rather than for emptiness.
function RandomEternals.Grant.list_for_ante(ante)
   local overrides = RandomEternals.config.per_ante_overrides
   if type(overrides) == "table" and overrides[ante] ~= nil then
      return overrides[ante], "ante " .. tostring(ante) .. " override"
   end
   return RandomEternals.config.per_ante, "end of ante " .. tostring(ante)
end

-- Granted once per ante, no matter how many times the hook fires. Independent of the per-round
-- list above: on a boss cash-out both fire, the round list first.
--
-- It can fire more than once for one ante: Handy's insta-cash-out early-returns from
-- G.FUNCS.cash_out when the press carries a button (button_callbacks.lua:2924) and the real
-- call follows from elsewhere, so the wrapper sees the same cash-out twice. The marker lives on
-- G.GAME, which save_run serialises wholesale (functions/misc_functions.lua:1473), so it also
-- survives closing and reopening the run -- otherwise every Continue during a shop would hand
-- out the ante's jokers again.
function RandomEternals.Grant.for_ante(ante, force)
   if not RandomEternals.enabled() then return end
   if type(ante) ~= "number" then return end

   G.GAME.randometernals_granted = G.GAME.randometernals_granted or {}
   if G.GAME.randometernals_granted[ante] and not force then return end
   G.GAME.randometernals_granted[ante] = true

   local entries, why = RandomEternals.Grant.list_for_ante(ante)
   RandomEternals.Grant.list(entries, why)
end
