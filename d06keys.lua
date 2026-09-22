-- d06keys.lua
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
-- Turns the D06 ring's "swipe" buttons into real key presses on a Kobo.
--
-- Each ring button sends a mouse drag in one direction (left/right/up/down).
-- This script reads the ring's raw HID reports, works out the direction of
-- each press, and injects one key press back into the ring's OWN input
-- device (/dev/input/eventN named "D06"). KOReader's Bluetooth plugin is
-- already listening to that device, so it sees the keys as coming from the
-- ring and you can bind them in the plugin's key bindings.
--
-- Run with KOReader's LuaJIT, e.g.:
--   cd /mnt/onboard/.adds/koreader && ./luajit d06keys.lua

local ffi = require("ffi")
local bit = require("bit")
local C = ffi.C

------------------------------------------------------------------------
-- Settings: edit these to taste
------------------------------------------------------------------------
local RING_NAME = "D06"   -- HID name of the ring (from evtest / uevent)
local VERBOSE   = true    -- print each detected press

-- Linux key codes sent for each swipe direction. Use four different codes
-- to bind four different actions. The ring must declare the key (the D06's
-- evtest header lists which it supports); these all qualify.
-- 103 Up, 108 Down, 105 Left, 106 Right, 104 PageUp, 109 PageDown,
-- 114 VolumeDown, 115 VolumeUp
local KEYS = {
  up    = 103,  -- swipe up    -> Up arrow
  left  = 105,  -- swipe left  -> Left arrow
  down  = 108,  -- swipe down  -> Down arrow
  right = 106,  -- swipe right -> Right arrow
}

------------------------------------------------------------------------
-- C bindings
------------------------------------------------------------------------
ffi.cdef[[
struct d06_timeval { long tv_sec; long tv_usec; };
struct d06_input_event {
  struct d06_timeval time;
  uint16_t type;
  uint16_t code;
  int32_t  value;
};
int  open(const char *path, int flags);
int  close(int fd);
long read(int fd, void *buf, size_t n);
long write(int fd, const void *buf, size_t n);
int  usleep(unsigned int usec);
int  ioctl(int fd, unsigned long req, void *arg);
]]

local O_RDONLY, O_WRONLY = 0, 1
local EV_SYN, EV_KEY = 0, 1
local EVIOCSKEYCODE = 0x40084504

-- Scancodes of the ring's mouse buttons (HID Button page, buttons 1-5).
-- These get remapped to "no key" so the ring's own clicks (key 272 etc.)
-- never reach KOReader; only the injected keys do.
local SILENCE_SCANCODES = { 0x90001, 0x90002, 0x90003, 0x90004, 0x90005 }

local function silence_clicks(fd)
  local map = ffi.new("uint32_t[2]")
  local okcount = 0
  for _, sc in ipairs(SILENCE_SCANCODES) do
    map[0], map[1] = sc, 0   -- 0 = KEY_RESERVED: the kernel drops it
    if C.ioctl(fd, EVIOCSKEYCODE, map) == 0 then okcount = okcount + 1 end
  end
  return okcount
end

local function log(msg)
  if VERBOSE then io.stdout:write(os.date("%H:%M:%S "), msg, "\n"); io.stdout:flush() end
end

local function readfile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function listdir(path)
  local out = {}
  local p = io.popen("ls " .. path .. " 2>/dev/null")
  if p then
    for l in p:lines() do out[#out + 1] = l end
    p:close()
  end
  return out
end

------------------------------------------------------------------------
-- Finding the ring
------------------------------------------------------------------------
local function find_hidraw()
  for _, n in ipairs(listdir("/sys/class/hidraw")) do
    local u = readfile("/sys/class/hidraw/" .. n .. "/device/uevent")
    if u and ("\n" .. u):find("\nHID_NAME=" .. RING_NAME .. "\n", 1, true) then
      return "/dev/" .. n
    end
  end
end

local function find_ring_event()
  for _, n in ipairs(listdir("/sys/class/input")) do
    if n:match("^event%d+$") then
      local name = readfile("/sys/class/input/" .. n .. "/device/name")
      if name and name:gsub("%s+$", "") == RING_NAME then
        return "/dev/input/" .. n
      end
    end
  end
end

------------------------------------------------------------------------
-- Key injection
------------------------------------------------------------------------
local ev = ffi.new("struct d06_input_event")
local EVSIZE = ffi.sizeof(ev)
local function emit(fd, etype, code, value)
  ev.type, ev.code, ev.value = etype, code, value
  local n = tonumber(C.write(fd, ev, EVSIZE))
  if n ~= EVSIZE then
    log("Write to ring device failed (returned " .. n .. ", errno " .. ffi.errno() .. ")")
  end
end
local function tap(fd, code)
  emit(fd, EV_KEY, code, 1); emit(fd, EV_SYN, 0, 0)
  emit(fd, EV_KEY, code, 0); emit(fd, EV_SYN, 0, 0)
end

local function s16(lo, hi)
  local v = lo + hi * 256
  if v >= 32768 then v = v - 65536 end
  return v
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------
-- Ring mouse report (ID 3): [3][buttons][X lo][X hi][Y lo][Y hi][wheel]
local buf = ffi.new("uint8_t[64]")

while true do
  local hpath = find_hidraw()
  local epath = find_ring_event()
  local hfd = hpath and C.open(hpath, O_RDONLY) or -1
  local efd = (hfd >= 0 and epath) and C.open(epath, O_WRONLY) or -1

  if hfd < 0 or efd < 0 then
    if hfd >= 0 then C.close(hfd) end
    C.usleep(1000000)  -- ring not connected yet; check again in 1 s
  else
    log("Reading " .. hpath .. ", injecting keys into " .. epath)
    log("Silenced " .. silence_clicks(efd) .. " of " .. #SILENCE_SCANCODES .. " mouse buttons")
    local sent = false
    while true do
      local n = tonumber(C.read(hfd, buf, 64))
      if n <= 0 then break end  -- ring disconnected
      if n >= 7 and buf[0] == 3 then
        if bit.band(buf[1], 1) == 0 then
          sent = false            -- button released: ready for the next press
        elseif not sent then
          local dx, dy = s16(buf[2], buf[3]), s16(buf[4], buf[5])
          if dx ~= 0 or dy ~= 0 then
            local dir
            if math.abs(dx) > math.abs(dy) then
              dir = dx < 0 and "left" or "right"
            else
              dir = dy < 0 and "up" or "down"
            end
            tap(efd, KEYS[dir])
            sent = true
            log("Swipe " .. dir .. " -> key " .. KEYS[dir])
          end
        end
      end
    end
    C.close(hfd)
    C.close(efd)
    log("Ring disconnected; waiting for it to come back")
  end
end
