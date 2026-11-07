# ScanFlow 0.4.23 — selectable Liquid Glass app icons

Date: 2026-11-07
Production source: 515ce9f3db5d81f21c8a688caef77ac780c75b81; build 45.

Implemented: Appearance > App icon; three native Icon Composer icons (teal, pearl, graphite) plus the prior scanner artwork. New icons contain separate glass document, capture-frame and detail groups. Selection uses UIApplication.setAlternateIconName; the selected state is read from UIApplication, updates after returning to the app, and is not advanced on error. Duplicate requests are disabled while pending. Release builds exclude the simulator probe and preview launch route.

The compiler emits alternate icons in Assets.car without normal UIImage-accessible PNGs. scripts/render_icon_previews.py compiles each actual .icon package separately and copies only its static fallback thumbnail to the built app. Both device and simulator workflows run this step before packaging/installing. For manual builds, run that script with the matching --platform and --app output path before installing. Do not hand-draw replacement previews or edit generated CFBundleIcons.

Validation: GitHub Actions run 42396504450. Device artifact 13584170893 (ScanFlow-0.4.23-build45); preview artifact 13584565934. Device Release and simulator Debug builds passed. Scanner core, 16 document display-name assertions, native Vision direction checks, ZIP integrity and Ukrainian filename checks passed. Generated plist contains the primary and exactly three alternate icon names. All four thumbnails are present, distinct, and were visually inspected from the IPA. Bundle identifier and file sharing remain correct.

IPA: 12,768,567 bytes; SHA-256 23fe15868461279534f6fba4c7075714e037f943bf1166aad747831e83a114d2.

Native screenshots inspected: icon-picker.png and icon-picker-large-text.png, iPhone 15 Pro simulator. All four actual previews render in the ordinary two-column layout. Accessibility-large switches to a single-column scroll layout; visible card contents fit. Earlier missing alternate thumbnails were detected in native captures and corrected before delivery.

Runtime limitation: the automatic icon-switch probe in the simulator did not return within 90 seconds (icon-switch-verification.json: simulator-timeout). An earlier probe reported supportsAlternateIcons=true but was cancelled by the simulator. These are NOT successful Home Screen switch tests. A real signed iPhone install is still required to verify the system confirmation and icon change. Production error handling remains in place; no private APIs or silent icon changes are used.

Result: build, package and picker visual checks passed; actual Home Screen switching is unverified on a physical iPhone.
