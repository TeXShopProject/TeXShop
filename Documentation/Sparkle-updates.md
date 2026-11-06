# TeXShopProject updates

TeXShop 5.59 uses Sparkle 2.10.1, with the framework embedded at the project root. The historical `3rdparty/Sparkle-1.24.0` directory is not used by the application.

The feed is https://texshop.app/appcast.xml. It is part of the website deployed from `website/` by the manual **Publish website** GitHub Actions workflow. Edit website sources in this repository, commit and push after review, then run that workflow. GitHub Pages must be configured to use GitHub Actions. Site URL: https://texshop.app/.

The feed contains released builds only. A cached legacy feed URL is overridden by the updater delegate so the installed application's feed remains authoritative.

## Signing

The new EdDSA public key is embedded in `Resources/Info.plist`. Its private key is stored in the maintainer's login Keychain under account `TeXShopProject`; an owner-only backup is kept outside the repository. Never commit or upload that backup. No signing private key is required for website deployment.

Use the official Sparkle 2.10.1 tools from https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1. The release archive `Sparkle-2.10.1.tar.xz` has SHA-256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`.

## Prepare a release

1. Build the universal Release application. Run `python3 Scripts/sign-release.py /path/to/TeXShop.app --identity "Developer ID Application: Your Name (TEAMID)"` to sign nested code inside out with secure timestamps, preserving required entitlements but removing `get-task-allow`. Then notarize the ZIP with `xcrun notarytool submit /path/to/TeXShop.zip --keychain-profile TeXShop --wait` and staple the ticket with `xcrun stapler staple /path/to/TeXShop.app`. Check the release on supported macOS versions.
2. Run `python3 Scripts/prepare-sparkle-release.py /path/to/TeXShop.app /path/to/new-staging-directory --tools /path/to/Sparkle/bin`. The script checks the application's feed, public key, code signature, Gatekeeper assessment and stapled ticket, creates the ZIP, signs and verifies it, and prepares a signed appcast preserving earlier items. It never uploads anything.
3. Review the archive, release notes and appcast. After publication approval, create the matching GitHub release tag (`v.5.59` for 5.59) and upload `TeXShop-5.59.zip` unchanged.
4. After confirming the public archive is available, replace `website/appcast.xml` with the staged signed appcast, commit/push after review, and deploy the website. Do not edit an appcast after signing it; re-sign it after every edit.
5. Test the public feed from an earlier TeXShopProject-signed release before announcing automatic updates. The first release establishes that update path.

Koch's existing releases use his feed and keys. This new key does not authorize updates for them. A transition through his feed requires coordination with Koch; otherwise users install 5.59 manually and receive subsequent updates from TeXShopProject.

For the 5.59 domain transition, use `--replace-existing` to replace the existing 5.59 item in the staged feed. This option requires exactly one matching release and build version, preserves other releases, and still signs and verifies the complete feed. With the unchanged build number, an already-installed 5.59 must be replaced manually. Publish the replacement archive and verify its public checksum before deploying the replacement feed.

## Localized release notes

Starting with 5.60, prepare both `Documentation/Releases/<version>.md` (English)
and `<version>-ja.md` (Japanese). Each must start with `# TeXShop <version>`.
While the release is being prepared, retain `<!-- release-status: draft -->` in
each file. Finalize the content and remove that marker before packaging; the
preparation script rejects drafts or missing notes before invoking signing tools.
Keep the matching articles in `website/release-notes.html` and
`website/release-notes-ja.html` consistent with these documents.

`prepare-sparkle-release.py` embeds both documents as localized Markdown
`description` elements in the new appcast item. Sparkle selects the appropriate
language (English is the fallback) and displays the changes in its update window.
TeXShop 5.59 already ships Sparkle 2.10.1, which supports this format. The notes
are covered by the whole-appcast signature, so they do not require separately
signed HTML files. The existing signed `website/appcast.xml` is unchanged until
an actual release is prepared. The full release-history link also lets Sparkle
open the website's release notes.

Before publication, verify the update window in isolated English and Japanese
5.59 installations using the finalized signed feed. Check both the note display
and the update itself. Do not modify the signed appcast after signing it.

Reference: https://sparkle-project.org/documentation/publishing/
