-- 2-d06keys.lua  (KOReader user patch)
-- Starts d06keys.lua in the background when KOReader launches,
-- and stops it when KOReader exits, so Nickel never sees it.
--
-- Put this file in:  /mnt/onboard/.adds/koreader/patches/
-- Keep d06keys.lua in: /mnt/onboard/.adds/koreader/

local KO_DIR  = "/mnt/onboard/.adds/koreader"
local PIDFILE = "/tmp/d06keys.pid"
local LOGFILE = "/tmp/d06keys.log"

local function start()
  os.execute(
    "cd " .. KO_DIR .. " && " ..
    "if [ ! -f " .. PIDFILE .. " ] || ! kill -0 $(cat " .. PIDFILE .. ") 2>/dev/null; then " ..
      "./luajit d06keys.lua > " .. LOGFILE .. " 2>&1 & echo $! > " .. PIDFILE .. "; " ..
    "fi"
  )
end

local function stop()
  os.execute(
    "[ -f " .. PIDFILE .. " ] && kill $(cat " .. PIDFILE .. ") 2>/dev/null; " ..
    "rm -f " .. PIDFILE
  )
end

start()

-- Stop the translator when KOReader exits (back to Nickel, restart, power off).
local Device = require("device")
local orig_exit = Device.exit
Device.exit = function(self, ...)
  stop()
  return orig_exit(self, ...)
end
