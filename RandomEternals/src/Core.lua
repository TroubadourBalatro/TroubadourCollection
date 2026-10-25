--- RandomEternals - Core.lua
--
-- Namespace, logging, the safety wrapper every hook goes through, and the validation that
-- stands between a hand-edited config file and the game's own card constructors.
--
-- Validation is not politeness here. add_joker indexes G.P_CENTERS[key] unguarded
-- (functions/common_events.lua:374), so a single typo'd key in the config would take down the
-- run with a nil index at the exact moment a run starts. Everything this mod feeds the game is
-- checked first, and a rejected entry names itself in the log instead.

if not RandomEternals then RandomEternals = {} end

-- Set by Init once the hooks are in place; guards against double installation.
RandomEternals.installed = false

-- The four vanilla editions, as Card:set_edition understands them (card.lua:387). It takes a
-- table of flags -- add_joker turns the string into {[edition] = true} for us -- and picks the
-- first of holo/foil/polychrome/negative it finds, so exactly one may be named.
--
-- "base" and "none" are accepted as spellings of "no edition" because a config being edited
-- towards a plain joker is more likely to have the field blanked than deleted.
RandomEternals.EDITIONS = {
   foil = true, holo = true, polychrome = true, negative = true,
}

function RandomEternals.log(msg)
   print("[RandomEternals] " .. tostring(msg))
end

-- Returns the function's first result on success, nil on failure. Failures are logged with the
-- message so a broken hook shows up in the log instead of silently eating a grant -- and, more
-- to the point, so a broken hook does not take the surrounding vanilla call down with it. Both
-- hooks here wrap functions the run cannot survive without.
function RandomEternals.pcall(fn, ...)
   if type(fn) ~= "function" then return nil end
   local ok, res = pcall(fn, ...)
   if not ok then
      RandomEternals.log("error: " .. tostring(res))
      return nil
   end
   return res
end

function RandomEternals.enabled()
   return RandomEternals.config and RandomEternals.config.enabled ~= false
end

-- Whether a key names a real joker. G.P_CENTERS holds every center in the game keyed by id --
-- jokers, tarots, vouchers, editions, the lot -- so the set check is what keeps "c_fool" or
-- "v_overstock_norm" out of the joker area. The two non-pool centers j_locked and
-- j_undiscovered (game.lua:355/358) are jokers by set but are placeholders for the collection
-- screen, never real cards, so they are named out explicitly.
RandomEternals.NOT_A_JOKER = { j_locked = true, j_undiscovered = true }

function RandomEternals.joker_center(key)
   if type(key) ~= "string" then return nil, "key is not a string" end
   if RandomEternals.NOT_A_JOKER[key] then return nil, key .. " is a placeholder, not a real joker" end
   local center = G and G.P_CENTERS and G.P_CENTERS[key]
   if not center then return nil, "no such center: " .. key end
   if center.set ~= "Joker" then
      return nil, key .. " is a " .. tostring(center.set) .. ", not a Joker"
   end
   return center
end

-- Normalises the edition field to what add_joker wants: a bare edition name, or nil for none.
-- Returns nil plus a reason for anything it does not recognise, which the caller logs and then
-- drops the whole entry -- rather than quietly handing over a plain joker when the config
-- clearly asked for a shiny one.
function RandomEternals.edition_name(edition)
   if edition == nil or edition == false then return nil end
   if type(edition) ~= "string" then return nil, "edition is not a string" end
   local e = edition:lower()
   if e == "" or e == "base" or e == "none" then return nil end
   if not RandomEternals.EDITIONS[e] then
      return nil, "unknown edition '" .. edition .. "'"
   end
   return e
end

-- A config list is a plain array of entry tables. Anything else -- a single entry written
-- without its surrounding braces, a stray string -- is rejected whole rather than iterated,
-- because ipairs over it would silently grant nothing and look like the mod was off.
function RandomEternals.is_list(v)
   if type(v) ~= "table" then return false end
   for k in pairs(v) do
      if type(k) ~= "number" then return false end
   end
   return true
end
