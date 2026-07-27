# Nexus Lampe

A 3D printed shopware Nexus logo, lit from the inside by an ESP32 and ten
WS2812B pixels, that blinks when a pull request lands.

Built to be handed to colleagues: no credentials are baked into the firmware, so
each lamp is set up once by its own owner — over USB from a browser, or over the
lamp's own setup hotspot. Pull request events arrive over MQTT, which means no
port forwarding, no VPN and no Home Assistant required.

| | |
|---|---|
| [`firmware/`](firmware/) | ESPHome configuration, wiring notes, commissioning and troubleshooting |
| [`installer/`](installer/) | Browser installer — flash and provision a lamp in one flow, no software to install |
| [`installer/architecture.html`](installer/architecture.html) | Illustrated overview: what talks to what, and the reasoning behind it |
| [`.github/workflows/release.yml`](.github/workflows/release.yml) | Builds the firmware and publishes the installer to GitHub Pages |
| [`.github/workflows/pr-flash.yml`](.github/workflows/pr-flash.yml) | Copy this into any repository you want the lamps to watch |

## Set up a lamp

Open the installer page in Chrome or Edge, plug the lamp into a USB-C **data**
cable, and follow the two prompts. The lamp needs a 2.4 GHz network; the ESP32
has no 5 GHz radio.

What you should see: red, green, blue at power-on, then slow blue breathing while
it waits to be set up, then green once your password works, then white. From
there it is a lamp — and if you never connect it at all, it is still a lamp.

## Security posture

The firmware image is published so that lamps in other people's homes can fetch
their own updates. That makes it downloadable by anyone, so everything inside it
is treated as public:

- The MQTT credential in the image is **subscribe-only** and restricted to
  `nexus/v1/pr/#`. Extracted from the binary, it lets someone read pull request
  events. It cannot publish, so it cannot fake them.
- The publish credential lives only in GitHub Actions secrets and never in an
  image.
- The API encryption key and the OTA password are LAN-scoped: using them requires
  already being on the same network as a lamp. For a desk ornament that is an
  accepted risk rather than an overlooked one.

## Topics

```
nexus/v1/pr/<repo>     CI publishes here, never retained
nexus/v1/pr/+          every lamp subscribes here
{"event": "opened"}    opened | merged | closed | success | failure
```
