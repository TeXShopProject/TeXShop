# Historical releases

`manifest.json` records the archived assets, their original download URLs, byte lengths, SHA-256 hashes, and the application metadata extracted from each ZIP. The files are preserved as GitHub release assets, not stored in the source repository or the Pages artifact. The `v2.41` release had no attached assets, so its source ZIP was generated from the upstream Git tag and is identified by `generated_from_tag`.

For an application ZIP, `plist_min` comes from its Info.plist, `architectures` and per-architecture `min_os` come from the Mach-O executable, and `icon_sha256` identifies the ICNS resource named by the application. A null minimum is unknown; an architecture only establishes the platforms for which code is present. For source-only releases, matching bundled application metadata is preferred. Otherwise, the application target’s explicit Release settings are used where interpretable; `project-settings-audit.json` records the project and settings checked. Default architectures and ambiguous build configurations remain unknown. For source-only versions 3.13, 3.19–3.20, and 3.27–3.33, the catalog uses the 128-pixel PNG in the root Icons.iconset: the application target includes that icon set in its resources, and Info.plist names Icons as the app icon. The manifest records the exact source paths.

The version 5.49 notes state that versions 5.00–5.48 crashed on Mojave; the catalog notes that exception independently of their minimum version. PowerPC and 32-bit Intel upper limits describe the last macOS versions capable of running those architectures, not a guarantee that every archived app runs on every earlier system.

`release-dates.json` records dates explicitly reported for TeXShop releases and dates inferred from dated upstream tag names, with a source and explanatory note for each inference. The GitHub Release `published_at` and source commit dates often reflect later archival work and are not treated as release dates. `date-conflicts.json` records conflicting dates. For version 3.65, the maintainer selected July 13, 2016, the date used in later snapshots. For dated archive tags such as `1.00-2001-03-19`, the catalog shows the tag date at the maintainer’s direction; whether it is the actual public release date is not independently confirmed. Koch describes 1.0 as dated March 24, 2001, but also says it was put online a few days before that date; the catalog shows March 24 as the version date.

`Scripts/generate-historical-catalog.py` generates both language versions from these records. It does not upload, alter, or delete release assets.

Version 3.12’s source ZIP includes a TeXShop.app with matching version. Its Info.plist sets `CFBundleIconFile` to `Icons`, which identifies `TeXShop.app/Contents/Resources/Icons.icns`; document types use distinct icon settings. This is the icon shown in the catalog.

The icon-history illustration for 3.14–3.38 uses the icon from the 3.14 application. The 3.38 application uses a different ICNS encoding of the same visual design; individual releases are displayed using their own extracted icons.

`release-status.json` records the status of beta, development, unreleased and experimental versions and the evidence used for the labels. A final release is not labeled experimental merely because an earlier experimental build shared its version number; 2.15 was eventually made official.

`changelog-links.json` maps release tags to relevant archived change notes; dated 1.00 snapshots and letter-suffixed variants may link to their shared base-version notes. When the old change log lacks an individual entry for the earliest development builds, the links use Koch’s historical account instead.

`first-release.json` records version 1.0d1’s original 2000 release date and separately identifies the app and source as the 2024 recompilation, with compatibility and hashes checked from the preserved archives. These files are not the original 2000 distribution.

`icon-transition-notes.json` records the historical sources behind the short explanations of icon changes. The date associated with the earliest triangular-icon snapshot is inferred from its archive tag, not independently established as the first public appearance.

`cpu-transition-notes.json` records the change-log evidence for Intel, 64-bit and Apple Silicon milestones. An earlier unreleased 2.32 64-bit build is distinguished from the 3.00 official transition.

`requirements-inferences.json` documents estimated CPU/OS values and their bounding evidence; inferred values are identified as estimates in the catalog. The 2.32 source archive contains a matching 64-bit x86_64 application under `texshop2.32-64/build/Release/TeXShop.app`; adjacent official 2.31 and 2.33 applications are 32-bit PowerPC/Intel, but those architectures are not claimed for the distinct 2.32 source archive. Some early minimum OS versions remain unknown where historical requirements conflict or lack bounding evidence.
