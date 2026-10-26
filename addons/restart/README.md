# Restart TV

A one-tap restart for Android TV and Google TV: press the tile on the launcher home screen and the
system power dialog (Restart / Cancel) appears immediately over whatever is on screen. Navigate with
the D-pad and confirm with OK.

Package `io.github.tko76.restarttv`. You see it as **Restart** on the cleanyourtv launcher, where it
also shows as a module card.

## How it works

An ordinary app cannot trigger the system power dialog directly. This add-on uses an Android
accessibility service to call `GLOBAL_ACTION_POWER_DIALOG` — the same action the system uses
internally when you long-press the physical power button. The service asks for no key events and
reads no window content; its only job is this one action, fired the moment the tile is tapped.

This is identical in approach to the Sleep Timer add-on, which uses `GLOBAL_ACTION_LOCK_SCREEN`
for standby.

`GLOBAL_ACTION_POWER_DIALOG` is available on Android 5.0 (API 21) and later.

## Install

```sh
TV_HOST=<tv ip> addons/restart/build-and-install.sh
```

The script builds the APK, pushes it over ADB, installs it and enables the accessibility service
in one step. No on-screen confirmation is needed.

## Uninstall

```sh
TV_HOST=<tv ip> addons/restart/build-and-install.sh --uninstall
```

## Note on the first launch

If the accessibility service is not yet enabled (e.g. the TV rebooted before the service bound),
tapping the tile opens Accessibility Settings instead of the power dialog. Enable **Restart TV
(power dialog)** there, then press the tile again. The `build-and-install.sh` script handles this
automatically at install time.
