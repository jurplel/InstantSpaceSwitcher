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

### Downloads

Pre-built binaries are available through Github Releases [here](https://github.com/jurplel/InstantSpaceSwitcher/tags).

### Build from source

```sh
git clone https://github.com/jurplel/InstantSpaceSwitcher
cd InstantSpaceSwitcher
./dist/build.sh
open ./build/InstantSpaceSwitcher.app
```

### Code Signing Workaround

MacOS wants applications to be code signed, but this project is not.

To work get around the warning:

```
xattr -cr /path/to/InstantSpaceSwitcher.app
```

or, you can:

1. go to System Preferences
2. go to Security & Privacy
3. go to General,
4. scroll and find "Open Anyway" for InstantSpaceSwitcher.

## Background

When I first bought a high refresh rate monitor, around ~2018, I could tell that the space switching animation was longer because it had scaled with the refresh rate. Because of this, I eventually stopped using spaces altogether, and have been looking for a solution ever since.

The workaround in this project is to create a synthetic trackpad gesture with an artificially high velocity. This effectively skips the animation.

If you work at Apple, and your team owns the space switching animation, please fix this long-standing bug (and let us disable the animation natively, please).

```

```
