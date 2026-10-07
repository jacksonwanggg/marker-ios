# Marker

An iPhone app for marking in Formatif, the marking system UNSW CSE uses. I made it so I could get through my marking on my phone: see what's waiting, read the submission, leave a comment and set a status.

It's unofficial (not made or endorsed by UNSW or the Formatif team) and it isn't on the App Store. You build it onto your phone with Xcode.

## Install

You need a Mac with Xcode 16 or later, an iPhone on iOS 18 or later, and an Apple ID. A free one works.

1. Download the code (Code > Download ZIP, or `git clone`) and open `Marker.xcodeproj`.
2. Click Marker in the sidebar and go to Signing & Capabilities. Pick your Apple ID as the team and change the bundle identifier to something like `com.yourname.marker`.
3. Plug in your iPhone, select it at the top of Xcode and press Run.
4. On the phone, turn on Developer Mode in Settings > Privacy & Security, then trust yourself in Settings > General > VPN & Device Management.

With a free Apple ID the app stops opening after 7 days. Plug the phone in and press Run again.

Sign in with your UNSW account, or tap "Try the demo" to look around with made-up data.

## Notes

Marker only talks to Formatif and Microsoft's sign-in page, and your login stays in the iPhone's Keychain.

Opening a comment thread marks it as read in Formatif, and opening a submission counts as marking activity, so the app only loads those when you open them.

The Xcode project is generated from `project.yml` with XcodeGen. If you add files or change settings, edit `project.yml` and run `xcodegen generate`.

Run the tests with Cmd+U. The live tests skip themselves unless you give them a token or saved data (see `LiveQATests.swift` and `LiveDataTests.swift`).
