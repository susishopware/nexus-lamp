# Nexus Lampe — ESPHome firmware

WS2812B lighting for the 3D printed shopware "Nexus" logo lamp, driven by an
ESP32 DevKit and exposed to Home Assistant. A GitHub pull request makes the X
flash a colour and then return to whatever it was doing before.

## Hardware

| | |
|---|---|
| Board | ESP32 DevKit, 38 pin, USB-C |
| Chip | ESP32-D0WD-V3, dual core, 240 MHz, 4 MB flash |
| USB bridge | CP2102 — macOS and Windows drive it without an extra driver |
| Serial port | `/dev/cu.usbserial-0001` on macOS, `COM*` on Windows |
| Data pin | GPIO4 |
| LEDs | 10 × WS2812B (5 per X half), one daisy chain |

Every lamp announces itself as `nexus-lampe-<mac suffix>`, so several can live on
one network. `name_add_mac_suffix` takes care of that; nothing is per-device in
this repository.

GPIO4 instead of the originally planned GPIO16: GPIO16/17 carry the PSRAM bus on
WROVER modules, and esptool cannot tell WROOM from WROVER. GPIO4 is free on
both, so the choice removes a variable. Change `led_pin` in the substitutions
if you ever want to move it.

## Current budget

Powered from the ESP32's USB-C only. A WS2812B pixel draws about 20 mA per
channel, so ~60 mA at full white — 10 LEDs would be ~600 mA, over what a USB
port must deliver. `color_correct` in the light config caps every channel at
45 %, which puts the worst case at roughly:

```
10 LEDs × 60 mA × 0.45 = 270 mA   +   ESP32 WiFi peak ≈ 150 mA   ≈ 420 mA
```

The cap sits below the brightness slider, so it holds no matter what Home
Assistant asks for. If the board resets when the LEDs switch on, lower
`current_cap`.

## WiFi provisioning — no credentials in the build

These lamps go to other people, whose networks we cannot know in advance, so
nothing network-specific is baked into the image. Each lamp asks its owner once
and stores the answer in the ESP32's NVS flash, where it survives reboots and
OTA updates. Two ways in, both built in:

**Over USB** (`improv_serial`). Plug the lamp into a computer, open
<https://web.esphome.io> in Chrome or Edge, hit Connect, pick the port, then
"Configure WiFi". No install, no CLI, nothing to read. The same mechanism drives
our own installer page — see [`../installer/`](../installer/), which flashes
*and* provisions in one flow.

**Over the setup hotspot** (`captive_portal`). An unprovisioned lamp raises an
open network called **Nexus Lampe Setup**. Joining it pops the setup form up by
itself on phones and Macs; otherwise `http://192.168.4.1`. Works without a
cable, which is the fallback when someone's WiFi password changes later.

The hotspot is deliberately open so a recipient needs no instructions beyond
"connect to the Nexus network". Anyone in radio range during setup could point
the lamp at their own network — for a desk ornament that seemed like the right
trade. Add `password:` under `wifi: ap:` if you disagree.

Each lamp also gets a unique hostname via `name_add_mac_suffix: true`
(`nexus-lampe-<mac suffix>.local`), so several of them can live on one network.

## Setup for building the firmware

Only needed by whoever maintains the firmware, not by recipients.

```bash
git clone https://github.com/susishopware/nexus-lamp.git
cd nexus-lamp
python3 -m venv .venv
.venv/bin/pip install esphome
```

Then generate `firmware/secrets.yaml`. Do not hand-write it — the same script
runs in CI, and having one source keeps the two from drifting:

```bash
export API_ENCRYPTION_KEY=...   # openssl rand -base64 32
export OTA_PASSWORD=...         # openssl rand -hex 16
export WEB_PASSWORD=...
export MQTT_BROKER=...          # HiveMQ cluster hostname, no scheme, no port
export MQTT_USERNAME=nexus-lamp # the SUBSCRIBE-ONLY credential
export MQTT_PASSWORD=...
firmware/make-secrets.sh
```

No WiFi credentials anywhere: those are provisioned per device. The file is
gitignored; `secrets.yaml.example` is the template that is committed, and
`mqtt_ca.pem` holds the public root certificates the script injects.

## Commissioning

### Step 1 — flash over the cable, LEDs not connected yet

```bash
.venv/bin/esphome run firmware/nexus-lampe.yaml --device /dev/cu.usbserial-0001
```

The CP2102 resets the chip into the bootloader itself, so no BOOT button is
needed. After the upload, esphome stays attached to the serial log.

What a healthy first boot looks like — remember there are no credentials in the
image, so it comes up as a hotspot, not on your network:

- `Starting fallback AP 'Nexus Lampe Setup'`
- `Nexus lamp up: 10 LEDs on GPIO4, current cap 45%`
- no `Brownout detector was triggered` and no `rst:0xc (SW_CPU_RESET)` loop

Now provision it. Either join **Nexus Lampe Setup** and fill in the form, or
leave the cable in and use <https://web.esphome.io> → Connect → Configure WiFi.
After that the log shows `WiFi Connected!` with an IP.

Home Assistant then discovers the device on its own (Settings → Devices →
ESPHome). If it asks for an encryption key, paste `api_encryption_key` from
`secrets.yaml`.

From here on, updates go over the air — no cable:

```bash
.venv/bin/esphome run  firmware/nexus-lampe.yaml
.venv/bin/esphome logs firmware/nexus-lampe.yaml
```

### Step 2 — LED test with 3 pixels, still not soldered into the print

Cut a short piece of strip and hook it up with jumper wires. Three pixels draw
at most ~180 mA, so nothing can be damaged while we sort out the two things
that usually go wrong: colour order and data level.

| Strip pad | ESP32 pin |
|---|---|
| `5V` | `5V` (labelled `VIN` on some clones) |
| `GND` | any `GND` |
| `DI` / `DIN` | `GPIO4` (silkscreen `4` or `D4`) |

Go by the silkscreen, not by pin position — clone layouts differ. `num_leds`
can stay at 10 with only 3 attached; the first three simply light up.

Press the **LED self test** button (Home Assistant, or the device's web page at
`http://<ip>`). Expected sequence: **red → green → blue → white**, about 1.2 s
each, then off.

- Red and green swapped → change `rgb_order: GRB` to `RGB`
- First pixel wrong colour or flickering → data level problem, see
  troubleshooting
- Nothing at all → check that ESP32 and strip share a GND, and that the arrow
  on the strip points *away* from the soldered end

Only once this passes is it worth soldering.

### Step 3 — soldering the final chain

**Unplug USB before soldering.**

1. Cut two pieces of 5 LEDs. Cut only on the marked lines, through the middle
   of the copper pads, so both resulting ends keep solderable pads.
2. The arrows on the strip are the data direction. The end the arrow points
   *away from* is the input (`5V` / `DI` / `GND`); the other end is `DO`.
3. Tin the pads first, then the wire ends, then join them. If the strip is
   IP65, peel back the silicone over the pads.
4. Half A input: three wires to `5V`, `GND`, `DI`.
5. Bridge to half B: three wires from half A's output end — `5V`→`5V`,
   `GND`→`GND`, `DO`→`DI`. This is the pair that has to run through the cable
   breakthrough between the two X halves.
6. Put the **330–470 Ω resistor in series in the data line**, as close to half
   A's `DI` pad as you can get it — not at the ESP32 end. It damps reflections
   at the point where they matter.
7. Solder the **100–1000 µF electrolytic capacitor across `5V` and `GND`** at
   the start of the chain. Polarity matters: the stripe on the can is the
   negative leg and goes to `GND`. Getting it backwards makes it vent.
8. Before plugging in: check `5V` against `GND` for a short, and verify
   continuity along the chain.
9. Plug in USB, run the self test again — now all 10 pixels.

### Step 4 — pull request trigger

**Primary path: MQTT.** The lamps sit in other people's home networks, so
nothing can reach them from the outside. Instead each lamp holds an outbound
TLS connection to a broker and subscribes to one broadcast topic. CI publishes
once and every lamp reacts — no port forwarding, no Home Assistant needed, and
it scales to however many lamps we hand out.

```
GitHub Action  --publish-->  broker (8883, TLS)  <--subscribe--  lamp, lamp, lamp
```

Fill in `mqtt_broker`, `mqtt_username` and `mqtt_password` in `secrets.yaml`
(currently `CHANGEME`), then set the same values as repository secrets
`MQTT_HOST`, `MQTT_USER`, `MQTT_PASS`, `MQTT_TOPIC` for
[`../.github/workflows/pr-flash.yml`](../.github/workflows/pr-flash.yml). That
workflow belongs in the repositories you want to watch, not just here.

Test the whole chain by hand:

```bash
mosquitto_pub -h "$MQTT_HOST" -p 8883 --capath /etc/ssl/certs \
  -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t shopware/nexus/pr -m '{"event":"merged"}'
```

`mqtt_ca_cert` in `secrets.yaml` holds ISRG Root X1, which covers brokers whose
chain ends at Let's Encrypt (HiveMQ Cloud and EMQX Cloud among them). For
anything else, fetch the root and replace it:

```bash
openssl s_client -showcerts -connect "$MQTT_HOST:8883" </dev/null
```

MQTT never blocks anything: `reboot_timeout: 0s` means an unreachable broker is
simply ignored, and `topic_prefix: null` keeps the lamps from publishing state
of their own — a hundred lamps on one broker stay silent apart from their
subscription.

**Also available: Home Assistant.** For recipients who run HA, the native API
is still there and gets discovered automatically:

```yaml
action: esphome.nexus_lampe_pr_event    # name carries the MAC suffix per lamp
data:
  event: opened      # opened | merged | closed | success | failure
```

For full control there is also `..._pr_flash_rgb` with `red`, `green`, `blue`
(0..1), `duration` (ms) and `blinks`.

**Also available: straight at the lamp** (same network only):

```bash
curl -fsS --digest -u "$WEB_USER:$WEB_PASS" -X POST \
  "http://nexus-lampe-<mac suffix>.local/button/pr_flash_test/press"
```

Colour map, defined in the `pr_event` script:

| event | colour | blinks |
|---|---|---|
| `opened` | shopware blue `#0078BF` | 2 |
| `merged` | purple `#8250DF` | 3 |
| `failure` | red `#D1242F` | 4 |
| `success` | green `#1A7F37` | 2 |
| `closed` | grey | 2 |

The flash saves the light's previous state (on/off, brightness, colour) and
fades back into it afterwards. A second trigger arriving mid-flash restarts the
flash but keeps the originally saved state, so repeated PRs cannot leave the
lamp stuck on a status colour.

## What the lamp does on its own

No app required for any of this.

**Every power-on:** red, green, blue, about 400 ms each. Confirms the data line
works and that `rgb_order` is right — red has to come first. Then it restores
whatever state its owner left it in (`restore_mode: RESTORE_DEFAULT_ON`), because
a lamp with no switch has to light up when you plug it in.

**A lamp that has never been on a network** breathes slowly in shopware blue
after the greeting: alive, waiting to be set up. It gives up after three minutes
and turns white, because someone who never wants to connect it should still own a
lamp and not a pulsing ornament.

**The first time it ever connects,** it goes green for 1.3 s and then fades to
white. That is the moment somebody is standing there wondering whether their
password worked.

The blue-and-green sequence happens **once in the lamp's life** — a global with
`restore_value: true` latches in flash on the first successful connection. Later
reconnects stay silent on purpose: a lamp that flashes every time the router
reboots would be a bug, not a feature.

To see it again — for testing, or to check what a colleague will experience —
press the **Setup-Anzeige neu starten** button. It clears the latch and reboots.
It does *not* forget the WiFi credentials; for a real handover, reflash from the
installer page, which erases them.

## Troubleshooting

**The board only boots when the LED strip is disconnected, resets over and over
with `rst:0x1 (POWERON_RESET)` or `rst:0x10 (RTCWDT_RTC_RESET)`, and not one
single ESPHome log line ever appears.** Check the ground pin, not your soldering.

This cost hours once. On the 38-pin DevKitC the pin **directly next to `5V` is
`CMD` — GPIO11, one of the six SPI flash lines** — and on clones it can be
silkscreened in a way that reads like `GND` at a glance. Tie that pin to ground
and the ESP32 cannot read its own flash: it never reaches the firmware, resets,
and tries again forever. The nearest real `GND` in that row is four pins further
up; the one at the top of the opposite row is easier to hit unambiguously.

The giveaway is that nothing you do to the strip changes anything — re-soldering,
shortening it, swapping wires. If the board boots perfectly with the strip
unplugged and never boots with it plugged in, suspect the pins before the joints.

**Flickering, or the first pixel misbehaves while the rest is fine.** The
ESP32 drives 3.3 V logic and WS2812B wants ~0.7 × 5 V = 3.5 V. Usually fine
over a short lead, but if not: either sacrifice the first pixel (feed it data,
ignore it, and let its 5 V output drive the rest) or add a 74HCT125 level
shifter. `chipset: WS2812` is the more forgiving timing variant already.

**Board resets when the LEDs turn on.** Inrush current. Lower `current_cap`,
verify the electrolytic capacitor is present and correctly polarised, and use
a proper USB-C charger rather than a hub port.

**`Brownout detector was triggered` in the log.** Same cause as above, or a
thin/long USB cable.

**Serial port busy or upload fails.** Something else is attached to the port —
`.venv/bin/esphome logs` from another shell, or the Arduino IDE. Close it. If
the upload still won't start, hold BOOT while it says `Connecting...`.

**OTA fails but serial works.** The `ota_password` in `secrets.yaml` has to
match what is on the device; after changing it, one more cable flash is needed.
