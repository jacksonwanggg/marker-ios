# Marker

Marker is an iPhone app for marking tasks in Formatif, the tutor marking system UNSW CSE runs (it's a fork of Doubtfire). I wanted to work through my marking queue from my phone: see what's waiting, read the submission, leave a comment and set a status, all without opening a laptop.

It's an unofficial client, so it isn't made or endorsed by UNSW or the Formatif team. It's written in SwiftUI for iPhone, needs iOS 18 or later, uses Swift 6, and has no third-party dependencies.

The inbox lists tasks waiting on you, and you can narrow it to your students, one tutorial or the whole unit. Explorer shows one task across tutorials, and Students has a page per student with their tasks and staff notes. Open a task to read the submission PDF and files, check the task sheet, comment, set a status or answer an extension request. There are also CSV exports and local notifications.

## Running it

The Xcode project is generated from `project.yml` and isn't checked in, so generate it first:

```sh
brew install xcodegen
xcodegen generate
open Marker.xcodeproj
```

Run `xcodegen generate` again whenever you add or remove files or edit `project.yml`.

To run it on your own iPhone, set your team and a bundle id of your own. Do that in `project.yml` (`DEVELOPMENT_TEAM` and the `PRODUCT_BUNDLE_IDENTIFIER` lines). Changing them in Xcode under Signing & Capabilities works too, but the next `xcodegen generate` throws those changes away.

## Tests

```sh
xcodebuild -project Marker.xcodeproj -scheme Marker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

This runs the unit tests and the UI tests that drive demo mode. `SSOTests` also opens the real Microsoft sign-in page (it types nothing), so it needs a network connection. The live-data, live QA and demo video tests skip themselves unless their environment variables are set (see below). xcodebuild hands any `TEST_RUNNER_` variable to the tests with that prefix removed.

## Demo mode

"Try the demo" on the sign-in screen runs the whole app on invented data, and writes are faked. App Review will use this too. For screenshots there are launch arguments, and the last three only work in demo mode:

| Argument | Effect |
|---|---|
| `-demo YES` | skip sign-in and start in demo mode |
| `-demoTab notifications` | open a tab (`explorer`, `students`, `notifications`, `settings`) |
| `-demoOpen comments` | open a task on one of its tabs (`submission`, `files`, `sheet`, `comments`) |
| `-demoStudent YES` | open a student page |

## Demo video

`demo/Marker-demo.mp4` is a narrated walkthrough of demo mode. The `demo/` folder is git-ignored, so the video isn't in the repo.

To record it again, run `MarkerUITests/DemoVideoTests` with `TEST_RUNNER_VIDEO_DURATIONS` set to one `sNN=seconds` pair per narration clip (`s01=13.7,s02=14.5,...`). The test drives the app one step per clip and prints when each step starts. Record the simulator with `xcrun simctl io <device> recordVideo` while it runs, then use ffmpeg to lay the clips over the recording at those times.

## Read-only QA against a live unit

This only works in debug builds. Setting `MARKER_QA_READONLY=1` on the app makes the client refuse every write. It also refuses the reads that have side effects: `comments`, because reading a thread marks it read, and `submission`, `submission_files` and `submission_details`, which Formatif logs as marking activity. `LiveQATests` sets this flag itself.

There are two kinds of live test. `LiveDataTests` runs the app model on saved responses from a live unit, with no network. That folder holds one JSON file per endpoint (`unit_roles.json`, `unit.json`, `inbox_mine.json` and so on; `FileBackend` in `LiveDataTests.swift` has the full list). Keep it outside the repo because it contains real student data. `LiveQATests` runs the real app against the live unit using an auth token you already have.

```sh
# app model on saved responses
TEST_RUNNER_MARKER_LIVE_DIR=/path/to/saved \
TEST_RUNNER_MARKER_CAPTURES_DIR=/path/to/captures \
  xcodebuild -project Marker.xcodeproj -scheme Marker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MarkerTests test

# the real app on the live unit, read-only
TEST_RUNNER_MARKER_QA_TOKEN=<auth token> TEST_RUNNER_MARKER_QA_USER=z5xxxxxx \
  xcodebuild -project Marker.xcodeproj -scheme Marker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MarkerUITests/LiveQATests test
```

The captures folder is optional. It's only used to check that captured comment threads decode.

Debug builds also have a Debug section in Settings showing whether a refresh token is present, your user id and your tutorials, plus a "Test token refresh" button. Release builds compile all of this out.

## How it talks to Formatif

Every request goes through `Core/FormatifClient.swift`, which is an actor. It sends the `auth-token` and `username` headers. On a 419 or 401 it refreshes the token once and retries, and concurrent requests share that one refresh. Error bodies like `{"error": ...}` become readable messages. `Core/Backend.swift` maps each thing a screen does to its endpoint.

"Sign in with UNSW" fetches `/api/auth/method`, opens Microsoft's sign-in page in a web view, catches the redirect to `/sign_in?authToken=...&username=...` and exchanges that token with `POST /api/auth`. The session (auth token, refresh cookie and its 7-day expiry) is stored only in the Keychain.

The app tries hard to avoid side effects in Formatif. It fetches comments only when you open the Comments tab, since that marks them read. It loads PDFs only when you open a submission, and background refresh only asks for the inbox. Every write (comment, status, extension, pin, staff note) needs a tap and is sent straight away. If Formatif refuses it, the change rolls back and you see the error.

## Notifications

The app compares the inbox with the last copy it saw, both in the foreground and during Background App Refresh. New submissions, resubmissions, new student comments and extension requests each send a notification, grouped by task, and tapping one opens the task. "Mark as read later" just dismisses it and sends nothing to Formatif.

Feedback reminders go off when a submission has been waiting without feedback: three nudges and then an overdue reminder, by default after 2, 3, 4 and 7 days. In Settings you can turn each one off or change its day count, and they stay in order, so moving one pushes the others along. By default a reminder fires that long after the submission, or you can pick a time of day and it fires then once enough time has passed. Reminders are scheduled locally, so they fire on time without background refresh, and they're rescheduled on every refresh, status change and settings change. The inbox tags ("Waiting 5 days", "Overdue · 1 week, no feedback") and the "Waiting Nd+" filter use the same days.

You also get:

- a daily summary at a time and on weekdays you choose (default 08:00, Monday to Friday)
- a warning before your sign-in runs out, a chosen number of hours before the 7 days are up (default 12)
- quiet hours with your own start and end (default 22:00 to 08:00), during which alerts arrive silently and reminders wait until the quiet hours end
- an app badge counting tasks awaiting feedback plus unread threads

If you set a status while a comment is still typed, the app offers to send the comment first ("Send and set Complete"). If Formatif refuses the comment, the status isn't changed.

## Not built yet

- the iPad three-column layout (the target is iPhone only)
- viewers for the similarity report and Overseer, discussion prompts, and the marking-sessions chart (the CSV exports are there)
- replying to or editing staff notes (adding and deleting work)
- camera attachments (Photos and Files work)
- notification scopes other than "my students"

## App Store notes

The plan is an unlisted App Store release. Because Marker is an unofficial client, get an OK from the Formatif/CSE admins before submitting. `PrivacyInfo.xcprivacy` declares no tracking and no collected data, and `ITSAppUsesNonExemptEncryption` is `NO`. UNSW sign-in needs a staff account, so the review notes should point App Review at "Try the demo".
