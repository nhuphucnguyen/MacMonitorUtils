# Mac Monitor Control

Mac Monitor Control is a small native menu-bar utility that turns a MacBook's
built-in display off while an external display remains active. This lets the lid
stay open for airflow instead of relying on clamshell mode.

## Safety behavior

- The **off** action is disabled until an external display is active.
- The built-in display is restored if the last external display disconnects.
  A one-second safety watchdog runs independently of macOS display callbacks,
  with additional follow-up checks for abrupt cable and dock disconnects.
- The app opts out of automatic termination so the watchdog remains resident.
- Recovery pauses during sleep and resumes after WindowServer and the login
  session have stabilized, avoiding wake-time configuration errors.
- The built-in display is restored before the app quits.
- Display changes apply only to the current login session.
- A recovery-only `--on` command is included; there is deliberately no headless
  `--off` command because the menu-bar app must remain alive to provide recovery.

## Build and run

The project requires macOS 13 or newer and the Apple Command Line Tools (or
Xcode). No third-party dependencies or special permissions are required.

```sh
./scripts/build-app.sh
open "build/Mac Monitor Control.app"
```

After launch, use the laptop icon in the menu bar. Connect an external display,
then choose **Turn Built-in Display Off**.

To inspect state or recover the panel from Terminal or SSH:

```sh
"build/Mac Monitor Control.app/Contents/MacOS/MacMonitorControl" --status
"build/Mac Monitor Control.app/Contents/MacOS/MacMonitorControl" --on
```

Run the hardware-independent safety checks with:

```sh
swift run MacMonitorControl --self-test
```

## Important limitation

Apple's public Core Graphics API can configure display arrangements but does not
offer a supported API to disconnect an individual physical display. This tool
loads the undocumented `CGSConfigureDisplayEnabled` function at runtime. It does
not require root access, but Apple can change or remove that function in a future
macOS release. When unavailable, the app leaves the display untouched and shows
the control as unavailable.

This disconnects the built-in display from the active WindowServer layout; it
does not claim to electrically cut every component in the panel assembly. The
thermal benefit primarily comes from being able to keep the lid open.
