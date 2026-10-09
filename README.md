# ThinkPad Backlight

An Omarchy bar widget for the ThinkPad keyboard backlight: click to toggle, right-click for brightness and a sundown schedule.

![ThinkPad Backlight menu](preview.gif)

- **Click:** on or off, back at the level you last used.
- **Right-click:** menu with three keyboard icons (dark, dim, bright) for off, low and high, and a "Turn on at sundown" switch.
- **Sundown mode:** on 20 minutes before sunset, off at sunrise. The location comes from your timezone's main city, so it follows you when you travel and stores no coordinates.
- **Below the switch:** shows when the backlight goes on and off. Type a time (7:00 PM, 7pm or 19:00) to override either side; **Automatic** puts both back on sunset and sunrise for your timezone.
- Clicks win until the next switch. Remembers low or high.
- Follows Fn+Space.
- Rename the location label with `omarchy bar set remi.kbdlight placeName "Home"`.

## Requirements

- A ThinkPad (`tpacpi::kbd_backlight`)
- `brightnessctl`
- A system timezone (for sundown mode)

## Install

```
omarchy plugin add https://github.com/remigius-labs/omarchy-thinkpad-backlight --enable
```

## Limits

- ThinkPads only for now (`tpacpi::kbd_backlight`), with off / low / high.
- Sundown times use your timezone's main city, so they can be off by about 20 minutes.

## License

MIT
