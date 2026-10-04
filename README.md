# StayMounted

**Keeps your Mac's network shares mounted, and opens the apps that depend on them.**

macOS forgets file shares all the time. They drop after sleep, when Wi-Fi changes, or when a
NAS reboots, and they are not there after a restart unless you reconnect by hand. Anything that
reads from the share then fails: a media library, a photo catalog, a backup tool, a project
folder. StayMounted is a small menu bar app that notices when an SMB share goes missing and
quietly puts it back. It can also open your apps once the share is there.

---

## ⬇️ Download

<p align="center">
  <a href="https://github.com/smanke-org/StayMounted/releases/latest/download/StayMounted.dmg">
    <img src="https://img.shields.io/badge/Download-StayMounted.dmg-2ea44f?style=for-the-badge&logo=apple&logoColor=white" alt="Download StayMounted.dmg" height="48">
  </a>
</p>

1. **[Download StayMounted.dmg](https://github.com/smanke-org/StayMounted/releases/latest/download/StayMounted.dmg)**
2. Open it and drag **StayMounted** to **Applications**.
3. Open StayMounted from Applications. Its icon appears in the menu bar. Click it and choose a share to keep mounted.

Requires macOS 26 or later. Signed with Developer ID and notarized by Apple.

---

## How it works

- **Pick what to keep mounted.** Shares that are mounted now appear in the menu with a
  *Keep Mounted* button. You can also type an address such as `smb://nas.local/Media`.
- **Uses the password you already saved.** StayMounted stores no passwords. It mounts through
  macOS the same way Finder does, using the Keychain entry Finder saved when you ticked
  *Remember this password*. If there isn't one, the share shows *Sign In…*, which opens the
  standard macOS sign-in sheet once.
- **Quiet when you're away.** Before mounting, it checks that the server is answering, so
  being off your home network or VPN never produces error dialogs. It tries again as soon as
  the network changes.
- **Starts at login.** StayMounted turns on *Open at Login* the first time it runs from
  Applications, so your shares are back after every restart. You can turn it off in the menu.

## Features

- **Open apps when a share mounts.** Choose *Open When Mounted…* from a share's ⋯ menu and
  add apps. They open in order every time the share mounts: at login, and again after sleep
  or a network drop. Apps that are already open are left alone. Each app can open hidden, and
  each share can wait a few seconds before opening its apps.
- **Respects Eject.** If you eject a share yourself, a small panel counts down ten seconds
  before remounting it. Its *Keep ejected* button pauses that share until you resume it.
  Shares lost to sleep or a network change come back without asking.
- **Pause anytime.** Pause a single share, or all of them, from the menu.
- **Dock, menu bar, both or neither.** **Show in Dock** and **Show in Menu Bar** in the menu's
  footer pick where StayMounted appears. Right-click the Dock icon for **Settings…**, which
  opens the menu's panel in a window. With both off, StayMounted keeps working with no icon.
  Open it again from Applications or Spotlight to get the panel back.

## Updates

StayMounted checks GitHub for a new release shortly after it starts. If there is one, the
menu shows *Update to …*, and it installs only when you click that item. You can also choose
*Check for Updates…* at any time, or turn off *Check for Updates at Launch*.

Before installing, StayMounted makes sure the download is signed by the same developer and
notarized by Apple. It updates the app in place, so your settings and permissions carry over.

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
