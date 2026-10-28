# Historical releases

`manifest.json` records the archived assets, their original download URLs, byte lengths, SHA-256 hashes, and the application metadata extracted from each ZIP. The files are preserved as GitHub release assets, not stored in the source repository or the Pages artifact. The `v2.41` release had no attached assets, so its source ZIP was generated from the upstream Git tag and is identified by `generated_from_tag`.

For an application ZIP, `plist_min` comes from its Info.plist, `architectures` and per-architecture `min_os` come from the Mach-O executable, and `icon_sha256` identifies the ICNS resource named by the application. A null minimum is unknown; an architecture only establishes the platforms for which code is present. For source-only releases, matching bundled application metadata is preferred. Otherwise, the application target’s explicit Release settings are used where interpretable; `project-settings-audit.json` records the project and settings checked. Default architectures and ambiguous build configurations remain unknown. Where no application icon could be verified in a source-only archive, the catalog leaves the icon blank instead of presenting an inferred neighboring icon.

The version 5.49 notes state that versions 5.00–5.48 crashed on Mojave; the catalog notes that exception independently of their minimum version. PowerPC and 32-bit Intel upper limits describe the last macOS versions capable of running those architectures, not a guarantee that every archived app runs on every earlier system.

`release-dates.json` contains only dates explicitly reported as TeXShop release dates, with a source for each. The GitHub Release `published_at` and source commit dates often reflect later archival work and are not treated as release dates. `date-conflicts.json` records conflicting dates. For version 3.65, the maintainer selected July 13, 2016, the date used in later snapshots. Dates in older archived tags such as `1.00-2001-03-19` are part of the tag name; they are not separately asserted to be release dates.

`Scripts/generate-historical-catalog.py` generates both language versions from these records. It does not upload, alter, or delete release assets.

Version 3.12’s source ZIP includes a TeXShop.app with matching version. Its Info.plist sets `CFBundleIconFile` to `Icons`, which identifies `TeXShop.app/Contents/Resources/Icons.icns`; document types use distinct icon settings. This is the icon shown in the catalog.

The icon-history illustration for 3.14–3.38 uses the icon from the 3.14 application. The 3.38 application uses a different ICNS encoding of the same visual design; individual releases are displayed using their own extracted icons.
