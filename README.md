# InstantSpaceSwitcher

Native instant workspace switching on macOS. No more waiting for animations.

This local build defaults to **Fast**, to keep a visible sliding transition.
This default applies to both the app and CLI. Adjust it in the app under
**Settings → Animation**. This tab includes a live curve graph, speed presets, a custom duration slider (**80–1000 ms**), and separate
**Ease in** / **Ease out** sliders (**0–50%** of the slide time each).
Curve presets are **Gentle** (the current 10%/10% curve), **Linear**, **Ease In**,
**Ease Out**, and **Smooth**. Changes save automatically and apply to the next
slide. **Gentle** with **Fast** uses the accepted 220 ms behavior.
Instant disables curve controls; select another speed to edit them.
Animated presets now drive swipe progress over a fixed interval, with constant
speed through the middle 80% and brief easing at either end. The target durations
are Normal **275 ms**, Fast **220 ms**, Faster **183 ms**, and Fastest **138 ms**.
Instant retains the original immediate gesture. Saved speed preferences still apply.
The gesture now uses a travel of **2.0**, leaves one update interval before
release, and releases at rest. The first trial used travel 1.0 followed by a
high-velocity finish; on macOS 26.6.2 this visibly slid only partway and then
accelerated abruptly. Do not treat the gesture travel field as a normalized
screen position or restore the high-velocity finish for ordinary slides.
The revised travel and at-rest release were visually accepted on this machine;
the travel calibration remains experimental on other macOS versions.
The durations above describe the gesture; the Dock renders the actual animation.
Physical trackpad gestures retain their normal behavior unless **Override swipe
gesture** is enabled. Repeated shortcuts finish the current slide before starting
the next; direct jumps skip intermediate slides and animate the final step.

For **Control + Left/Right**, assign those shortcuts in the app's Keyboard tab
and disable macOS's competing **Move left a space** / **Move right a space**
shortcuts in **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**.
Otherwise the native shortcuts may retain the normal animation regardless of the
app's speed setting. Re-enable them there if you stop using this app.

Command-Tab retains the native macOS chooser. **Settings → General → Use animation
settings when switching apps** applies the selected slide to cross-Space app
activation, including Command-Tab and Dock clicks. It is enabled by default.
The app observes activation, resolves the focused window's Space and display,
and posts the existing asynchronous swipe. Keyboard input is never held or
replayed. Window lookup runs on a background queue with a short Accessibility
timeout; rapid selections discard stale lookups.
Physical Space swipes and Control-arrow navigation suppress activation following
while the desktop settles, so the new focus cannot undo a manual Space change.
An explicit Command-Tab selection or mouse click clears that suppression.

While enabled and Accessibility is granted, the app temporarily turns off
**System Settings → Desktop & Dock → When switching to an application, switch to
a Space with open windows** so the native jump does not race the slide. Dock
rebuilds its own WindowServer workspace preferences from that setting; Dock is
not restarted. The original value is recorded and restored when the option is
disabled or the app quits; a separate helper restores it if the app crashes, and
the next launch restores anything still left over. An earlier build set a
partial WindowServer session preference instead, which discarded Dock's other
workspace keys and broke the Mission Control window layout. This has been tested
on macOS 26.6.2. The earlier approach that held and replayed Command release was
removed because it caused sticky or unresponsive keyboard input.

https://github.com/user-attachments/assets/037422c9-3fb7-41cd-8da7-58d28c4c8eff

## Features

- Does not require disabling SIP
- Uses native macOS spaces
- Free

A simple CLI is provided (`InstantSpaceSwitcher.app/Contents/MacOS/ISSCli --help`)


## Installation

### Homebrew

```sh
brew install --cask jurplel/tap/instant-space-switcher
```

After installation the app is located inside `/Applications/InstantSpaceSwitcher.app`


### Downloads

Pre-built binaries are available through Github Releases [here](https://github.com/jurplel/InstantSpaceSwitcher/tags).

### Build from source

```sh
git clone https://github.com/jurplel/InstantSpaceSwitcher
cd InstantSpaceSwitcher
./dist/build.sh
open ./build/InstantSpaceSwitcher.app
```

### Troubleshooting / First time startup

1. When opening the app the first time you are likely to run into any of the following warnings:

> "Apple could not verify InstantSpaceSwitcher.app is free of malware"

> "App is damaged and can’t be opened"

> "App can't be opened because the developer cannot be verified"

Please follow the instructions [here](https://wiki.hacks.guide/wiki/Open_unsigned_applications_on_macOS_Sequoia_and_newer) for instructions on how to allow the app to run[^1].

2. Afterward you will get a warning that InstantSpaceSwitcher wants to use accessibility features. You have to allow this.

3. Then open the app from the Applications folder and the configuration window should appear.

## Background
When I first bought a high refresh rate monitor, around ~2018, I could tell that the space switching animation was longer because it had scaled with the refresh rate. Because of this, I eventually stopped using spaces altogether, and have been looking for a solution ever since. 

The workaround in this project is to create a synthetic trackpad gesture with an artificially high velocity. This effectively skips the animation.

If you work at Apple, and your team owns the space switching animation, please fix this long-standing bug[^2] (and let us disable the animation natively, please).

[^1]: This happens because the app is not signed, which requires a costly Apple Developer account
[^2]: And I know for a fact there is a rdar for this
