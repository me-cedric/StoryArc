# Downloads queue menus, iOS (wave 4)

Task: close-the-audited-gaps 24.3. Each transfer's actions are one menu, and so are the whole queue's. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it proves |
| --- | --- |
| ios-downloads-queue | The queue (injected, three transfers): one "..." control per row and one "All downloads" control. |
| ios-downloads-row-menu-open | The failed transfer's menu: "Retry", then "Remove download" last, in its own group. |
| ios-downloads-all-menu-open | The menu for every transfer: "Pause all", "Resume all", then "Cancel all" last. |

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SweepDownloadsTests/testCaptureDownloadQueue` and `--only SweepCoverMenuTests/testCaptureQueueMenus --device <id> --appearance light|dark`.
