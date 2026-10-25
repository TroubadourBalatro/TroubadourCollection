--- RandomEternals - Menu.lua
--
-- The Random Eternals Challenge row on the New Run screen: a toggle, and -- only while it is
-- ticked -- a cycle picking how many eternals to draw, or "1 per ante". Both write into RandomEternals.Eternals.state,
-- which Eternals.prepare reads when the run starts.
--
-- Steamodded replaces the vanilla New Run tab with its own paged run select unless its
-- "vanilla run select" option is on, so both builders are wrapped; whichever one the menu
-- calls gets the row inserted below the deck and stake selection.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Menu = {}

do
   local state = RandomEternals.Eternals.state

   -- 1 to 6, then the "1 per ante" mode.
   local function count_options()
      local opts = {}
      for i = 1, 6 do opts[i] = i end
      opts[#opts + 1] = RandomEternals.Eternals.PER_ANTE
      return opts
   end

   -- Where the remembered count sits in the cycle; a number past the end is clamped to the
   -- largest one.
   local function option_index(opts)
      if state.count == RandomEternals.Eternals.PER_ANTE then return #opts end
      return math.max(1, math.min(tonumber(state.count) or 1, #opts - 1))
   end

   local function set_count(args)
      state.count = args.to_val
   end

   -- Shows or hides the count cycle with the toggle, the way vanilla's toggle_seeded_run does
   -- the seed box: an object built when wanted and removed when not, checked every frame.
   local function box(e)
      if e.config.object and not state.enabled then
         e.config.object:remove()
         e.config.object = nil
      elseif not e.config.object and state.enabled then
         local opts = count_options()
         local current = option_index(opts)
         state.count = opts[current]
         e.config.object = UIBox{
            definition = {n=G.UIT.ROOT, config={align = "cm", colour = G.C.CLEAR}, nodes={
               {n=G.UIT.C, config={align = "cm", padding = 0.05}, nodes={
                  {n=G.UIT.T, config={text = "Eternals", scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
               }},
               {n=G.UIT.C, config={align = "cm"}, nodes={
                  create_option_cycle{options = opts, current_option = current, opt_callback = 'randometernals_eternals_count',
                     w = 1.6, scale = 0.7, no_pips = true, colour = G.C.RED},
               }},
            }},
            config = {offset = {x=0,y=0}, parent = e, type = 'cm'}
         }
         e.config.object:recalculate()
      end
   end

   function RandomEternals.Menu.row()
      return {n=G.UIT.R, config={align = "cm", padding = 0.05, minh = 0.7}, nodes={
         create_toggle{col = true, label = "Random Eternals Challenge", label_scale = 0.3, w = 0, scale = 0.7,
            ref_table = state, ref_value = 'enabled'},
         {n=G.UIT.C, config={align = "cm", minw = 3, minh = 0.6}, nodes={
            {n=G.UIT.O, config={align = "cm", func = 'randometernals_eternals_box', object = Moveable()}},
         }},
      }}
   end

   function RandomEternals.Menu.install()
      if RandomEternals.Menu.installed or not G.UIDEF then return end
      RandomEternals.Menu.installed = true

      -- Here rather than at load: G.FUNCS does not exist while main.lua is still being read.
      G.FUNCS.randometernals_eternals_count = set_count
      G.FUNCS.randometernals_eternals_box = box

      -- Vanilla: root rows are deck, stake, seed box, play button. The row goes after stake.
      local vanilla_ref = G.UIDEF.run_setup_option
      if type(vanilla_ref) == "function" then
         G.UIDEF.run_setup_option = function(setup, ...)
            local t = vanilla_ref(setup, ...)
            if setup == 'New Run' and t and t.nodes then
               RandomEternals.pcall(table.insert, t.nodes, math.min(3, #t.nodes + 1), RandomEternals.Menu.row())
            end
            return t
         end
      end

      -- Steamodded: the root holds one column of the page (deck or stake) and then the nav bar.
      -- The row goes between them.
      local galdur_ref = G.UIDEF.run_select_galdur
      if type(galdur_ref) == "function" then
         G.UIDEF.run_select_galdur = function(...)
            local t = galdur_ref(...)
            local col = t and t.nodes and t.nodes[1]
            if col and col.nodes then
               RandomEternals.pcall(table.insert, col.nodes, math.min(2, #col.nodes + 1), RandomEternals.Menu.row())
            end
            return t
         end
      end
   end
end
