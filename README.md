# PixelRemote

A modern remote-desktop client for **macOS, Windows and Linux**, written in Flutter.
Type an SSH address, and PixelRemote carries VNC (RFB) through an encrypted SSH
tunnel, the way `vncviewer -via` does, so the only port that needs to be reachable is SSH.

## Features

- **One-field connect**: `user@host:port`, `ssh://…`, IPv6 `[::1]:22`, or any alias from `~/.ssh/config`
  (`HostName`, `User`, `Port`, `IdentityFile`, `IdentityAgent`, wildcards and `!` negation).
- **SSH auth**: ssh-agent (macOS/Linux), key files (passphrases asked only if the server accepts the key),
  password and keyboard-interactive/2FA prompts.
- **Host keys**: trust-on-first-use with a fingerprint dialog. Honours your OpenSSH `known_hosts`
  (including hashed entries) and refuses changed keys.
- **Stream control, live**: quality presets (Tight JPEG levels or lossless), frame rate
  **15/30/60/75/90/120/144/165**, resolution (server default, match window, or fixed presets via
  ExtendedDesktopSize), colour depth (24/16/8-bit), and a **bandwidth cap**. Frames are pulled one at a
  time and paced by a token bucket, so the stream never exceeds the frame rate or the cap.
- **Floating stats panel** (draggable): latency (SSH round trip), packet loss (unanswered probes),
  down/up throughput with a sparkline, delivered vs. target fps, resolution.
- **Keyboard mapping between macOS and PC**: automatic (detects the remote OS over SSH), off,
  Ctrl ⇄ ⌘, or Alt ⇄ ⌘. Keys are released safely on focus loss.
- **Clipboard sync** in both directions, UTF-8 via the Extended Clipboard extension (CJK-safe),
  falling back to Latin-1 cut text on older servers.
- Local rendering of the remote cursor (no cursor lag), trackpad and wheel scrolling,
  Ctrl+Alt+Del and other key combos, full screen.
- **English (US) and 简体中文**, light/dark themes.

## Remote host setup

Run any VNC server bound to **localhost** on the remote machine; the SSH tunnel does the rest. With
the tunnel providing encryption, security type *None* or *VncAuth* is fine.

| Remote OS | Example |
|---|---|
| Linux (existing X session) | `x0vncserver -localhost -SecurityTypes None -display :0` (TigerVNC) or `x11vnc -localhost -display :0 -nopw -forever` |
| Linux (virtual desktop, resizable) | `vncserver :1 -localhost yes -SecurityTypes None` → VNC port **5901** |
| macOS | System Settings → Sharing → Screen Sharing → enable *VNC viewers may control screen with password* |
| Windows | TightVNC / UltraVNC, with *Allow loopback connections* / *Loopback only* enabled |

Alternatively, put the server's launch command in **Advanced options → Start command**. PixelRemote runs it
over SSH and waits for the port to come up.

## Architecture

Layered, programmed to interfaces, with dependencies pointing inward:

```
presentation ─► application ─► domain ◄─ data
       ╲                               ╱
        └──────── app (composition root) ┘
```

| Layer | Responsibility | Depends on |
|---|---|---|
| `lib/domain` | Entities (`ConnectionProfile`, `StreamSettings`, `KeyRemapper`…), ports (`TunnelConnector`, `RemoteDesktopProtocol`, `UserInteraction`, repositories), `RemoteException` | nothing (pure Dart) |
| `lib/application` | Use case `ConnectSession`, `SessionMonitor`, controllers (Riverpod `Notifier`s), **commands** | domain, `core` |
| `lib/data` | dartssh2 tunnel, ssh_config/known_hosts/agent, RFB client (handshake, Raw/CopyRect/ZRLE/Tight decoders, pacer, clipboard), storage | domain |
| `lib/presentation` | Theme, l10n, pages and widgets, keyboard translation, dialog-based `UserInteraction` | application, domain |
| `lib/app` | `compositionRoot()`: the only file that binds ports to concrete classes | all |

- **Dependency inversion**: `application/providers.dart` declares ports that throw until bound;
  `app/composition_root.dart` binds them. Tests bind in-memory fakes the same way.
- **Command pattern**: every viewer action is a `Command<RemoteDesktopSession>` (`KeyCommand`, `PointerCommand`,
  `ScrollCommand`, `ApplySettingsCommand`, `ResizeCommand`, …), dispatched through one `CommandInvoker`.
- **Strategies**: each RFB encoding is a `RectDecoder`; JPEG decoding is a `JpegCodec` port (engine codec in the app).

Libraries: [dartssh2](https://pub.dev/packages/dartssh2) (SSH), [Riverpod](https://riverpod.dev) (state/DI),
[window_manager](https://pub.dev/packages/window_manager), [google_fonts](https://pub.dev/packages/google_fonts),
[pointycastle](https://pub.dev/packages/pointycastle) (DES, hashes), `shared_preferences`, `flutter_localizations`.

## Build and run

```bash
flutter pub get
flutter run -d macos     # or: -d windows, -d linux
```

- **Linux** build hosts need `libgtk-3-dev libx11-dev libxi-dev`.
- **macOS**: the app runs un-sandboxed (like other SSH clients) so it can read `~/.ssh` and reach ssh-agent.

## Tests

```bash
flutter test                                               # unit + RFB protocol round-trip tests
SCREENSHOT_DIR=/tmp/shots flutter test test/presentation/screenshots_test.dart   # render UI to PNGs
E2E_SSH=user@host flutter test test/e2e                     # real SSH + RFB against a live host
```

## Known limitations

- RFB has no H.264. Bandwidth is controlled with JPEG quality, colour depth, frame pacing and the cap.
- ssh-agent on Windows (named pipe) isn't supported yet; key files and passwords work.
- macOS's Apple-only auth (RFB type 30) isn't supported; use the VNC-password option.
- Packet loss is estimated from SSH keep-alive probes (TCP hides real loss from applications).
- The stats panel floats inside the window rather than as a separate OS window.
