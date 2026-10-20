# Afterglow

An iOS app for Tuya / Smart Life lights that talks to them straight over your Wi-Fi (Tuya's cloud only as a fallback), plus an ESP32 bridge that puts them in Apple Home and turns them off when the TV goes off.

## Features

- **Local first.** Lights found on your Wi-Fi are switched over Tuya's LAN protocol (3.3, 3.4, 3.5): instant, and still working with the internet down. Anything not found locally, or when you're away, goes through the cloud. A small Wi-Fi or cloud icon on each tile shows which path the last command took.
- **Every light type.** On/off, brightness, white temperature and colour, for v1 and v2 bulbs, strips, ceiling lights and dimmers. Lamps on smart plugs count if their name has "lamp", "light" or "bulb" in it.
- **Scenes** like Equinox: chips on the home screen, tap to run, long-press to edit, + to add. "All lights" scenes or per-light looks, a "capture how the lights look now" button, and arrive/leave home triggers (geofence, works with the app closed). Comes with Bright, Evening, Movie and All off.
- **Widgets**: small (all on/off), medium (4 lights), large (6 lights + 3 scenes), lock screen circular, rectangular and inline. All buttons work without opening the app.
- **Control Center** (iOS 18+): a Light toggle you can add once per light (or for all lights) and a Scene button. These also work on the lock screen corner buttons and the Action button.
- **Siri** with no setup: "lights off in Afterglow", "Afterglow Movie", "toggle desk lamp in Afterglow", "bedtime in Afterglow" (lights off unless the TV is on).
- **Learns your habits**: every lights-off and scene is donated to Siri, so it starts suggesting them on the lock screen around the times you use them.
- **Shortcuts actions**: Turn All Lights On/Off, Toggle Light, Set Light Power, Set Light Brightness, Run Light Scene, Is the TV On, Lights Off If TV Is Off.

## Apple Home and the TV

An iPhone app can't add accessories to Apple Home, and Home automations need a HomePod or Apple TV. The [bridge](Bridge/README.md) fixes both: a ~$10 ESP32 that shows every light in Home (on, brightness, white temperature, colour) and controls them locally, and runs the TV automations itself, no hub, no phone:

- **TV turns off** → run a scene (default: all lights off), only at night if you want, after a delay that it **learns from you**: it notices how long you usually wait after the TV goes off before switching the lights off yourself (from Home, Afterglow, Smart Life or the wall) and uses your typical gap. Turn the lights back on right after it fires and it learns to wait longer.
- **TV turns on** → optional scene (e.g. Movie).
- **Late-night sweep** → everything off at a set time, skipped while the TV is on.
- A **Lights Follow TV** switch in Home pauses all of it ("Hey Siri, turn off Lights Follow TV").

The TV is read with Sony's Bravia REST API (`getPowerStatus`). On the TV: Settings › Network & Internet › Home network › IP control › Authentication "Normal and Pre-Shared Key", Remote start on.

## Setup

1. Sideload the IPA from [Releases](https://github.com/soum91/afterglow/releases) (AltStore, SideStore or Sideloadly, keep app extensions on).
2. Sign in: Smart Life › Me › ⚙︎ › Account and Security › User Code, paste it, save the QR, scan it from Smart Life's scanner.
3. Afterglow lists your lights and searches your Wi-Fi for them. Settings › Find lights on Wi-Fi runs it again; give the lights fixed IPs in your router so they stay found.
4. Optional: Settings › Apple Home bridge, then Settings › TV & automations.

## Build

Every push to `main` builds `Afterglow-<version>-build-<N>.ipa` on GitHub Actions and publishes it as release `build-N` with a changelog since the previous build. The app and widget are ad-hoc signed with the `group.com.soum91.afterglow` App Group. Firmware changes build `AfterglowBridge-<chip>-build-<N>-*.bin` as release `firmware-build-N` (and `firmware-latest`).

Local: `brew install xcodegen && xcodegen generate`, open `Afterglow.xcodeproj`.

## How it talks to the lights

Cloud: the Smart Life sharing login Home Assistant's Tuya integration uses (no developer account), signed and AES-GCM encrypted requests to `/v1.1/m/thing/{id}/commands`. Device list, specifications and the data point map (`/v1.0/m/life/devices/{id}/status`) come from there too, along with each light's local key.

Local: TCP 6668, Tuya 3.3 (AES-ECB + CRC), 3.4 (session key + HMAC) and 3.5 (session key + AES-GCM), ported from [tinytuya](https://github.com/jasonacox/tinytuya). Lights are found by scanning the /24 for port 6668 and proving each light's key against each open address. Standard light points: 20 switch, 21 mode, 22 brightness (10–1000), 23 temperature (0–1000), 24 colour `HHHHSSSSVVVV`; v1 bulbs use 1–5 with `RRGGBB0HHHSSVV`.

Independent implementation, not affiliated with Tuya or Sony.
