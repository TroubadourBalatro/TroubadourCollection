--- RandomEternals - test/reload.lua
--
--   luajit Mods/RandomEternals/test/reload.lua
--
-- Reading a config off the disk, with no love.filesystem and no game around it: that the real
-- src/Config.lua loads, that each way a hand-edited file can be wrong is refused by name, and
-- -- the point of the sandbox -- that a file which fails partway through leaves the config
-- already in memory exactly as it was.
local here = (arg and arg[0]) or "Mods/RandomEternals/test/reload.lua"
local prefix = here:match("^(.*)test[/\\]reload%.lua$")
local SRC = prefix and (prefix .. "src/") or "../src/"
local TMP = os.getenv("TMPDIR") or "/tmp/"

for _, f in ipairs({ "Core", "Config", "Reload" }) do
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

-- Writes a fixture and returns its path. io.open is the read path here, so an absolute path is
-- what Reload.read falls back to.
local n = 0
local function fixture(body)
   n = n + 1
   local path = ("%srandometernals_reload_%d_%d.lua"):format(TMP, os.time(), n)
   local f = assert(io.open(path, "w"))
   f:write(body)
   f:close()
   return path
end

-- ---------------------------------------------------------------------------
print("\n-- the real config file loads, and is not the table already in memory")
local real, why = RandomEternals.Reload.load(SRC .. "Config.lua")
check("loaded", type(real), "table")
check("reason", why, nil)
check("fresh table", real ~= RandomEternals.config, true)
check("start is a list", RandomEternals.is_list(real.start), true)

print("\n-- a file that will not compile is refused, and names itself")
local bad, err = RandomEternals.Reload.load(fixture([[
RandomEternals.config = { start = { { key = "j_joker" } }  -- no closing brace
]]))
check("refused", bad, nil)
check("has a reason", type(err) == "string" and #err > 0, true)

print("\n-- a file that errors halfway is refused whole, not half-applied")
local before = RandomEternals.config
local path = fixture([[
RandomEternals.config = { start = { { key = "j_joker" } } }
error("boom")
]])
check("refused", (RandomEternals.Reload.load(path)), nil)
check("apply said no", (RandomEternals.Reload.apply(path)), false)
check("live config untouched", RandomEternals.config, before)

print("\n-- a list written without its braces is refused by name")
local _, shape = RandomEternals.Reload.load(fixture([[
RandomEternals.config = { start = { key = "j_joker" } }
]]))
check("names the field", shape, "start is not an array of entries")

print("\n-- a file that sets no config at all")
local _, none = RandomEternals.Reload.load(fixture("local x = 1\n"))
check("refused", none, "the file did not set RandomEternals.config to a table")

print("\n-- a path that is not there")
local _, missing = RandomEternals.Reload.load(TMP .. "randometernals_no_such_file.lua")
check("refused", (missing or ""):match("^cannot read") ~= nil, true)

print("\n-- the sandbox does not write through to the live namespace")
RandomEternals.Reload.load(fixture([[
RandomEternals.clobbered = true
RandomEternals.config = { start = {} }
]]))
check("namespace clean", RandomEternals.clobbered, nil)

print("\n-- apply installs, and only on success")
local good = fixture([[
RandomEternals.config = { enabled = true, start = { { key = "j_blueprint" } } }
]])
check("applied", RandomEternals.Reload.apply(good), true)
check("installed", RandomEternals.config.start[1].key, "j_blueprint")
local kept = RandomEternals.config
check("refused", (RandomEternals.Reload.apply(TMP .. "randometernals_no_such_file.lua")), false)
check("kept the good one", RandomEternals.config, kept)

-- ---------------------------------------------------------------------------
print("")
if failures > 0 then
   print(("%d failed"):format(failures))
   os.exit(1)
end
print("all ok")
