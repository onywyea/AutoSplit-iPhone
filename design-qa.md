# ScanFlow 0.4.22 visual QA

Scope: centered home subject, description and Continue action; circular appearance wordmark; selected glass scanner app artwork.

final result: pending

# ScanFlow 0.4.21 home hero — visual QA

Date: 2026-11-07

Visual target: second displayed concept, with a three-page fan, left-aligned readable document identity and Continue action. Native iOS chrome adapts to the device rather than reproducing image-generated system chrome.

Production app source: 78e8cef6c640a3f152ae312b86122165dedfe211. Preview source: cca1abb9f6573aacc20957298c0681df8c62f5f4; subsequent changes were restricted to screenshot readiness and CI configuration, with no production app code changes.

Evidence: GitHub Actions run 42386940087, artifact 13580700493, home.png and home-large-text.png. iPhone 15 Pro simulator, 393 × 852 points, standard text and accessibility-large. Synthetic document fixtures; no customer document data.

Verified by visual comparison:
- Three complete paper silhouettes fit below the header; the front page is upright and its top is visible.
- Readable subject and relationship appear on separate lines, without changing stored/exported filenames.
- The reduced fan and tighter spacing leave the recent thumbnail row visible at standard text size.
- The Continue label and arrow fit inside the glass action at accessibility-large, with horizontal padding.
- The continuous background has no separate rectangular hero surface.

Initial native capture showed an oversized fan and insufficient padding on the accessible action. These were corrected. A subsequent capture showed the launch screen and was rejected; the harness now waits for a nonblank frame before capture. The final captures were manually inspected.

Validation: device Release build, 16 display-name assertions, existing scanner core checks, native Vision orientation checks, ZIP integrity and IPA metadata/digest checks passed. Physical-device gestures and camera behavior were outside this layout check. Existing native tab-bar/search-role behavior and recent filenames remain outside the hero redesign scope.

final result: passed
