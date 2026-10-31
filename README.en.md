# Best Planner

[中文说明](README.md)

A macOS kanban planner with a desktop widget, plus a web version (add it to your phone’s home screen) that syncs with the Mac through cloud sync. Available in English and Chinese.

## Download

1. Go to **[Releases](https://github.com/ziyueupup-ghost/best-planner/releases/latest)** and download `BestPlanner-<version>.zip`. Unzip it and drag `Best Planner.app` into your Applications folder.
2. **macOS will block it the first time** ("can't verify the developer") because the app isn't signed with a paid Apple developer account:
   - Double-click it once and click Done when the warning appears;
   - Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** and confirm. After that it opens normally.
3. Requires macOS 14 (Sonoma) or later. Works on Apple silicon and Intel Macs.
4. Desktop widget: right-click the desktop → Edit Widgets → search for “Best Planner”.
5. Updates: the app checks every time it opens and shows an alert when there is a new version — click **Update Now** and it downloads, verifies, installs and reopens itself (from 1.5.0 on). You can also use **Best Planner → Check for Updates…**.

**Language:** the app follows your system language. To switch, use the 🌐 button in the toolbar or **Best Planner → Language**, then reopen the app.

## Web version and cloud sync

The web version: https://best-planner.orgevery.workers.dev

1. **Sign up** from the Mac app (toolbar ☁️ **Cloud Sync** → “No account? Sign up”) or on the website. The account can be an email or a user name (3–32 letters, digits, `. _ -`). Sign-up needs an invite code — ask the author. Your existing Mac tasks are uploaded right away.
2. **Phone**: open the web address in Safari, sign in, then Share → **Add to Home Screen**. Sign in once more the first time you open it from the home screen; after that it stays signed in (as long as you use it at least once every six months).
3. **Sync**: the Mac app uploads about 2 seconds after a change and checks for changes from other devices every 15 seconds; the website uploads at once and checks every 10 seconds while open. It works offline and catches up when you’re back online. Edits made on two devices at once are merged.

Notes:
- The web version has no focus timer, agenda, review, statistics or multi-select; the next copy of a repeating task is created when the Mac app is open.
- Files attached on a Mac open only on that Mac; the website shows the device name and path, which you can copy.
- A wrong password shows how many tries are left; after 5 in a row, wait 15 minutes. There’s no self-service password reset; the admin runs `Web/reset-password.sh`.
- Accounts can’t see each other’s tasks. iCloud Drive sync still works alongside cloud sync.

## iPhone app (no longer updated)

The iPhone app is no longer updated; use the web version above on your phone. The old instructions are kept below for reference.

The iPhone app isn't on the App Store; you sign and install it yourself with a free Apple account. You need a Mac and a USB cable (no Xcode).

1. **Install Best Planner on your Mac first and turn on iCloud sync**: **Best Planner → Sync with iCloud Drive…**. A “Best Planner” folder appears in iCloud Drive. Your Mac and iPhone must use the **same** Apple account, with iCloud Drive on.
2. Download `BestPlanner-iOS-<version>.ipa` from Releases.
3. Install [iloader](https://github.com/nab138/iloader/releases/latest) (SideStore's official installer) on the Mac and sign in with your Apple account.
4. Connect the iPhone with the cable, select it in iloader, click **Import IPA** and choose the `.ipa`.
5. On the iPhone: **Settings → General → VPN & Device Management**, trust your Apple account; **Settings → Privacy & Security**, turn on **Developer Mode** at the bottom (the phone restarts).
6. Open Best Planner on the iPhone → **Settings** → **Choose the “Best Planner” folder in iCloud Drive** → select it → **Open**. Your iPhone and Mac now use the same data; changes usually arrive within about a minute.
7. Home-screen widget: touch and hold the Home Screen → **Edit** → **Add Widget** → search “Best Planner”.

Notes:
- **A free account's signature expires after 7 days**; the app then won't open (no data is lost — it's all in iCloud). Every 7 days, use **Import IPA** in iloader again; it installs over the old one and keeps your data and settings.
- SideStore's on-device sign-in is currently rejected by Apple (error -80045), so this guide installs with iloader on the Mac instead.
- If syncing stops, look at the diagnostics at the bottom of the iPhone app's Settings: a `save error` other than none means the phone can't write to iCloud; otherwise check that the Mac's iCloud Drive is uploading.

Your data stays on your Mac (`~/Library/Application Support/Planner/`), or in iCloud Drive (folder “Best Planner”) if you turn on iCloud sync.

## Features

- **Board** with your own statuses (name, emoji, color, order, width, “done column”), drag-and-drop and ← → buttons, manual or automatic sorting, search and tag filter
- **Tasks**: notes, subtasks (reorderable, with an optional date and time), several dates (deadline / milestone / start / reminder, each with an optional time of day), stripe and background colors, attachments and links, history
- **Tags**: emoji, 19 shapes, 8 styles, 7 border patterns, separate text / background / border colors, 18 color sets and 14 one-click looks
- **Custom priorities** with names, colors and emoji
- **Progress flags** (on track, struggling, needs follow-up, needs more info, waiting…), customizable, any number per task, shown on cards
- **Contacts / collaborators** on tasks, remembered for reuse, with email and phone; click an email to write in Outlook; manage them in Settings → Contacts
- **Folding** per column: whole column, by tag, by priority or by date; reorder groups by dragging
- **Subtask packs**: reusable subtask lists, added in one click or automatically with a tag
- **Planned moves**: any date can “then move to” a status — e.g. move from To Do to Doing on the start date
- **Repeating tasks** (daily, weekdays, weekly, every 2 weeks, monthly, yearly, or custom: every N days / weeks / months / years, on chosen weekdays such as Mon, Wed, Fri)
- **Reminders** as macOS notifications (per-task on/off)
- **Quick Add** from anywhere with **⌃⌥N** or the menu bar icon — understands `Send draft tomorrow 3pm #Work !urgent @Doing`
- **Agenda** view: open tasks by date, across all statuses
- **Review** view: a calendar of what you got done each day, daily notes, a streak counter and 18 achievements
- **Focus timer** (pomodoro) with your own lengths and focus/break cycles, plus a draggable floating countdown when the window is closed or another app is in front, and an alarm when a period ends (choose the sound or turn it off); and statistics
- Multi-select, duplicate, undo / redo (⌘Z), Recently Deleted (kept 30 days), adjustable text size
- **Cloud sync** (toolbar ☁️, since 1.7.0) between the Mac, the web version and your phone, plus **iCloud Drive sync** between Macs; daily backups (kept 30 days)
- **Desktop widget** (small / medium / large) with subtasks you can tick right on the desktop; the **Widgets** toolbar button chooses which statuses and tags it shows (synced to the iPhone)
- **Web version**: the same board layout and tag styles as the Mac, task editing, subtasks, attachments (Mac files show the device and path), works offline (see “Web version and cloud sync” above)

## Building from source

Only the Command Line Tools are needed (no Xcode): run `xcode-select --install` once, then

```bash
./build.sh
```

builds the app and installs it to `/Applications/Best Planner.app`. To make a release, bump `VERSION` in `build.sh` and run `./build.sh release`; it writes a universal zip and its `.sha256` checksum to `dist/`. Upload **both** to GitHub Releases with the tag `v<version>`; the in-app one-click update downloads the zip and checks it against the `.sha256` (without it, the app just opens the download page).

The iPhone app needs Xcode installed (for the iOS SDK and simulator; there's no Xcode project):

```bash
./build-ios.sh sim   # build and run in the iPhone simulator
./build-ios.sh ipa   # make dist/BestPlanner-iOS-<version>.ipa (unsigned; the installer signs it with your Apple account)
```

Upload the `.ipa` to the release too.

### Translations

UI text is written in Chinese in the code and wrapped in `L("…")`; English lives in `Shared/English.swift`, keyed by the Chinese text (interpolated values become `{}`). Add an entry there whenever you add a new `L("…")`.

### Notes

- The web version runs on Cloudflare (Workers + D1): `cd Web && npx wrangler@4 deploy`. Set the invite code with `npx wrangler@4 secret put INVITE_CODE` — never in code. `Web/src/worker.js` is the server (accounts, sign-in, board storage, gzip in D1, versioned saves with three-way merge on conflict), `Web/public/` the site, `Web/schema.sql` the tables, `App/CloudSync.swift` the Mac client.
- The widget extension must be linked with `-e _NSExtensionMain` (done in `build.sh`), otherwise macOS doesn't recognise it.
- The widget's checkboxes need `Metadata.appintents`, which Xcode would generate; here `Resources/make_intents_metadata.py` writes it. Keep it in sync with `Widget/WidgetIntents.swift`.
