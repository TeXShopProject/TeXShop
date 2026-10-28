# Historical releases

`manifest.json` records the archived assets, their original download URLs, byte lengths, SHA-256 hashes, and the application metadata extracted from each ZIP. The files are preserved as GitHub release assets, not stored in the source repository or the Pages artifact. The `v2.41` release had no attached assets, so its source ZIP was generated from the upstream Git tag and is identified by `generated_from_tag`.

For an application ZIP, `plist_min` comes from its Info.plist, `architectures` and per-architecture `min_os` come from the Mach-O executable, and `icon_sha256` identifies the ICNS resource named by the application. A null minimum is unknown; an architecture only establishes the platforms for which code is present. Source-only releases do not receive inferred CPU or OS requirements, even if a source ZIP contains a separately built application. Where no application icon could be identified in a source-only archive, `icon_inferred_from` identifies the neighboring release whose representative icon is shown.

The version 5.49 notes state that versions 5.00–5.48 crashed on Mojave; the catalog notes that exception independently of their minimum version. PowerPC and 32-bit Intel upper limits describe the last macOS versions capable of running those architectures, not a guarantee that every archived app runs on every earlier system.

`release-dates.json` contains only dates explicitly reported as TeXShop release dates, with a source for each. The GitHub Release `published_at` and source commit dates often reflect later archival work and are not treated as release dates. `date-conflicts.json` records conflicting dates that are therefore omitted from the catalog. Dates in older archived tags such as `1.00-2001-03-19` are part of the tag name; they are not separately asserted to be release dates.

`Scripts/generate-historical-catalog.py` generates both language versions from these records. It does not upload, alter, or delete release assets.
