# Historical website downloads

The archive preserves the original prose and HTML snapshots. Direct download links in the rendered pages point to local copies; source URLs, sizes and SHA-256 hashes are recorded in `website/archive/manifest.json`.

`HumboldtTalk.pdf` was recovered from the parent directory of Richard Koch’s website. The three files in `Smoothing/` were recovered from Internet Archive snapshots because the original URLs now return HTTP 404. Their snapshot URLs are recorded in the manifest.

## Large release assets

The following original, unmodified ZIP files are excluded from Git and must be uploaded to the **historical-downloads** release in `TeXShopProject/TeXShop`, after publication approval:

- `texshop557-tahoe.zip`
- `texshopsource557-tahoe.zip`

Local copies are in `website/archive/downloads/`. Keep backups before removing a checkout. `Scripts/build-website.py` restores missing copies from that release and verifies their SHA-256 hashes. The built Pages site serves these files at the same relative download URLs as the local preview. A clean checkout cannot build the full site until those release assets have been published.

Suggested release title: **Historical TeXShop downloads**

Suggested release text:

> Original TeXShop application and source archives preserved from Richard Koch’s website. These historical files are provided unchanged for archival purposes; they are not the current release.

Mark this archival release as **not the latest release**.

## Link audit

`archive-link-audit-2026-10-28.json` records every unique external URL and each local file reference found before mirroring, including HTTP response codes and redirect destinations. HTTP 403 and timeouts do not establish that a resource no longer exists. Unavailable third-party web pages remain historical references rather than being silently replaced with unrelated pages. Directly linked downloadable files have been recovered separately as recorded in the manifest.

## Legacy releases listed on Downloads

The English and Japanese Downloads pages list 5.58 (Golden Gate), 5.57 (Tahoe), 5.57, 4.79, 4.44 and 2.47, with separate application and source ZIP links. These links point directly to assets in the `historical-downloads` pre-release; these additional large files are not copied into the Pages build or committed to Git.

`legacy-downloads.json` records each original URL, release asset URL, byte count, SHA-256 hash, bundle version and architecture. The 4.79 and 4.44 source ZIPs come from the matching tags in Max Horn’s TeXShop repository, which Richard Koch’s Obtaining page recommends for historical sources. The commit IDs are recorded in the manifest. All other application and source archives come directly from Richard Koch’s website. The ZIP contents are preserved unchanged.

The minimum OS shown on Downloads follows the original distribution’s documentation and bundle requirements. Apple Silicon binaries require at least macOS 11. The Tahoe build has a minimum of 10.13 on Intel, but Koch recommends it for Tahoe; the page preserves that distinction. Version 2.47 contains PowerPC and 32-bit Intel code, so it cannot run on macOS 10.15 or later. The 5.58 Golden Gate archive is distributed by Koch as version 5.58, although its original Info.plist retains version 5.57; that metadata is preserved unchanged.

Upload the ZIPs and `historical-downloads-SHA256SUMS.txt` only after publication approval. Keep `historical-downloads` marked as a pre-release and keep 5.59 as the latest release. The checksums file covers both the existing Tahoe archives and the additional legacy archives.

## Download buttons and checksums

Both Downloads pages show separate OS and CPU columns. Each App and Source button has its own SHA-256 copy button, using the verified values in the legacy manifest. Version 5.59 also has a source ZIP, downloaded unchanged from the `v.5.59` tag archive and intended for storage as `TeXShop-5.59-source.zip` in the existing 5.59 release. Its source commit, hash and size are recorded in `Documentation/Releases/5.59-source.json`. The signed application ZIP, existing SHA256SUMS asset and appcast are unchanged.
