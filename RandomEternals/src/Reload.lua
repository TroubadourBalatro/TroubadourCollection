--- RandomEternals - Reload.lua
--
-- Reading Config.lua off the disk again, mid-session.
--
-- Lovely appends src/Config.lua onto main.lua at launch, so the table that chunk assigns is
-- the launch default and nothing more. This file reads the same source file again, runs it in
-- a sandbox, and swaps RandomEternals.config for what came back -- which is enough on its own,
-- because every consumer indexes RandomEternals.config at call time rather than caching a list
-- (Core.lua:44, Hooks.lua:30, Grant.lua:144/229/236-240). No hook is reinstalled and
-- RandomEternals.installed is not touched.
--
-- The sandbox is not about trust, it is about failure modes. A chunk that errors halfway has
-- already assigned whatever it assigned; run with the real globals, a half-executed Config.lua
-- would leave RandomEternals.config half-written and the run holding it. In a sandbox a failed load
-- leaves the live config exactly as it was.
--
-- The only hard rule here: never leave RandomEternals.config nil. Core.lua:45 tolerates it, but
-- Hooks.lua:30 and Grant.lua:229 would index through it and lose the grant.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Reload = {}

do
   -- love.filesystem is rooted at the save directory, which is the directory Mods/ lives in,
   -- so this relative path is the one to read in game. Settable so the offline harness can
   -- point it at a fixture.
   RandomEternals.Reload.PATH = "Mods/RandomEternals/src/Config.lua"

   -- love.filesystem first, io.open second -- the same two-step NegativeMine.Plan.read uses
   -- (NegativeMine/src/Plan.lua:45). io.open is what the test harness and an absolute path
   -- need; in game it is never reached.
   function RandomEternals.Reload.read(path)
      path = path or RandomEternals.Reload.PATH
      if type(path) ~= "string" or path == "" then return nil, "no config file named" end
      if love and love.filesystem and love.filesystem.read then
         local body = love.filesystem.read(path)
         if body then return body end
      end
      local f = io.open(path, "r")
      if not f then
         return nil, ("cannot read %s -- the path is relative to the Balatro save directory, "
            .. "the one Mods/ is in"):format(path)
      end
      local body = f:read("*a")
      f:close()
      if not body then return nil, ("cannot read %s"):format(path) end
      return body
   end

   -- Shape check, not content check. Every key, edition and sticker is already validated at
   -- grant time, one entry at a time, with a log line naming whatever was refused
   -- (Core.lua:55-79, Grant.lua:86-105) -- that is the right place for it, because a single
   -- bad entry should cost you that entry and nothing else.
   --
   -- What cannot wait until then is a list that is not a list. ipairs over a single entry
   -- written without its surrounding braces grants nothing and looks exactly like the mod
   -- being off, so a config shaped that way is refused whole, here, by name.
   local LISTS = { "start", "per_round", "per_ante" }

   local function check(cfg)
      if type(cfg) ~= "table" then
         return nil, "the file did not set RandomEternals.config to a table"
      end
      for _, field in ipairs(LISTS) do
         local v = cfg[field]
         if v ~= nil and not RandomEternals.is_list(v) then
            return nil, field .. " is not an array of entries"
         end
      end
      if cfg.per_ante_overrides ~= nil and type(cfg.per_ante_overrides) ~= "table" then
         return nil, "per_ante_overrides is not a table"
      end
      return cfg
   end

   local compile = loadstring or load

   -- Returns the config the file holds, or nil plus a reason. Does not install it.
   function RandomEternals.Reload.load(path)
      path = path or RandomEternals.Reload.PATH
      local body, why = RandomEternals.Reload.read(path)
      if not body then return nil, why end

      local chunk, err = compile(body, "@" .. path)
      if not chunk then return nil, tostring(err) end

      -- A fresh RandomEternals in the sandbox, falling through to the real globals for everything
      -- else. The file's own `if not RandomEternals then RandomEternals = {} end` guard finds this one
      -- truthy, so `RandomEternals.config = {...}` lands in env.RandomEternals and the live namespace is
      -- never written through.
      local env = setmetatable({ RandomEternals = {} }, { __index = _G })
      if setfenv then
         setfenv(chunk, env)
      else
         -- Lua 5.2+: _ENV is the chunk's first upvalue.
         local ok = pcall(debug.setupvalue, chunk, 1, env)
         if not ok then return nil, "cannot sandbox the config chunk" end
      end

      local ran, run_err = pcall(chunk)
      if not ran then return nil, tostring(run_err) end

      return check(env.RandomEternals and env.RandomEternals.config)
   end

   -- Loads and installs. Returns true, or false plus a reason -- and on failure leaves the
   -- config that is already in place alone, because a run granting the previous list is a far
   -- better outcome than a run granting nothing.
   function RandomEternals.Reload.apply(path)
      path = path or RandomEternals.Reload.PATH
      local cfg, why = RandomEternals.Reload.load(path)
      if not cfg then
         RandomEternals.log("config reload failed: " .. tostring(why)
            .. " -- keeping the config loaded at launch")
         return false, why
      end
      RandomEternals.config = cfg
      RandomEternals.log("config reloaded from " .. path)
      return true
   end
end
