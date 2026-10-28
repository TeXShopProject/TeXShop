# TeXShopProject updates

TeXShop 5.59 uses Sparkle 2.10.1, with the framework embedded at the project root. The historical `3rdparty/Sparkle-1.24.0` directory is not used by the application.

The feed is https://texshopproject.github.io/TeXShop/appcast.xml. It is part of the website deployed from `website/` by the manual **Publish website** GitHub Actions workflow. Edit website sources in this repository, commit and push after review, then run that workflow. GitHub Pages must be configured to use GitHub Actions. Site URL: https://texshopproject.github.io/TeXShop/.

The initial feed contains no releases. Publishing it does not distribute a development build. A cached legacy feed URL is overridden by the updater delegate so the installed application's feed remains authoritative.

## Signing

The new EdDSA public key is embedded in `Resources/Info.plist`. Its private key is stored in the maintainer's login Keychain under account `TeXShopProject`; an owner-only backup is kept outside the repository. Never commit or upload that backup. No signing private key is required for website deployment.

Use the official Sparkle 2.10.1 tools from https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1. The release archive `Sparkle-2.10.1.tar.xz` has SHA-256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`.

## Prepare a release

1. Build the universal Release application. Run `python3 Scripts/sign-release.py /path/to/TeXShop.app --identity "Developer ID Application: Your Name (TEAMID)"` to sign nested code inside out with secure timestamps, preserving required entitlements but removing `get-task-allow`. Then notarize the ZIP with `xcrun notarytool submit /path/to/TeXShop.zip --keychain-profile TeXShop --wait` and staple the ticket with `xcrun stapler staple /path/to/TeXShop.app`. Check the release on supported macOS versions.
2. Run `python3 Scripts/prepare-sparkle-release.py /path/to/TeXShop.app /path/to/new-staging-directory --tools /path/to/Sparkle/bin`. The script checks the application's feed, public key, code signature, Gatekeeper assessment and stapled ticket, creates the ZIP, signs and verifies it, and prepares a signed appcast preserving earlier items. It never uploads anything.
3. Review the archive, release notes and appcast. After publication approval, create the matching GitHub release tag (`v5.59` for 5.59) and upload `TeXShop-5.59.zip` unchanged.
4. After confirming the public archive is available, replace `website/appcast.xml` with the staged signed appcast, commit/push after review, and deploy the website. Do not edit an appcast after signing it; re-sign it after every edit.
5. Test the public feed from an earlier TeXShopProject-signed release before announcing automatic updates. The first release establishes that update path.

Koch's existing releases use his feed and keys. This new key does not authorize updates for them. A transition through his feed requires coordination with Koch; otherwise users install 5.59 manually and receive subsequent updates from TeXShopProject.
