--- RandomEternals - Hooks.lua
--
-- The two places the mod touches the game: the start of a run, and the cash-out that ends a
-- round -- which, when the blind was a boss, also ends an ante.
--
-- Both are installed at runtime from Init rather than at load, because a Lovely chunk appended
-- to main.lua has no ordering guarantee against the other mods appended alongside it. For
-- cash_out that is the whole point: Handy patches the body of G.FUNCS.cash_out by pattern, and
-- installing a frame late puts this wrapper outside that body rather than racing it.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Hooks = {}

function RandomEternals.Hooks.install()
   if type(Game) ~= "table" or type(Game.start_run) ~= "function" then
      RandomEternals.log("WARNING: Game.start_run missing, not granting at run start")
   else
      local start_run_ref = Game.start_run
      function Game:start_run(args)
         local result = start_run_ref(self, args)
         -- On both paths, and before the grant: a loaded run is the only thing that can be
         -- holding cards from before sell values were pinned, and a new run's own grants
         -- arrive already pinned.
         RandomEternals.pcall(RandomEternals.Grant.migrate)

         -- args.savetext is a Continue or a save load (game.lua:2022). The board it restores
         -- already holds whatever was granted the first time, so granting again would stack
         -- another copy of the start list every time the run is opened.
         if not (args and args.savetext) then
            -- Re-read Config.lua off the disk first, so the list granted a line below is the
            -- one the file holds now rather than the one baked in at launch. Only on this
            -- path: a loaded run keeps the config it started with, and its per_round and
            -- per_ante lists with it, rather than changing shape halfway through.
            -- The Random Eternals Challenge writes its draw into the file just before that
            -- read, so it arrives through the same path as a hand edit.
            RandomEternals.pcall(RandomEternals.Eternals.prepare, args)
            RandomEternals.pcall(RandomEternals.Reload.apply)
            RandomEternals.pcall(RandomEternals.Grant.list, RandomEternals.config.start, "run start")
         end
         return result
      end
   end

   -- Every card in the game passes through here, so the cost is one field test per call --
   -- Grant.repin returns immediately for anything the config never pinned, leaving vanilla
   -- prices, and vanilla sell values, exactly as they were.
   if type(Card) ~= "table" or type(Card.set_cost) ~= "function" then
      RandomEternals.log("WARNING: Card.set_cost missing, sell values will not stay pinned")
   else
      local set_cost_ref = Card.set_cost
      function Card:set_cost()
         set_cost_ref(self)
         RandomEternals.Grant.repin(self)
      end
   end

   if type(G.FUNCS.cash_out) ~= "function" then
      RandomEternals.log("WARNING: G.FUNCS.cash_out missing, not granting per ante")
      return
   end

   local cash_out_ref = G.FUNCS.cash_out
   G.FUNCS.cash_out = function(e, ...)
      -- Both of these are read before the original runs. cash_out calls reset_blinds(), which
      -- clears blind_states, so afterwards there is no way left to tell a boss cash-out from
      -- any other one.
      --
      -- The ante is off by one on purpose: ease_ante(1) already ran back in end_round
      -- (functions/state_events.lua:248), so G.GAME.round_resets.ante names the ante about to
      -- start and the one that just finished is one below it.
      --
      -- The round needs no such correction: ease_round(1) runs at blind select, so
      -- G.GAME.round already names the round this cash-out is ending.
      local boss, ante, round
      if G.GAME and G.GAME.round_resets then
         boss = G.GAME.round_resets.blind_states
                and G.GAME.round_resets.blind_states.Boss == "Defeated"
         ante = G.GAME.round_resets.ante - 1
         round = G.GAME.round
      end

      local ret = { cash_out_ref(e, ...) }

      -- Neither is gated on whether this particular call did the work. Handy's insta-cash-out
      -- makes one of the two calls a no-op, and which one it is depends on settings; the
      -- markers inside for_round and for_ante are what keep each grant to once either way.
      --
      -- Round before ante, so a boss cash-out -- which is both -- lands the smaller unit
      -- first and reads in the log in the order it happened.
      RandomEternals.pcall(RandomEternals.Grant.for_round, round)
      if boss then RandomEternals.pcall(RandomEternals.Grant.for_ante, ante) end

      return unpack(ret)
   end
end
