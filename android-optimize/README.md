# Android speed & battery optimizer (no root)

`phone-optimize.sh` tunes a non-rooted Android phone over ADB. Every setting it
changes is saved first, and `./phone-optimize.sh revert` puts it back.

## What it does

| Command | Changes |
|---|---|
| `speed` | Animations at 0.5x (UI feels about twice as fast), compiles apps ahead of time (`bg-dexopt-job`), clears app caches |
| `battery` | Turns off background Wi-Fi/Bluetooth scanning, turns on the cached-app freezer (Android 11+), makes sure Adaptive Battery is on |
| `apply` | Both of the above |
| `restrict-apps` | Blocks background running for the apps you list in `restrict-apps.txt` (same as setting the app's battery use to *Restricted*) |
| `status` | Shows current values, battery level/temperature, and app restrictions |
| `revert` / `unrestrict-apps` | Undo |

Nothing is uninstalled or deleted except app cache files, which apps rebuild as needed.
Reboot after `apply`.

Want animations off completely? Run `ANIM_SCALE=0 ./phone-optimize.sh speed`.

## Setup on the phone (one time)

1. **Settings > About phone**, tap **Build number** 7 times to unlock Developer options.
2. **Settings > System > Developer options**, turn on **USB debugging**
   (and **Wireless debugging** if you'll use Option B).

## Option A: run from a computer

1. Install ADB ("platform-tools"):
   - Windows: https://developer.android.com/tools/releases/platform-tools
   - macOS: `brew install android-platform-tools`
   - Linux: `sudo apt install adb`
2. Plug in the phone by USB and accept the "Allow USB debugging?" prompt.
3. Run (on Windows, use Git Bash or WSL):
   ```
   ./phone-optimize.sh status
   ./phone-optimize.sh apply
   ```

## Option B: run on the phone itself with Termux (Android 11+)

1. Install **Termux** from F-Droid (the Play Store version is outdated).
2. In Termux: `pkg install android-tools git`
3. Open **Developer options > Wireless debugging > Pair device with pairing code**.
   Use split screen so Termux and Settings are both visible, then in Termux run:
   ```
   adb pair localhost:<pairing port> <pairing code>
   adb connect localhost:<port shown on the Wireless debugging screen>
   ```
4. Get the scripts and run them:
   ```
   git clone https://github.com/nicholasjensen/arduino.git
   cd arduino/android-optimize
   bash phone-optimize.sh apply
   ```
   Wireless debugging turns off after a reboot or Wi-Fi change; repeat the `adb connect` step next time.

## Restricting battery-hungry apps

1. See what's installed: `adb shell pm list packages -3`
2. Check what uses the most battery: **Settings > Battery > Battery usage**.
3. Put those package names in `restrict-apps.txt`, one per line, then run `./phone-optimize.sh restrict-apps`.

Restricted apps can only run while open, so their notifications may arrive late.
Don't list messaging, alarm, or email apps you rely on.
