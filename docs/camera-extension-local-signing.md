# Camera extension — local signing test lane

This build ships a real CMIO camera system extension, built and signed locally
without an Apple Developer team. It appears in **System Settings › General ›
Login Items & Extensions › Camera Extensions** once macOS has accepted the
system extension.

## What is in the repo

| Piece | Path |
| --- | --- |
| CMIO extension source | `macos/CameraExtension/` |
| Extension Info.plist | `macos/CameraExtension/Info.plist` |
| Extension entitlements | `macos/CameraExtension/CameraExtension.entitlements` |
| Host activation entitlement | `macos/CameraExtension/Host.entitlements` |
| Local identity bootstrap | `scripts/bootstrap-local-signing.sh` |
| Build + embed + sign | `scripts/build-camera-extension.sh` |
| Install + sign host | `scripts/install-local-camera-extension.sh` |
| Diagnostics | `scripts/diagnose-camera-extension.sh` |

The extension currently emits a **moving colour-bar test pattern at 1280×720,
30 fps**. This is intentional: it verifies the signed system-extension install
and the CMIO video path end-to-end. Android frame delivery is the next layer and
does not change the CMIO/activation plumbing.

## One-time machine setup

Self-signed system extensions are a developer-only path. macOS requires both:

1. **Reduce SIP** in Recovery Terminal, then reboot:

   ```sh
   csrutil enable --without kext --without debug
   ```

2. **Enable developer mode** for system extensions:

   ```sh
   sudo systemextensionsctl developer on
   ```

A paid Apple Developer ID + notarization removes these two requirements for
distribution, but is not needed for this local test lane.

**Important:** with SIP fully enabled, macOS also refuses to launch the
locally-signed host because `com.apple.developer.system-extension.install` is a
restricted entitlement. Use the normal build/run for ordinary app testing and
the SIP developer lane only when testing the camera extension.

## Build, sign, install

```sh
# Creates the "AndroLaunch Local Dev" identity in your login keychain the first
# time; subsequent runs reuse it.
scripts/install-local-camera-extension.sh Release
```

The script:

1. builds the host app and the extension;
2. signs the extension with `com.apple.security.app-sandbox` and the shared
   `group.com.senpai.AndroLaunch` application group;
3. signs the host with `com.apple.developer.system-extension.install`;
4. installs to `/Applications/AndroLaunch.app` owned by `root:wheel`.

Then:

1. Open AndroLaunch.
2. Go to **Device › Camera Extension** (or Settings › Camera).
3. Click **Install extension**.
4. Approve it in **System Settings › Login Items & Extensions › Camera
   Extensions**.

Verify:

```sh
scripts/diagnose-camera-extension.sh
systemextensionsctl list | sed -n '/cmio/,+6p'
```

Open FaceTime/Zoom/QuickTime and select **AndroLaunch Camera**.

## Why the extension is not present in normal builds

Xcode's automatic signing refuses the host entitlement, and macOS refuses to
activate an unsigned/self-signed extension unless the SIP developer lane above is
enabled. Normal `scripts/build-macos.sh` builds therefore remain ad-hoc signed
and the app shows the honest **Not available / Install** state.

## Signing identity stability

The identity CN is `AndroLaunch Local Dev` by default. Keep it stable: macOS TCC
and sysextd remember the certificate CN. Override with
`ANDROLAUNCH_SIGNING_IDENTITY` only if you intentionally re-bootstrap.
