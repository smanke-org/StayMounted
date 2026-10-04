# StayMounted

A macOS menu bar app that keeps your SMB file shares mounted. It mounts them when you log in,
remounts them after sleep or a network drop, and brings them back if they are ejected.

[**Download the latest release**](https://github.com/smanke-org/StayMounted/releases/latest/download/StayMounted.dmg)

## How it works

- **Pick what to keep mounted.** Shares that are mounted now appear in the menu with a
  *Keep Mounted* button, or type an address such as `smb://nas.local/Media`.
- **Uses the password you already saved.** StayMounted stores no passwords. It mounts through
  macOS the same way Finder does, using the Keychain entry Finder saved when you ticked
  *Remember this password*. If there isn't one, the share shows *Sign In…*, which opens the
  standard macOS sign-in sheet once.
- **Quiet when you're away.** Before mounting, it checks that the server is answering, so
  being off your home network or VPN never produces error dialogs. It tries again as soon as
  the network changes.
- **Respects Eject.** If you eject a share yourself, a small panel counts down ten seconds
  before remounting it, with a *Keep ejected* button that pauses that share until you resume
  it. Shares lost to sleep or a network change come back without asking.
- **Pause anytime.** Pause a single share, or all of them, from the menu.

Requires macOS 26 or later.
- **Dock, menu bar, both or neither.** **Show in Dock** and **Show in Menu Bar** in the menu's
  footer pick where StayMounted appears. Right-click the Dock icon for **Settings…**, which
  opens the menu's panel in a window. With both off it keeps working with no icon; open it
  again from Applications or Spotlight to get the panel back.

## Building

```bash
./build_app.sh            # GitHub build: self-updating, Developer ID signed
./install.sh              # copy to /Applications and launch
./build_app.sh --appstore # sandboxed Mac App Store flavour, updater compiled out
swift test                # unit tests for StayMountedKit
```

`./release.sh <version>` builds, notarizes, packages and publishes a GitHub release.

Diagnostics are written to `~/Library/Logs/StayMounted.log`. Set `STAYMOUNTED_UI_PREVIEW=1`
to open the menu's contents in an ordinary window.
