# Afterglow Bridge (Apple Home)

ESP32 firmware that puts your Tuya lights in Apple Home and runs the TV automations, with no HomePod, Apple TV, cloud or phone involved.

In Home you get each light (on, brightness, white temperature, colour where the bulb has them) plus a **Lights Follow TV** switch that pauses the TV automations.

## What you need

- Any ESP32, ESP32-S3 or ESP32-C3 dev board with USB (about $8 to $12), on a USB charger
- A computer with Chrome or Edge, once, for flashing
- 2.4 GHz Wi-Fi, same network as the lights

## 1. Flash

Download from [Releases](https://github.com/soum91/afterglow/releases/tag/firmware-latest):

| Board | First install | Updates |
|---|---|---|
| ESP32 (most common) | `AfterglowBridge-esp32-build-N-full.bin` at `0x0` | `...-app.bin` at `0x10000` |
| ESP32-S3 | `AfterglowBridge-esp32s3-build-N-full.bin` at `0x0` | `...-app.bin` at `0x10000` |
| ESP32-C3 | `AfterglowBridge-esp32c3-build-N-full.bin` at `0x0` | `...-app.bin` at `0x10000` |

Open https://espressif.github.io/esptool-js/, Connect (hold BOOT if it won't), set the address, pick the file, Program, then press RESET. Updating with the `-app.bin` keeps Wi-Fi and the Home pairing.

## 2. Wi-Fi

Join **HomeSpan-Setup** (password `homespan`), enter your Wi-Fi and an 8-digit setup code (or keep `466-37-726`).

## 3. Pair with Afterglow

Afterglow › Settings › Apple Home bridge. It finds the bridge on the network, pairs, and sends your lights (local keys and IPs stay on your Wi-Fi). Run **Find lights on Wi-Fi** first; only lights with a Wi-Fi address can be bridged. Whenever lights, scenes or automations change, the app resends on its own next time you open it.

## 4. Add to Home

Home app › + › Add Accessory › More options › **Afterglow Bridge** › Add Anyway › setup code.

## TV automations

Set in Afterglow › Settings › TV & automations, run on the bridge:

- **TV off**: a scene (default all off), optionally only between two times, after a fixed delay or one it learns. Learning: when you switch a rule light off yourself within 20 min of the TV going off, that gap is recorded (last 9 kept); the delay is the median, 60 s until there are two. If you turn a light back on within 3 min of the bridge switching it off, it records that it should have waited longer. Turning the TV back on cancels the countdown.
- **TV on**: optional scene.
- **Late-night sweep**: all off at a set time unless the TV is on.

TV state comes from the Bravia REST API every 4 s; two "standby" answers (or three timeouts) in a row count as off.

## Serial console (115200)

- `@i` lights, TV, learned delay, recent events
- `@R` forget the paired phone (to pair a different one)
- `?` HomeSpan commands (Wi-Fi reset, unpair, factory reset)

## Notes

- Many bulbs accept only one local connection. The bridge never holds one open (connect, send, close), and polls each light every 15 s, so the app and Smart Life still work.
- Adding or removing lights restarts the bridge (about 20 s) so Home sees the change. Accessory IDs come from the Tuya device ID, so rooms you assigned in Home stick.
