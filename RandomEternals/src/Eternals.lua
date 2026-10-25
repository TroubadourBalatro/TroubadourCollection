--- RandomEternals - Eternals.lua
--
-- The Random Eternals Challenge: a toggle on the New Run screen (Menu.lua) that, when a new run
-- starts, draws N distinct jokers uniformly from every joker that can carry the eternal sticker
-- and writes them into the start list of Config.lua as eternals. Reload then reads the file
-- back exactly as it would an edit by hand, so the draw is granted by the ordinary start path.
--
-- In "1 per ante" mode the draw is one eternal in start plus one in each of per_ante_overrides
-- [1] through [39], so the run gains a new eternal at the end of every ante up to and including
-- ante 39, all distinct.
--
-- The draw lives between two pairs of marker comments, one inside start = { ... } and one
-- inside per_ante_overrides = { ... }, and nothing outside them is touched. With the toggle off, a new run comments the previous draw out rather than
-- deleting it -- the file keeps a record of the last challenge, and grants none of it.

if not RandomEternals then RandomEternals = {} end
RandomEternals.Eternals = {}

do
   -- Each block: its two marker comments, and the list they sit in, for a Config.lua from
   -- before the markers existed.
   RandomEternals.Eternals.BLOCKS = {
      start = { begin = "-- >>> random eternals", finish = "-- <<< random eternals",
                anchor = "start" },
      per_ante = { begin = "-- >>> random eternals per ante",
                   finish = "-- <<< random eternals per ante", anchor = "per_ante_overrides" },
   }

   -- The count cycle's last option, after the numbers.
   RandomEternals.Eternals.PER_ANTE = "1 per ante"
   -- The last completed ante that gains one, in "1 per ante" mode.
   RandomEternals.Eternals.LAST_ANTE = 39

   -- Session state the menu toggle and count cycle write into. Not saved across launches.
   -- count is a number, or PER_ANTE.
   RandomEternals.Eternals.state = { enabled = false, count = 5 }

   -- Its own generator, seeded off the clock. math.random is reseeded by the game's own
   -- pseudorandom calls, so on a seeded run it would hand back the same draw every time.
   local rng
   local function random(n)
      if not rng and love and love.math and love.math.newRandomGenerator then
         rng = love.math.newRandomGenerator(os.time(), math.floor((os.clock() % 1) * 1e9))
      end
      if rng then return rng:random(n) end
      return math.random(n)
   end

   -- Every joker the game's set_eternal would accept, in collection order.
   function RandomEternals.Eternals.pool()
      local keys = {}
      local jokers = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker or {}
      for _, center in ipairs(jokers) do
         if center.eternal_compat and center.key and not RandomEternals.NOT_A_JOKER[center.key] then
            keys[#keys + 1] = center.key
         end
      end
      return keys
   end

   -- n keys sampled uniformly without replacement: a partial Fisher-Yates over a copy.
   function RandomEternals.Eternals.draw(n)
      local keys = RandomEternals.Eternals.pool()
      n = math.max(0, math.min(n or 0, #keys))
      for i = 1, n do
         local j = i + random(#keys - i + 1) - 1
         keys[i], keys[j] = keys[j], keys[i]
      end
      local out = {}
      for i = 1, n do out[i] = keys[i] end
      return out
   end

   -- Exact match, not a substring: the start markers are a prefix of the per-ante ones.
   local function is_marker(line, marker)
      return line:match("^%s*(.-)%s*$") == marker
   end

   local function split(body)
      local src = {}
      for line in (body .. "\n"):gmatch("(.-)\r?\n") do src[#src + 1] = line end
      if src[#src] == "" then src[#src] = nil end
      return src
   end

   -- Returns the file body with the lines between a block's markers replaced by `lines`.
   -- Without the markers, they are added at the top of the block's list, so a Config.lua from
   -- before this feature still works.
   function RandomEternals.Eternals.splice(body, lines, block)
      block = block or RandomEternals.Eternals.BLOCKS.start
      local src = split(body)

      local first, last
      for i, line in ipairs(src) do
         if not first and is_marker(line, block.begin) then first = i
         elseif first and is_marker(line, block.finish) then last = i; break end
      end

      local before, after = {}, {}
      if first and last then
         for i = 1, first do before[#before + 1] = src[i] end
         for i = last, #src do after[#after + 1] = src[i] end
      else
         local at
         for i, line in ipairs(src) do
            if line:match("^%s*" .. block.anchor .. "%s*=%s*{%s*$") then at = i; break end
         end
         if not at then
            return nil, ("no %s = { line and no random eternals markers"):format(block.anchor)
         end
         for i = 1, at do before[#before + 1] = src[i] end
         before[#before + 1] = "      " .. block.begin
         after[1] = "      " .. block.finish
         for i = at + 1, #src do after[#after + 1] = src[i] end
      end

      local out = {}
      for _, l in ipairs(before) do out[#out + 1] = l end
      for _, l in ipairs(lines) do out[#out + 1] = l end
      for _, l in ipairs(after) do out[#out + 1] = l end
      return table.concat(out, "\n") .. "\n"
   end

   -- The lines currently between a block's markers, each commented out unless it already is.
   local function commented(body, block)
      local lines, inside = {}, false
      for _, line in ipairs(split(body)) do
         if not inside and is_marker(line, block.begin) then inside = true
         elseif inside and is_marker(line, block.finish) then break
         elseif inside then
            if line:match("^%s*$") or line:match("^%s*%-%-") then
               lines[#lines + 1] = line
            else
               lines[#lines + 1] = (line:gsub("^(%s*)", "%1-- ", 1))
            end
         end
      end
      return lines
   end

   local function write(path, body)
      if love and love.filesystem and love.filesystem.write then
         if love.filesystem.write(path, body) then return true end
      end
      local f = io.open(path, "w")
      if not f then return nil, "cannot write " .. path end
      f:write(body)
      f:close()
      return true
   end

   local function entry(key)
      return ('{ key = "%s", eternal = true }'):format(key)
   end

   -- The new contents of both blocks, or nil when the challenge is off for this run.
   local function drawn(state)
      local E = RandomEternals.Eternals
      if state.count == E.PER_ANTE then
         local keys = E.draw(1 + E.LAST_ANTE)
         local per_ante = {}
         for ante = 1, #keys - 1 do
            per_ante[ante] = ("      [%d] = { %s },"):format(ante, entry(keys[ante + 1]))
         end
         RandomEternals.log(("random eternals: 1 per ante -- %s to start, then %s")
            :format(tostring(keys[1]), table.concat(keys, ", ", 2)))
         return { keys[1] and ("      " .. entry(keys[1]) .. ",") or nil }, per_ante
      end
      local keys = E.draw(state.count)
      local start = {}
      for i, key in ipairs(keys) do start[i] = "      " .. entry(key) .. "," end
      RandomEternals.log(("random eternals: drew %d -- %s"):format(#keys, table.concat(keys, ", ")))
      return start, {}
   end

   -- Called on the new-run path, before Reload reads the file. A challenge run never draws:
   -- the toggle sits on the New Run tab, and a challenge has its own fixed setup.
   function RandomEternals.Eternals.prepare(args, path)
      path = path or RandomEternals.Reload.PATH
      local body, why = RandomEternals.Reload.read(path)
      if not body then
         RandomEternals.log("random eternals: " .. tostring(why))
         return false
      end

      local B = RandomEternals.Eternals.BLOCKS
      local start, per_ante
      if RandomEternals.Eternals.state.enabled and not (args and args.challenge) then
         start, per_ante = drawn(RandomEternals.Eternals.state)
      else
         start, per_ante = commented(body, B.start), commented(body, B.per_ante)
      end

      local new_body, err = RandomEternals.Eternals.splice(body, start, B.start)
      if new_body then new_body, err = RandomEternals.Eternals.splice(new_body, per_ante, B.per_ante) end
      if not new_body then
         RandomEternals.log("random eternals: " .. tostring(err))
         return false
      end
      if new_body == body then return true end
      local ok, werr = write(path, new_body)
      if not ok then RandomEternals.log("random eternals: " .. tostring(werr)) end
      return ok
   end
end
