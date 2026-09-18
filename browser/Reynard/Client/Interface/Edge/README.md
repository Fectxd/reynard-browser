# Edge UI Instrumentation

This folder contains the *Edge-style overflow menu* ("≡" button) customisation
applied on top of upstream **[minh-ton/reynard-browser](https://github.com/minh-ton/reynard-browser)**.

## What it does

Tapping the **≡** button now opens an Edge-style menu instead of the old tab-bar
library. The menu adapts like the rest of the app:

| Layout | Rendering |
|---|---|
| Wide / regular width (iPad landscape, split screen) | **grid** of icon + label tiles |
| Narrow / compact width (iPhone portrait) | **vertical list** of icon + label rows |

A thin divider separates the two groups:

- **Above the line (blue tint):** 收藏夹 · 历史记录 · 下载 · 设置
- **Below the line:** 主页 · 新建 InPrivate 标签页 · 添加到收藏夹 · 查看桌面网页 ·
  删除数据 · 扩展共享 · 发送到设备 · 翻译 · 添加至手机 · 下载此页面 ·
  在页面上查找 · 字体大小 · 退出浏览器

### Wired to real features

| Menu item | Backing implementation |
|---|---|
| 收藏夹 / 历史记录 / 下载 / 设置 | `presentLibrary(initialSection:)` |
| 主页 | `createNewTab(mode: .regular)` |
| 新建 InPrivate 标签页 | `createNewTab(mode: .private)` |
| 添加到收藏夹 | `presentBookmarkEditor(addToFavorites: true)` |
| 查看桌面网页 | `tabManager.changeWebsiteModeForSelectedTab()` |
| 删除数据 | `ClearBrowsingDataViewController` |
| 扩展共享 | share sheet (`presentShareSheet`) |
| 下载此页面 | `presentLibrary(initialSection: .downloads)` |
| 在页面上查找 | `showActionBar(.findInPage)` |
| 字体大小 | **per-site page zoom** (`presentPerSitePageZoom`) |

### Rendered as icon placeholders (implemented later)

发送到设备 · 翻译 · 添加至手机 · 退出浏览器 — shown faded with an icon, no-op
on tap.

## Per-site font size ("字体大小")

Font size is exposed as **per-site page zoom**. It is backed by the app's existing
`SiteSettingsStore` (`setPageZoom(_:forHost:)`), so a chosen zoom level is
remembered **only for the current host** — exactly the "per site" behaviour you
asked to borrow from the fork. No engine change is required.

## Files added

- `browser/Reynard/Client/Interface/Edge/EdgeMenuViewController.swift`
  — adaptive grid/list collection-view menu.
- `browser/Reynard/Client/Interface/Edge/BrowserViewController+EdgeMenu.swift`
  — presents the menu and dispatches each item.
- `browser/Reynard/Client/Interface/Edge/edge-ui.patch` — the replayable unified diff.
- `tools/development/apply-edge-ui.sh` — applies the patch (idempotent).
- `.github/workflows/edge-ui-build.yml` — fork build that replay-applies the patch
  then compiles.

The Edge UI patch lives **outside** the engine `patches/` directory on purpose:
`patches/` is consumed by `tools/development/apply-patches.sh` and applied to the
`engine/firefox` submodule. Keeping `edge-ui.patch` under
`browser/Reynard/Client/Interface/Edge/` prevents the engine patch script from
trying to apply it to the wrong tree.

Two existing files get a one-line hook each (both captured by the patch):
- `BrowserViewController.swift` — `onLibrary` now calls `presentEdgeMenu()`.
- `BrowserChrome.swift` — adds `menuButtonAnchorRect()`.

## Why a patch, and how to keep it working after an upstream update

The app Swift code (`browser/Reynard/...`) lives in this same repo, not in the
Gecko engine submodule, so upstream pushes can change these files. Rather than
editing them in place (and fighting merge conflicts on every sync), the Edge UI
is kept as **one replayable patch** and applied on top of whatever upstream
shipped.

Because the `Reynard` Xcode folder uses **synchronized root groups**, any new
`.swift` file under `browser/Reynard/...` is compiled automatically — no
`project.pbxproj` edit is ever needed, and the patch never touches the Xcode
project.

### To re-apply after syncing upstream

```sh
# after pulling/merging the new upstream commit into this repo
./tools/development/apply-edge-ui.sh
```

The script is idempotent: if the patch is already applied it exits immediately;
otherwise it applies with `git apply --3way`, so it merges even when nearby
source shifted. Use `--non-interactive` in CI to fail instead of prompting:

```sh
./tools/development/apply-edge-ui.sh --non-interactive
```

### Via GitHub Actions

The `.github/workflows/edge-ui-build.yml` workflow runs on the **fork** (the
upstream `build.yml` is gated to the `minh-ton` owner and ignores forks). It
replays the patch, builds Gecko, and produces the IPA/TIPA artifacts. Trigger it:

- **Manual:** Actions → *Edge UI Build (Fork)* → *Run workflow*, or
- **Automatic:** push to the `edge-ui` branch.

Note: building requires a macOS runner and compiles the Gecko engine, so a run
takes a long time.

## Regenerating the patch after further edits

After editing the Edge UI files, regenerate `edge-ui.patch` by diffing against
upstream:

```sh
# assuming `upstream` is minh-ton/reynard-browser's main
git fetch upstream
git diff upstream/main -- browser/ > browser/Reynard/Client/Interface/Edge/edge-ui.patch
```

Keep the diff limited to `browser/` so the Gecko-engine `patches/` flow
(`apply-patches.sh`) is untouched.
