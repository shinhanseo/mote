# Mote for iPhone

Native SwiftUI companion, iOS 17+. Uses the homepage's dust silhouette, ivory paper, olive accent, generous spacing and divider rows. No third-party UI or networking dependencies.

## Current implementation

- Now / History / Settings, event detail, empty and connection-error states, dark appearance, Reduce Motion support.
- Device-local acknowledgment and persistent 10-minute reminders. Acknowledgment cancels an outstanding reminder. These actions do not acknowledge or approve anything in Codex.
- Native notification permission, local test notification, private CloudKit fetch and visible query subscriptions for completion / approval / input-required events.
- Titles hidden by default. Push payload text is generic and contains no conversation titles. Raw prompts, replies, commands, project paths and Codex thread IDs are not in the shared schema.
- Explicit `--demo` preview, marked on screen. A normal launch never seeds fake devices/events or marks a connection successful before a real fetch.
- Shared CloudKit transport and a compiled Mac notifier adapter. **The adapter is not wired into the shipping Mac monitor yet.** No automatic Mac → iPhone notifications have been end-to-end tested.

## Open and build

Open `MoteMobile.xcodeproj`, scheme `MoteMobile`.

- `Debug`: safe simulator build; CloudKit disabled. Use launch argument `--demo` for sample events; optional `--history` or `--settings` opens that tab.
- `CloudDebug`: development CloudKit + push entitlements for device testing, team `2RQKCF6Z9C`.
- `Release`: CloudKit-enabled archive configuration. Production schema, signing and real-device delivery must be verified before distribution.

The project is committed directly. `python3 generate-project.py` regenerates the project deterministically without XcodeGen or Ruby gems. Keep the generated files checked in.

```sh
xcodebuild -project Mobile/MoteMobile.xcodeproj -scheme MoteMobile \
  -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/mote-mobile \
  CODE_SIGNING_ALLOWED=NO build

swiftc -parse-as-library Mobile/Shared/CloudRelay.swift Mobile/Tests/RelayTests.swift \
  -o /tmp/mote-relay-tests && /tmp/mote-relay-tests
```

## CloudKit setup / remaining integration

Container: `iCloud.im.mote.companion`. iOS bundle: `im.mote.companion.mobile`.

The device build with automatic provisioning succeeded on the development Mac. This proves that the project signs with CloudKit/push entitlements; it does not prove that the production schema exists or that notifications arrive.

Both devices must use the same iCloud account and the same CloudKit environment. Do not mix a development Mac writer and TestFlight's production receiver.

Record types in the private database default zone:

| Type | Fields | Indexes |
| --- | --- | --- |
| MoteMac | name:String, lastSeen:Date | recordName queryable |
| MoteEvent | kind:String, title:String (empty by default), macName:String, occurredAt:Date | recordName queryable, kind queryable, occurredAt queryable + sortable |

Event recordName is a SHA-256 of installation identity + thread + turn + kind. Codex IDs do not leave the Mac in plaintext. Idempotent event creation avoids duplicate creation alerts. There are no remotely executable commands in this protocol.

Before a real beta:

1. Development schema and query/sort indexes were imported and verified in CloudKit Console (`schema.ckdb`). Only the default Users type existed beforehand. Production schema has not been deployed; deploy only after real-device verification.
2. Associate a development Mac App ID/profile with this container. Compile `Shared/CloudRelay.swift` and `MacIntegration/MobileNotifier.swift` into an opt-in Mac build with `MoteCloudKitEnabled=true` and appropriate iCloud entitlements. The normal public Mac binary must not enable CloudKit without provisioning.
3. Wire `connect()` to an explicit Mac setting. Only after successful account/registration checks enable sending.
4. Route existing completion/approval/input notices to `send(...)`, respecting pause, privacy, snooze and away policy. Await results and surface failures. The adapter starts disabled, does not persist consent yet, and has no offline retry queue yet.
5. Add bounded expiration/deletion of old event records and a durable, expiring retry queue before enabling automatic sending broadly. Current receiver only fetches up to 100 events from the last 7 days; old cloud records are not automatically deleted yet.
6. Test on a physical iPhone: locked screen, app terminated, Wi-Fi/cellular, denied notifications, full iCloud storage, changed account, stale state and duplicate sends.
7. Add iPhone-side connect/disconnect ownership and subscription cleanup before calling the flow complete. Current subscriptions are account scoped, so multi-iPhone notification preferences are not isolated yet.

The existing approved Mac release is unchanged. This work does not provide remote Codex approval/reply, guarantee instant push delivery, or keep a sleeping Mac running.

Apple references: [enable CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app), [creation subscriptions](https://developer.apple.com/documentation/cloudkit/ckquerysubscription/options/firesonrecordcreation).
