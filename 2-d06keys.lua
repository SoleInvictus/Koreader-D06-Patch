-- 2-d06keys.lua  (KOReader user patch)
-- Copyright (C) 2026 SoleInvictus
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- Starts d06keys.lua in the background a few seconds after KOReader has
-- finished starting, and stops it when KOReader exits.
-- Everything is wrapped in pcall so a problem here can't stop KOReader
-- from launching; errors go to KOReader's crash.log instead.
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
