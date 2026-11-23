# Changelog

## [build-46] - 2026-11-23

## Verified changes since build-42

- Fix Bulk actions settings compile error and fail CI correctly on Xcode errors ([`7d9967ac`](https://github.com/soum91/afterglow/commit/7d9967aceae03239a4e757f3bf4a698fa67e090c); `.github/workflows/build.yml`, `Afterglow/Views/SettingsView.swift`)
- Make All Lights scope explicit and guarantee power strip exclusion by default ([`ca2ede8a`](https://github.com/soum91/afterglow/commit/ca2ede8aad09ed159a850f73f600bcf38df76483); `Afterglow/Views/HomeView.swift`, `Afterglow/Views/SettingsView.swift`, `Shared/Light.swift`)
- Repair device management List structure and clarify safe default for added outlets ([`8e7df96d`](https://github.com/soum91/afterglow/commit/8e7df96d51cea1a3bda406b2e2109cc54d2e9939); `Afterglow/Views/SettingsView.swift`)
- Protect power strips from All Lights and add persistent device removal and icon fallback ([`f05b8dc9`](https://github.com/soum91/afterglow/commit/f05b8dc9e3783a242a35070cdf04395b58954d90); `Afterglow/App/AppStore.swift`, `Afterglow/App/Bridge.swift`, `Afterglow/Views/HomeView.swift`, and 8 more)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-42...build-46)

## [build-42] - 2026-11-23

## Verified changes since build-39

- Build only latest Afterglow IPA and verify FlareStore feed publication ([`5df3742f`](https://github.com/soum91/afterglow/commit/5df3742fe3d37290869c9e8f690b29a06e119775); `.github/workflows/build.yml`)
- Back up Afterglow Tuya credentials in private app storage across App Group re-signing ([`001efb19`](https://github.com/soum91/afterglow/commit/001efb192e731ea24917130a054c5dff18ce989e); `Shared/SharedStore.swift`)
- Prevent Tuya auth loss, serialize all-light commands, and add per-device icons ([`e762ae77`](https://github.com/soum91/afterglow/commit/e762ae77e23cc907956053363774965c9ec76389); `Afterglow/App/AppStore.swift`, `Afterglow/Views/HomeView.swift`, `Afterglow/Views/SettingsView.swift`, and 4 more)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-39...build-42)

## [build-39] - 2026-11-23

## Verified changes since build-38

- Open Tuya Smart instead of Smart Life during Afterglow QR sign-in ([`6708c3fe`](https://github.com/soum91/afterglow/commit/6708c3fed18902a7606c1c499930c4f44a90445a); `Afterglow/Views/LoginView.swift`, `README.md`)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-38...build-39)

## [build-38] - 2026-11-17

## Verified changes since build-37

- Switches: say why a device can't go to the bridge instead of claiming it was sent ([`c7f4255f`](https://github.com/soum91/afterglow/commit/c7f4255facbe23eb816056ceb40bfcf4fa448d65); `Afterglow/App/AppStore.swift`, `Afterglow/Views/SettingsView.swift`)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-37...build-38)

## [build-37] - 2026-11-14

## Verified changes since build-36

- Bridge payload: mark plain relays and plugs as kind=switch so Apple Home shows a switch, not a bulb ([`78d773ef`](https://github.com/soum91/afterglow/commit/78d773ef71847c8531ba05115c60a6720d9314b8); `Afterglow/App/Bridge.swift`)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-36...build-37)

## [build-36] - 2026-11-14

## Verified changes since build-34

- Fix build: wrap Siri dialog strings in IntentDialog ([`a1424c1a`](https://github.com/soum91/afterglow/commit/a1424c1ab567f7cb566dcfa9261f07bc4ea90c0c); `Shared/Intents.swift`)
- Siri: Turn on/off <light> shortcuts (each light or All lights); lights on/off says which light didn't answer ([`c5f02d53`](https://github.com/soum91/afterglow/commit/c5f02d53299978486a5933e2e627e0127dfb0592); `Afterglow/App/AfterglowApp.swift`, `Shared/Intents.swift`)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-34...build-36)

## [build-34] - 2026-11-14

## Verified changes since build-33

- Siri: Turn on/off <light> shortcuts (each light or All lights); lights on/off says which light didn't answer ([`239aa5d9`](https://github.com/soum91/afterglow/commit/239aa5d9ad494408d65989eb22114c35cdb9f584); `Shared/LightControl.swift`)

[Inspect exact code changes](https://github.com/soum91/afterglow/compare/build-33...build-34)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.


## Unreleased
- Sign-in QR flow now opens **Tuya Smart** (`tuyaSmart://`) rather than Smart Life, with an App Store fallback. Login instructions and QR share label use Tuya Smart; the underlying Tuya Home Assistant QR auth protocol is unchanged.

## Unreleased — Tuya session and device controls
- Preserve Tuya credentials and local device state on transient authorization errors; add explicit Tuya Smart reconnect.
- Coalesce token refresh within a client and reuse one cloud client across app, Shortcuts and widgets.
- Run all-device commands sequentially; show attempted and failed device counts instead of silently controlling only a subset.
- Automatically use a power-outlet icon for plug/strip categories, with a selectable icon for every light or plug in Settings.

## Unreleased — protect sockets and manage devices
- `All off`, `All on`, shortcuts, widgets, fallback TV/bedtime automations and default `All lights` scenes act on genuine lights only. A plug/strip/switch stays powered unless explicitly opted into the group.
- Afterglow home now separates lights from other devices while retaining individual control.
- Fix blank ceiling-light SF Symbol by testing availability and falling back to lightbulb.
- Add an explicit Remove action in device settings and a persistent removed-device exclusion list so cloud sync cannot reimport deleted devices. Allow restoration from Settings.
- Use selected device icons in widgets and expose the bulk-actions inclusion toggle.


## Unreleased — Siri colour and white light control
- Register brightness as a spoken Siri/App Shortcut action (previously an unadvertised App Intent).
- Add named colour, Kelvin white colour temperature and warmer/cooler intents using Afterglow's local-first Tuya command path.
- Reject unknown/removed light selections rather than falling back to controlling all; report partial per-device command failures.
- Keep power strips and switches out of all-lights colour/temperature actions.
- Avoid turning RGB bulbs on nearly black when changing colour from off.
- Preserve existing Bedtime and Toggle All as manual Shortcuts actions within the 10 promoted App Shortcuts limit.
