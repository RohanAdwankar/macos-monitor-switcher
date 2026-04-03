# DisplayKeys

Minimal macOS app plus command wrapper for switching focus between displays by moving the mouse to the adjacent display and clicking there.

Global shortcuts while the app is open:

- `Ctrl+Shift+Left`: switch to the display on the left
- `Ctrl+Shift+Right`: switch to the display on the right

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

- `open` launches the menu bar app so you can verify it is actually running.
- While the app is open, `Ctrl+Shift+Left` and `Ctrl+Shift+Right` trigger the same behavior.
- `left` and `right` directly move the pointer onto the adjacent display and click there.
- `quit` only closes the menu bar app started by `open`.
- The app needs `Accessibility` permission in `System Settings > Privacy & Security > Accessibility`.
