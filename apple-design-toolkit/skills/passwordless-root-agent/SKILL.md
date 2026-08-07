---
name: passwordless-root-agent
description: Give a macOS app password-free privileged operations safely — a root LaunchDaemon watching a spool directory executes a fixed whitelist of bare verbs, installed with one GUI admin prompt. No sudoers edits, no injection surface. Use when an app needs repeated root actions (pmset, powermetrics, purge) without prompting every time.
---

# Password-Free Root Operations (Spool-Agent Pattern)

Replace per-action sudo prompts with ONE install-time admin prompt. No visudo, no NOPASSWD, no SMJobBless complexity.

## Architecture

1. **Root agent script** at `/Library/Application Support/<App>/agent.sh` — owned `root:wheel`, mode 755. NEVER let root execute a user-writable file (that's privilege escalation); the installer copies it out of the app bundle into the root-owned dir.
2. **Spool dir** `<support>/spool` — mode **1777** (sticky, world-writable, like /tmp). The app drops `req-<id>` files; the agent replies with `done-<id>` (chmod 644 so the app can read).
3. **LaunchDaemon plist** in `/Library/LaunchDaemons/` with `WatchPaths=[spool]` + `RunAtLoad` — fires on every spool write; launchd throttles bursts (~10 s), which is fine.
4. **Installer** runs once via `osascript -e 'do shell script "…" with administrator privileges'`: mkdir, cp, chown/chmod, write plist (root:wheel 644), `launchctl bootout system/<label> 2>/dev/null; launchctl bootstrap system <plist>`.

## The security invariant: bare verbs only

Request files contain a single whitelisted verb and NOTHING else:

```zsh
verb=$(head -1 "$req" | tr -cd 'a-z')   # strip everything but lowercase
rm -f "$req"
case "$verb" in
  tune) …fixed pmset commands… ;;
  deep) OUT="$REPORTS/scan-$(date +%Y%m%d-%H%M%S).txt"; …fixed pipeline > "$OUT"… ;;
  *) log "ignored unknown request" ;;
esac
```

No arguments accepted ⇒ nothing in the world-writable spool can inject paths, options, or commands. Output paths are constructed BY the agent, never read from the request. Sanitize the reply id: `id="${id//[^a-zA-Z0-9]/}"`. Sweep stale `done-*` with `find -mmin +5 -delete`.

## App side

```swift
try verb.write(toFile: "\(spool)/req-\(id)", atomically: true, encoding: .utf8)
// poll "\(spool)/done-\(id)" every 0.4 s up to a deadline; contents = "ok" or a report path
```
Detect installed state: plist exists AND `isWritableFile(atPath: spool)`. Fall back to the GUI-prompt path when absent — and make that fallback ALSO install the agent in the same single prompt ("last password ever" UX).

## Companion pattern: root telemetry governor

Same install, second daemon on `StartInterval=60`: read battery gauge via `ioreg -rn AppleSmartBattery` (top-level keys only — nested dicts repeat key names; InstantAmperage is unsigned two's-complement: subtract 2^64 if > 9.2e18), Kalman-filter the wattage in awk (persist state in a root-owned file), act via `pmset -a lowpowermode` directly — root daemons need no sudo. Uninstall: bootout both daemons, rm plists + support dir.
