# ScanFlow 0.4.24 — ten new Liquid Glass icons

Date: 2026-11-07
Production app/assets source: b8ed1963794970e067de4c8c6d51aabd8b956e4d, build 46. Subsequent changes are limited to this report and screenshot-runner cleanup/time limits.

Collection: Prism, Stack, Lens, Ribbon S, Portal, Folio, Orbit, Wave, Archive, Facet. These are ten different vector silhouettes, not ten recolors. Each .icon package contains separate native glass optical groups. The four previous choices remain available; existing system icon selection is preserved. The picker shows the new collection first. IconCollection.json, Swift case names, compiler alternate-icon settings and package manifests are cross-checked.

GitHub Actions run 42400058046: device build job 128485684630 passed, artifact 13585750483 (ScanFlow-0.4.24-build46). Scanner core, 16 display-name assertions, native Vision direction checks, ZIP/Ukrainian filename checks, icon resource references, Release compilation and package metadata assertions passed. The actual IPA contains one primary icon, exactly 13 alternate icon names and 14 native-compiled preview PNGs. All ten new preview image digests are distinct. All ten source layer-one silhouettes are distinct and SVG files parse correctly.

IPA: 32,974,873 bytes; SHA-256 1fa125db68c4b7b64db4d981d89e7f52c96f073e386982c2468f56e01790d695. Outer artifact digest was checked before extracting it. Bundle identifier and file-sharing settings remain correct. The contact sheet is assembled from actual compiler-generated fallback images extracted from this IPA, masked like the picker thumbnails, with no alternate hand-drawn icon artwork.

Visual evidence: preview artifact 13585059654 from the same source/run. Manually inspected icons-prism-large.png, icons-portal-large.png, icons-archive-large.png and icons-prism-accessibility-large.png. All ten new images appear in the scrolled native picker. Labels fit, previous icons remain visible at the bottom, and accessibility-large uses a single-column scroll layout with card contents fitting. Preview image digest: 418ac8e231b944a38cdce6a8c4a0f9507234663a034f9fbc59e52b13efc2f421.

The preview job is marked cancelled: it reached its 15-minute limit after all four screenshots were captured, while shutting down the simulator. Logs show the last successful capture at 18:27:03 UTC, followed by cancellation at 18:27:16 UTC. This is not recorded as an entirely green preview workflow. Cleanup now has a 15-second timeout and the preview job has a 20-minute budget; Python syntax validation passed. These test-harness-only changes do not require rebuilding the delivered app.

The production icon-switch API/handler is unchanged from 0.4.23. Actual Home Screen icon switching and optical effects on a physically signed iPhone remain unverified; the prior automatic simulator switch probe timed out. No successful physical-device or automatic switch test is claimed.

Result: app build, icon package verification and manual native gallery visual checks passed; physical Home Screen switching remains unverified.
