# macos monitor switcher 

For switching focus between displays by moving the mouse to the adjacent display and clicking there.

- `Ctrl+Shift+Left`: switch to the display on the left
- `Ctrl+Shift+Right`: switch to the display on the right

This was created because `Cntrl-Left/Right` can be used to switch between windows, but there is no native command to swap between displays so some windows are unavailable.

## Build

```sh
./build.sh
chmod +x ./displaykeys
```

## Usage

```sh
./displaykeys open
./displaykeys left
./displaykeys right
./displaykeys quit
```

## Notes
- The app needs `Accessibility` permission in `System Settings > Privacy & Security > Accessibility`.
