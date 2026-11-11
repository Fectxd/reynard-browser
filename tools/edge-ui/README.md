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

## Edge start page vs. address-bar homepage

- **Homepage tabs / new tabs** show the Edge start page
  (`Homepage/Edge/EdgeStartPageViewController.swift`): weather in the top-left
  corner, homepage settings in the top-right corner, a search box that focuses
  the real address bar, then pages for Favorites / Frequently Visited /
  Recently Closed (centred, width-adaptive) and the MSN feed (ads filtered).
- **The small homepage shown while the address bar is focused** is upstream's
  own `HomepageRootViewController`, left unmodified. `HomepageOverlayCoordinator`
  keeps one `HomepageViewController` of each `HomepageStyle` and picks one per
  presentation.

## How the customisation is carried (patch over upstream)

Everything the fork changes in the app lives in `tools/edge-ui/`:

| File | Contents |
|---|---|
| `edge-ui.patch` | Unified diff of `browser/` against the upstream commit (text files only) |
| `strings.json` | Edge entries for `Localizable.xcstrings`, merged **by key** |
| `overlay/` | Binary files (app icon PNGs) copied over the tree as-is |
| `merge-strings.py` | The string merger (keeps Xcode's JSON formatting) |
| `regenerate-patch.sh` | Rebuilds `edge-ui.patch` + `strings.json` from the working tree |

The patch deliberately lives **outside** `browser/` (resetting `browser/` to
upstream must not delete it) and outside `patches/` (that directory belongs to
the Gecko engine flow in `apply-patches.sh`). The string catalog is not
patched as text because upstream rewrites it on nearly every translation sync,
which made the text hunk conflict.

Because the `Reynard` Xcode folder uses synchronized root groups, new `.swift`
files under `browser/Reynard/...` compile automatically; the patch never touches
`project.pbxproj`.

### CI

`.github/workflows/edge-ui-build.yml` fetches `minh-ton/reynard-browser`
(`upstream_ref`, default `main`), then runs

```sh
./tools/development/apply-edge-ui.sh --non-interactive --from-upstream FETCH_HEAD
```

which resets `browser/`, `engine/` and `patches/` to that upstream revision and
replays the patch, overlay and strings before building. Every build therefore
proves the customisation still applies to the latest upstream. If upstream
changed something the patch touches, the step fails and lists the conflicting
files.

### Local workflow

```sh
git fetch upstream
git merge upstream/main          # or rebase; resolve conflicts in browser/
# ...edit browser/ sources...
./tools/edge-ui/regenerate-patch.sh
```

To test the replay locally exactly as CI does:

```sh
./tools/development/apply-edge-ui.sh --non-interactive --from-upstream upstream/main
git checkout -f HEAD -- . && git clean -fd browser   # back to the branch state
```
