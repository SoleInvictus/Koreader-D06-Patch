Readme · MD
# Koreader-D06-Patch: Hot doom-scrolling action, now for KOReader!
 
I wanted to use a cheap D06 Bluetooth "TikTok" scrolling ring as a four-button page turner in [KOReader](https://github.com/koreader/koreader), but the D06 had other plans. It doesn't behave like a keyboard or remote. Instead, the little bastard pretends to be a mouse and each button press would send a held left mouse button press; drag up, down, left, or right; then release. KOReader would only detect the left mouse click (key 272) from every button, so you couldn't bind them separately... until now!
 
This patch runs a translator in the background that reads the ring's raw Bluetooth reports, works out which way each button "swipes", and horks out a normal key press instead. It also silences the ring's own mouse clicks, and ignores the touch pad altogether. The Bluetooth plugin then sees four normal, separate key presses that you can map to any KOReader action.
 
**Tested on:** Kobo Libra Colour running KOReader with the [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) for Bluetooth support.

Will it work for you? Who knows, but it works for me! 
 
## Requirements
- A KOReader device with **working Bluetooth input**. For Kobo, a Bluetooth plugin such as [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin).
- The D06 ring **paired and connected** through that plugin.
- KOReader running as **root** (default on Kobo), so the script can open `/dev/hidraw*` and `/dev/input/*`.

## Installation (Kobo)
1. Connect the Kobo to your computer via USB and share storage.
2. Copy `d06keys.lua` to `.adds/koreader/`.
3. Copy `2-d06keys.lua` to `.adds/koreader/patches/`. Create the `patches` folder if it doesn't exist.
4. Eject the Kobo and start KOReader.
5. Connect the D06 through your Bluetooth plugin.
6. Open the plugin's key bindings for the D06 and bind each button.

| File | Put It Here | Why |
|---|---|---|
| `d06keys.lua` | `.adds/koreader/` | Translates silly TikTok swipes into big-kid key presses via KOReader's LuaJIT. |
| `2-d06keys.lua` | `.adds/koreader/patches/` | A patch to start td06keys.lua when KOReader launches and stop it when it exits. |

### Verifying Function
**Easy Mode**    
Just use it and see if it works.

**"I Like to Make Everything Difficult" Mode:**   
After installation, press a few keys on the D06. The translator logs these actions to `/tmp/d06keys.log`. From a shell on the Kobo (SSH or KOReader's terminal):
 
```
cat /tmp/d06keys.log
```
 
You should see something like:
 ```
19:25:44 Reading /dev/hidraw0, injecting keys into /dev/input/event4
19:25:44 Silenced 5 of 5 mouse buttons
19:25:52 Swipe up -> key 103
19:25:54 Swipe down -> key 108
```
 
### Manual Activation
Done using the shell for manual testing.

```
cd /mnt/onboard/.adds/koreader && ./luajit d06keys.lua
```
 
Press keys on your D06 and watch it output the assigned key presses. Press Ctrl-C to stop it. 
 
## Configuration
All settings but the install path (KO_DIR) are located at the top of `d06keys.lua`.
 
### `RING_NAME`
```lua
local RING_NAME = "D06"
```
 
The Bluetooth name the ring reports which the script uses to find the it after connection. If your ring shows up under a different name, change this. The easiest way is to just look under connected Bluetooth devices for its name. Alternately, run `cat /proc/bus/input/devices` with the ring connected and look for the `Name=` line.
 
### `KEYS`
```lua
local KEYS = {
  up    = 103,  -- swipe up    -> Up arrow
  left  = 105,  -- swipe left  -> Left arrow
  down  = 108,  -- swipe down  -> Down arrow
  right = 106,  -- swipe right -> Right arrow
}
```
 
The Linux key code sent for each swipe direction. Use **four different codes** if you want four separate actions: the Bluetooth plugin binds actions to key codes, so directions that share a code will share an action. There's really no reason to change this unless you need to specify a specific key for some reason.
 
**Common codes:**
 
| Code | Key |
|---|---|
| 103 / 108 | Up / Down |
| 105 / 106 | Left / Right |
| 104 / 109 | Page Up / Page Down |
| 114 / 115 | Volume Down / Volume Up |
 
The ring has to declare a key for the kernel to accept it. The D06 declares a full keyboard, so any standard key works.

### `SILENCE_SCANCODES`
```lua
local SILENCE_SCANCODES = { 0x90001, 0x90002, 0x90003, 0x90004, 0x90005 }
```
 
The raw IDs of the ring's mouse buttons (buttons 1–5). When the ring connects, the script remaps these to "no key" so the ring's own clicks never reach KOReader. Otherwise the plugin would bind left mouse click (272) to every action. You shouldn't need to change this for the D06.
 
### `VERBOSE`
```lua
local VERBOSE = true
```
Logs each detected swipe to `/tmp/d06keys.log`. Set it to `false` to keep the log quiet.
 
### Install path (in `2-d06keys.lua`)
```lua
local KO_DIR  = "/mnt/onboard/.adds/koreader"
```
 
Where KOReader and `d06keys.lua` live. This is correct for Kobo. On other devices, set it to the KOReader folder containing the `luajit` binary and, presumably, `d06keys.lua`.
 
## Using a different ring
The script expects the D06's report format. Each press sends mouse reports (report ID `03`) laid out as:
 
```
[03] [buttons] [X low] [X high] [Y low] [Y high] [wheel]
```
 
X and Y are signed 16-bit numbers. The direction of the first movement while the button is held decides which key is sent.
 
Other "swipe" rings may use a similar mouse-style format, but check yours before you rely on it:
 
1. Find the ring's raw node: `ls /dev/hidraw*` (only nodes that appear when the ring connects matter).
2. Dump reports while pressing each button, one at a time: `cat /dev/hidrawN | hexdump -C`. (**HINT**: replace the 'N' in hidrawN to match the folder associated with your device.)
3. Dump the report descriptor: `hexdump -C /sys/bus/hid/devices/*/report_descriptor`.
If the layout differs, adjust the parsing in the main loop of `d06keys.lua`. That's the `buf[0] == 3` check and the `buf[1]` to `buf[5]` offsets.
 
**Rings that won't work:** some scrolling rings, like the JX-11, present as a *multitouch touchscreen*. Kobo kernels don't include the `hid-multitouch` driver , so no input or raw device is ever created and there's nothing for this script to read. To check a ring before trying it: connect it and look for `DRIVER=` in `/sys/bus/hid/devices/*/uevent`. `hid-generic` is good but `hid-multitouch` won't work.
 
## Other e-reader devices
This *should* work on other Linux-based KOReader installs that have Bluetooth input, `hidraw` support, and root access, though you may need to update `KO_DIR`. It won't work on Android. This has only been tested on a Kobo Libra Colour, so I can't guarantee this will work for any other reader or scrolling ring.
