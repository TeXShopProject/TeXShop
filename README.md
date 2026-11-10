# TeXShop

TeXShop is a free, open-source TeX and LaTeX editor and PDF previewer for macOS, created by Richard Koch and developed with contributions from many people.

At Richard's invitation, Yusuke Terada now develops and maintains TeXShop.

## Release status

- **Current release: TeXShop 5.59**, based on TeXShop 5.58 Golden Gate. Download the signed and notarized application from [GitHub Releases](https://github.com/TeXShopProject/TeXShop/releases/tag/v.5.59). The application uses the TeXShopProject update feed.
- **Beta: TeXShop 5.60 beta-3**, for testing. Download it from [GitHub Releases](https://github.com/TeXShopProject/TeXShop/releases/tag/v.5.60-beta.3); it is not offered through automatic updates. The changes are listed in the 5.60 release notes ([English](Documentation/Releases/5.60.md), [Japanese](Documentation/Releases/5.60-ja.md)).

The official website is [texshop.app](https://texshop.app/).

The universal application requires macOS 14.6 or later and runs on Apple Silicon and Intel. TeXShop also requires a separate TeX distribution to typeset documents; see [MacTeX](https://www.tug.org/mactex/).

## Source history

The initial commit is an import of Richard Koch's original `TexShop-5.58-GG-Source` archive. It is followed by maintenance changes, including PDF zoom and reload handling, preview appearance controls, localized interface corrections, runtime WebKit view creation, syntax-coloring range checks, invisible-character alignment, and PDF rendering recovery and workarounds.

## Building

Open `TeXShop.xcodeproj` in Xcode and select the `TeXShop` scheme. Choose your own signing configuration when building a distributable application. For an unsigned developer build:

```sh
xcodebuild -project TeXShop.xcodeproj -scheme TeXShop \
  -configuration Debug -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The current main application target declares macOS 14.6 as its deployment target. This build setting is not a tested release support matrix. Review the project settings against the Xcode SDK you use.

Tests are in `Tests/`. Release notes, the update procedure and notes on bundled libraries are in `Documentation/`; `Documentation/Legacy/` keeps documents from the original development. Launching the full application can update `~/Library/TeXShop`; use a separate test account or protect your existing configuration before testing development builds.

## Reporting bugs

Include the TeXShop version, macOS version, reproduction steps, and a minimal example. Remove private information from documents and crash reports before posting them in Issues.

## License and acknowledgments

TeXShop source headers specify the GNU General Public License, version 2 or (at your option) any later version. See [the GPL v2 text](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html). Bundled third-party components have their own license notices; those terms are unchanged.

Thank you to Richard Koch and all contributors, translators, documentation authors, and users who have supported TeXShop since 2000. See `Credits.rtf` and the original source notices for credits.
