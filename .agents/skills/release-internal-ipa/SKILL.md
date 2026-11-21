---
name: release-internal-ipa
description: Create a signed iOS IPA for internal distribution to registered Apple Developer devices. Use for requests to build an internal iOS release or export a distributable IPA.
---

# Release an Internal iOS IPA

Build a distribution-signed Release IPA from the current checkout for direct installation on registered Apple Developer devices.
Default to saving it at `~/Desktop/<AppName>.ipa`.

Use the existing signing settings and dependency versions. Export locally unless the user requests an upload.
Do not change source or version numbers just to export.

## Build and export

Use these commands as a starting point, adapted to the repository and installed Xcode version.
Discover the scheme and signing team from the project. For a workspace-based app, use `-workspace` instead of `-project`.
`xcodebuild -help` documents the available export settings. `security find-identity -v -p codesigning` lists local signing identities.

For Arbor, an archive with automatic signing looks like this:

```sh
build_dir=$(mktemp -d /tmp/ipa-release.XXXXXX)
xcodebuild -project Arbor.xcodeproj -scheme Arbor \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$build_dir/Arbor.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates -hideShellScriptEnvironment archive \
  > "$build_dir/archive.log" 2>&1
```

`-allowProvisioningUpdates` lets Xcode obtain signing assets through its configured Apple Developer account.
For manual signing, adapt the command to the project's profiles and certificates.
The dependency flag uses the committed `Package.resolved` versions.

Create `$build_dir/ExportOptions.plist` with these settings for an automatic registered-device export:

| Key | Value |
| --- | --- |
| `method` | `release-testing` |
| `destination` | `export` |
| `teamID` | The project's selected developer team |
| `signingStyle` | `automatic` |
| `thinning` | `<none>` |

```sh
xcodebuild -exportArchive -archivePath "$build_dir/Arbor.xcarchive" \
  -exportPath "$build_dir/export" \
  -exportOptionsPlist "$build_dir/ExportOptions.plist" \
  -allowProvisioningUpdates > "$build_dir/export.log" 2>&1
```

## Verify and deliver

Verify the exported IPA, including its embedded extensions. These commands expose the signatures and provisioning profile for inspection:

```sh
ditto -x -k "$build_dir/export/Arbor.ipa" "$build_dir/verify"
codesign --verify --deep --strict "$build_dir/verify/Payload/Arbor.app"
security cms -D -i "$build_dir/verify/Payload/Arbor.app/embedded.mobileprovision"
```

Verify that the profiles cover the intended team, app identifiers, and devices, with valid expiration dates and `get-task-allow=false`.
Copy the verified IPA to the destination. If an IPA already exists there, use a unique filename.
Return a clickable file link with the minimum iOS version and any material installation constraints.

## Troubleshooting

Investigate failures using the actual logs rather than a fixed retry sequence.
If export fails, preserve the archive so a retry does not require another build.
An empty identity list or trust error can reflect sandbox restrictions rather than missing signing assets.
Apple's `PLA Update available` error means the account holder needs to review a pending Developer Program agreement.
