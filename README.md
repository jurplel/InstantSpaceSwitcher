# InstantSpaceSwitcher

Native instant workspace switching on macOS. No more waiting for animations.

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

## macOS 27 compatibility

macOS 27 requires a serialized IOHID payload on synthetic space-switch gestures.
This build adapts the [upstream macos-27 patch](https://github.com/jurplel/InstantSpaceSwitcher/tree/macos-27),
with build/preference-dependent direction selection informed by
[Space Rabbit's measurements](https://github.com/Tahul/space-rabbit/issues/54).
Physical swipe direction remains unchanged.

On current macOS 27 builds, synthetic direction follows **Natural scrolling**.
Early beta seeds (26A5000 through 26A5415) always use inverted synthetic signs.
If Natural scrolling changes while Dock is running, its cached setting may differ
from the preference until Dock restarts. Do not change this preference during testing.
These are private event formats and may change in future OS updates.

On macOS 27, Changed/Ended carry full progress to complete the transition immediately;
the existing animation-speed presets may no longer produce distinct durations.
Older macOS versions retain their original event recipe.

### Event-layer tests

These tests need only Command Line Tools, not XCTest. They construct and inspect
events without posting them, including both direction conventions and fixed-point bounds.

```sh
clang -Wall -Wextra -Werror -fsanitize=undefined,float-cast-overflow \
  -o /tmp/iss-event-tests Tests/ISSNative/EventTests.c \
  Sources/ISS/ISS.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit
/tmp/iss-event-tests
```

For a live check, quit other space-switching utilities and leave the pointer on the
display being tested. The following moves to an adjacent space and back, verifies
the actual indices, and stops on mismatch. It requires Accessibility permission
and at least two spaces. Repeat on each display and beside a fullscreen app.

```sh
ISS_TEST_LIVE=1 /tmp/iss-event-tests
```

The live check exercises synthetic events with swipe interception enabled, but
physical trackpad swipes and visual glitches still need manual verification.
`ISS_FORCE_EVENT_AUGMENTATION=0` disables the new payload for baseline comparisons;
`=1` forces it on. Omit the variable for automatic OS detection.

## Background
When I first bought a high refresh rate monitor, around ~2018, I could tell that the space switching animation was longer because it had scaled with the refresh rate. Because of this, I eventually stopped using spaces altogether, and have been looking for a solution ever since. 

The workaround in this project is to create a synthetic trackpad gesture with an artificially high velocity. This effectively skips the animation. Space-switch requests are serialized and confirmed through `NSWorkspace.activeSpaceDidChangeNotification` before another gesture is injected or the OSD is shown.

Transition diagnostics are available in unified logging:

```sh
log stream --style compact --predicate 'subsystem == "com.interversehq.InstantSpaceSwitcher" AND category == "space-transition"'
```

If you work at Apple, and your team owns the space switching animation, please fix this long-standing bug[^2] (and let us disable the animation natively, please).

[^1]: This happens because the app is not signed, which requires a costly Apple Developer account
[^2]: And I know for a fact there is a rdar for this

