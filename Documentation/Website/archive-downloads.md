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
