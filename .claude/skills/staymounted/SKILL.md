---
name: staymounted
description: Drive StayMounted, the menu bar app on this Mac that keeps SMB network shares mounted, from the shell with the `staymounted` command: see which shares are mounted and why one isn't (its last error), add or stop watching a share, mount, unmount or remount one now, and pause or resume keeping shares mounted. Use when the user asks about their network shares, NAS or server volumes being mounted, or names StayMounted.
---

# StayMounted

`staymounted` runs commands in the StayMounted app. Changes show in its menu bar panel at once.
If the app is closed, the command opens it in the background. If `staymounted` isn't on PATH, use
`/Applications/StayMounted.app/Contents/MacOS/StayMounted` the same way.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and
  `error.message`, and do what the message says.
- Name a share by its 8-character id from `staymounted shares list` (any unique start works) or by
  its share name.
- Never ask for, pass or print a password. StayMounted uses the one Finder saved in the keychain.
  For `needs_sign_in`, the person connects once in Finder (Go > Connect to Server) and saves the
  password, or you run `shares mount <share> --sign-in` only when they asked, and they type it.
- `shares remove`, `shares unmount` and `shares remount` only report what they would do. Show the
  user that report and ask before you run it again with `--yes`: unmounting takes files away from
  apps that have them open. Mounting and pausing touch the real network shares too; run them only
  when the user asked.
- Mounting and unmounting finish in the background: check with `shares show <share>` afterwards.
- To try something without real shares, run a Debug build with `APP_STORE=/tmp/staymounted-test`
  in front; that copy never mounts or unmounts anything.

## Main commands

| Command | Does |
| --- | --- |
| `staymounted status --json` | Paused or not, shares watched, mounted and needing attention |
| `staymounted shares list [--state mounted\|not-mounted\|attention\|paused] --json` | Each share: server, mounted or not, state, last error |
| `staymounted shares show <share> --json` | One share in full, with the apps it opens when mounted |
| `staymounted shares mount <share> --json` / `shares mount --all --json` | Mount now, or every missing share |
| `staymounted shares unmount <share> [--yes] --json` | Unmount and pause it; `shares resume` brings it back |
| `staymounted pause --json` / `staymounted resume --json` | Stop or restart keeping every share mounted |

Everything else (`mounts list`, `shares add`, `shares remove`, `shares remount`, `shares pause`,
`open`): `staymounted help`, and `staymounted help <command>` for its options.
