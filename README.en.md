# Best Planner

[中文说明](README.md)

A macOS kanban planner with a desktop widget. Available in English and Chinese.

## Download

1. Go to **[Releases](https://github.com/ziyueupup-ghost/best-planner/releases/latest)** and download `BestPlanner-<version>.zip`. Unzip it and drag `Best Planner.app` into your Applications folder.
2. **macOS will block it the first time** ("can't verify the developer") because the app isn't signed with a paid Apple developer account:
   - Double-click it once and click Done when the warning appears;
   - Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** and confirm. After that it opens normally.
3. Requires macOS 14 (Sonoma) or later. Works on Apple silicon and Intel Macs.
4. Desktop widget: right-click the desktop → Edit Widgets → search for “Best Planner”.
5. Updates: **Best Planner → Check for Updates…** (it also checks once a day).

**Language:** the app follows your system language. To switch, use the 🌐 button in the toolbar or **Best Planner → Language**, then reopen the app.

Your data stays on your Mac (`~/Library/Application Support/Planner/`), or in iCloud Drive (folder “Best Planner”) if you turn on iCloud sync.

## Features

- **Board** with your own statuses (name, emoji, color, order, width, “done column”), drag-and-drop and ← → buttons, manual or automatic sorting, search and tag filter
- **Tasks**: notes, subtasks (reorderable), several dates (deadline / milestone / start / reminder), stripe and background colors, attachments and links, history
- **Tags**: emoji, 19 shapes, 8 styles, 7 border patterns, separate text / background / border colors, 18 color sets and 14 one-click looks
- **Custom priorities** with names, colors and emoji
- **Folding** per column: whole column, by tag, by priority or by date; reorder groups by dragging
- **Subtask packs**: reusable subtask lists, added in one click or automatically with a tag
- **Repeating tasks** (daily, weekdays, weekly, every 2 weeks, monthly, yearly)
- **Reminders** as macOS notifications (per-task on/off)
- **Quick Add** from anywhere with **⌃⌥N** or the menu bar icon — understands `Send draft tomorrow 3pm #Work !urgent @Doing`
- **Agenda** view: open tasks by date, across all statuses
- **Review** view: a calendar of what you got done each day, daily notes, a streak counter and 18 achievements
- **Focus timer** (pomodoro) and statistics
- Multi-select, duplicate, undo / redo (⌘Z), Recently Deleted (kept 30 days), adjustable text size
- **iCloud Drive sync** between Macs, daily backups (kept 30 days)
- **Desktop widget** (small / medium / large) with subtasks you can tick right on the desktop

## Building from source

Only the Command Line Tools are needed (no Xcode): run `xcode-select --install` once, then

```bash
./build.sh
```

builds the app and installs it to `/Applications/Best Planner.app`. To make a release, bump `VERSION` in `build.sh` and run `./build.sh release`; it writes a universal zip to `dist/`. Upload it to GitHub Releases with the tag `v<version>` and the in-app update check will find it.

### Translations

UI text is written in Chinese in the code and wrapped in `L("…")`; English lives in `Shared/English.swift`, keyed by the Chinese text (interpolated values become `{}`). Add an entry there whenever you add a new `L("…")`.

### Notes

- The widget extension must be linked with `-e _NSExtensionMain` (done in `build.sh`), otherwise macOS doesn't recognise it.
- The widget's checkboxes need `Metadata.appintents`, which Xcode would generate; here `Resources/make_intents_metadata.py` writes it. Keep it in sync with `Widget/WidgetIntents.swift`.
