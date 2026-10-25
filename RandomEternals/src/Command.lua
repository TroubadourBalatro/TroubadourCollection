--- RandomEternals - Command.lua
--
-- DebugPlus console commands, for exercising the config without playing to a boss blind.
--
-- DebugPlus is optional. Without it the require fails, install does nothing, and the mod keeps
-- working -- these commands are a testing convenience, not the feature.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Command = {}

do
   local function in_run()
      return G and G.STAGE == G.STAGES.RUN and G.jokers and true or false
   end

   function RandomEternals.Command.start()
      if not in_run() then return "randometernals: not in a run", "ERROR" end
      RandomEternals.Grant.list(RandomEternals.config.start, "start list, by command")
      return "granting the start list"
   end

   function RandomEternals.Command.round(args)
      if not in_run() then return "randometernals: not in a run", "ERROR" end
      local round = tonumber(args and args[1]) or G.GAME.round
      -- force, because the point of the command is to see a grant the run's own marker may
      -- already have recorded as done.
      RandomEternals.Grant.for_round(round, true)
      return "granting the per-round list for round " .. tostring(round)
   end

   function RandomEternals.Command.ante(args)
      if not in_run() then return "randometernals: not in a run", "ERROR" end
      -- Defaults to the ante in progress, which on a boss cash-out is already the next one.
      local ante = tonumber(args and args[1]) or (G.GAME.round_resets.ante)
      local _, why = RandomEternals.Grant.list_for_ante(ante)
      -- force, because the point of the command is to see a grant that the run's own marker
      -- may already have recorded as done.
      RandomEternals.Grant.for_ante(ante, true)
      return "granting " .. why
   end

   -- No in_run check: reloading from the main menu, between runs, is the useful case.
   function RandomEternals.Command.reload()
      local ok, why = RandomEternals.Reload.apply()
      if not ok then return "randometernals: " .. tostring(why), "ERROR" end
      return "config reloaded from " .. RandomEternals.Reload.PATH
   end

   function RandomEternals.Command.install()
      if RandomEternals.Command.installed then return end

      local got, api = pcall(require, "debugplus-api")
      if not got or not api or not api.isVersionCompatible(1) then return end

      local dp = api.registerID("RandomEternals")
      -- registerID returns false plus a reason when the ID is taken -- a reload, or a second
      -- copy of the mod. Nothing to add commands to, so leave the existing ones alone.
      if not dp then return end

      RandomEternals.Command.installed = true

      dp.addCommand({
         name = "randometernals_reload",
         shortDesc = "Re-read Config.lua from disk now",
         desc = "randometernals_reload\n\nRe-reads Mods/RandomEternals/src/Config.lua and replaces the "
            .. "config in memory with what it holds. This happens on its own at the start of "
            .. "every new run; the command is for picking up an edit without starting one -- "
            .. "to change the per_round or per_ante list of the run already in "
            .. "progress.\n\nA file that will not load leaves the current config in place and "
            .. "says why.",
         exec = function() return RandomEternals.Command.reload() end,
      })

      dp.addCommand({
         name = "randometernals_start",
         shortDesc = "Grant the configured start list now",
         desc = "randometernals_start\n\nGrants RandomEternals.config.start onto the current board, the "
            .. "same way it is granted when a run begins. Useful for checking a config without "
            .. "restarting the game into a new run.",
         exec = function() return RandomEternals.Command.start() end,
      })

      dp.addCommand({
         name = "randometernals_round",
         shortDesc = "Grant the per-round list now",
         desc = "randometernals_round [n]\n\nGrants RandomEternals.config.per_round, the list granted at "
            .. "every cash-out. With no n it uses the current round.\n\nIgnores the "
            .. "once-per-round marker, so it can be run repeatedly.",
         exec = function(args) return RandomEternals.Command.round(args) end,
      })

      dp.addCommand({
         name = "randometernals_ante",
         shortDesc = "Grant the per-ante list for an ante",
         desc = "randometernals_ante [n]\n\nGrants the list RandomEternals would grant at the end of ante "
            .. "n -- the override for that ante if one is configured, otherwise per_ante. With "
            .. "no n it uses the current ante.\n\nIgnores the once-per-ante marker, so it can "
            .. "be run repeatedly on the same ante.",
         exec = function(args) return RandomEternals.Command.ante(args) end,
      })
   end
end
