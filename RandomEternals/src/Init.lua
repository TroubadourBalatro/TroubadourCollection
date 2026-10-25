--- RandomEternals - Init.lua
--
-- Deferred install.
--
-- Hooks go on from the first love.update rather than at load time. Lovely gives no ordering
-- guarantee between mods that append to main.lua, so installing the cash_out wrapper a frame
-- late is what makes it land outside Handy's patch of that function -- and it also guarantees
-- G and G.FUNCS exist, which they do not while main.lua is still being read.
--
-- Nothing is ticked per frame: both features are event-driven, so this wrapper does its work
-- once and then costs a single boolean test per frame forever after.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Init = {}

do
   RandomEternals.Init.love_update_ref = love.update
   function love.update(dt, ...)
      if not RandomEternals.installed and G and G.FUNCS and G.FUNCS.cash_out and Game then
         RandomEternals.installed = true
         RandomEternals.pcall(RandomEternals.Hooks.install)
         RandomEternals.pcall(RandomEternals.Command.install)
         RandomEternals.pcall(RandomEternals.Menu.install)
      end
      RandomEternals.Init.love_update_ref(dt, ...)
   end
end
