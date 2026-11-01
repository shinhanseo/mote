# First public release

The website and release pipeline are ready. Public downloads stay disabled until a Developer ID-signed build has passed Apple notarization and local Gatekeeper checks.

## One-time Apple setup (performed by the account holder)

1. Open Xcode → Settings → Accounts, select your paid Apple Developer team and **Manage Certificates**. Add **Developer ID Application**. Apple Development / Apple Distribution certificates do not replace it. If unavailable, the Account Holder can create it at https://developer.apple.com/account/resources/certificates/list and follow Apple's CSR instructions. Keep the corresponding private key in this Mac's login Keychain. Do not revoke existing certificates.
2. For notarization, use your Apple Account's application-specific password or a suitable App Store Connect API key. For the password route, generate the app-specific password yourself in https://account.apple.com/ under Sign-In and Security. Do not paste it into chat or commit it.
3. In your own Terminal, run the interactive command below. Enter the Apple ID, actual Developer Team ID and app-specific password at the prompts. The Team ID comes from your Developer account Membership details, not the certificate's personal identifier.

```sh
xcrun notarytool store-credentials Mote
```

This stores the notarization credential in Keychain, not in the repository. If using another profile name, set `MOTE_NOTARY_PROFILE` when running the scripts. If multiple Developer ID identities exist, explicitly select the intended one with `MOTE_SIGN_IDENTITY`.

## Verify and build

```sh
Tools/release-preflight.sh
Tools/release.sh
```

The preflight requires a usable Developer ID Application identity/private key and working notarization credentials. The build creates a separate universal app (`arm64` and `x86_64`) under ignored `release/`, leaving the running development app alone. It applies hardened runtime and a secure timestamp, notarizes and staples the app, creates a drag-to-Applications DMG, signs/notarizes/staples the DMG, and runs Gatekeeper checks. Apple reports must say **Accepted**, otherwise publication stops. The output includes versioned ZIP/DMG, checksums and a local verification manifest. Existing versioned DMGs are not silently overwritten.

## Publish only after verification

```sh
Tools/publish-release.sh
```

This requires clean committed/pushed source, matching build revision, accepted Apple reports and a stapled DMG accepted by Gatekeeper. It creates the public GitHub release, attaches the artifacts, then enables the website download links and pushes that website change to `main` for Pages deployment. The website never points to an ad-hoc or merely development-signed build.

The current website updater intentionally supports the first release only. Subsequent versions require reviewing the existing CTA/version text rather than blindly replacing another release's links.

## Delivery checks

- Download the published DMG through the public website in a browser, preserving quarantine metadata.
- Open it, drag Mote to Applications, launch, and verify it starts without bypassing Gatekeeper.
- Launch Codex Desktop, grant notifications as desired, check running/waiting/unread transitions, and verify the named monitor setting.
- Verify login launch from the installed Applications location; registration tied to an old development path may need disabling/re-enabling.
- Check on Apple Silicon and Intel hardware before advertising runtime validation for both. A universal binary contains both architectures but is not evidence of Intel runtime testing.

Developer ID certificate/private-key creation, app-specific password creation and credential entry are account-holder steps. Neither a certificate nor a password is supplied in this repository.
