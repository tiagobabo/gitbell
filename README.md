# GitBell

A native macOS app for your GitHub notifications and pull requests. It lives in the Dock and, optionally, the menu bar, and comes with a desktop widget.

- **Inbox:** your unread GitHub notifications, grouped by repository. Each row says what happened (who commented, approved, pushed or merged), and clicking it opens that comment or review on GitHub.
- **Pull requests:** an overview like github.com/pulls/inbox. Review requests for you and your team, plus your own PRs split into needs fixing, ready to merge, in review and drafts, with status and checks.
- **Actions:** mark as read, mark as done, unsubscribe, or mark a whole repository or everything as read.
- **Window or menu bar:** a full window with a sidebar and search, and an optional menu bar icon that opens either the window or a compact popover.
- **Banners:** a macOS notification when someone requests your review.
- **People filter:** only show activity from certain people or teams, for example `carwow/banjo`.
- **Desktop widget:** small, medium and large sizes. Pick the sections it shows in Edit Widget, switch tabs and fold sections right in the widget.
- **Keyboard:** ↑ ↓ or J K to move, Return or O to open, E done, M read, U unsubscribe.

## Requirements

- macOS 14 or later
- Xcode, installed from the App Store and opened once (or run `sudo xcodebuild -runFirstLaunch`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), which generates the Xcode project from `project.yml`
- The [GitHub CLI](https://cli.github.com) is optional but makes signing in a one-click step

```sh
brew install xcodegen gh
```

If `xcode-select -p` doesn't print a path inside `Xcode.app`, point it there:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build and install

```sh
git clone git@github.com:tiagobabo/gitbell.git
cd gitbell
./build.sh --install
```

This generates `GitBell.xcodeproj`, builds a release version into `build/GitBell.app`, copies it to `~/Applications` and opens it. Run it again after pulling changes. `./build.sh` on its own builds without installing.

The app is signed to run locally only (no Apple developer account needed), so it's meant for the Mac it was built on.

## Sign in

On first launch GitBell looks for a GitHub CLI login and uses it automatically. If you haven't got one:

- **GitHub CLI:** run `gh auth login`, then click "Continue with GitHub CLI".
- **Personal access token:** create a [classic token](https://github.com/settings/tokens/new?scopes=notifications,repo,read:org&description=GitBell) with the `notifications` and `repo` scopes, plus `read:org` if you want to filter by team, and paste it in. It's stored in your Keychain.

Fine-grained tokens can't read notifications, so it has to be a classic token.

## Settings

Open them with ⌘, or from the right-click menu on the menu bar icon.

- **Show menu bar icon:** on by default. The Dock icon always opens the window.
- **Menu bar icon opens:** the window or the compact popover. Right-click the icon for both.
- **Launch at login.**
- **People:** turn on "Only show activity from these people" and list GitHub usernames and/or `org/team`, separated by commas. It filters the inbox and review requests; your own pull requests always show.
- **Banners:** for review requests from you directly, and optionally for team requests.

With the menu bar icon on, quitting from the Dock or with ⌘Q keeps GitBell running in the menu bar. Use Quit GitBell in the menu bar menu to quit it completely.

## Desktop widget

Right-click the desktop, choose Edit Widgets and search for GitBell. Right-click a placed widget and choose Edit Widget to pick its sections.

The widget reads what the app last fetched, so GitBell needs to be running for it to update.

## Troubleshooting

- **Widget missing or looks stale after an update:** remove it and add it again. If the gallery still shows an old version, restart the widget service with `killall chronod NotificationCenter`; both come back on their own.
- **"Review requests" shows a PR you've already reviewed:** that list follows GitHub's search for PRs still waiting on you, which updates within a couple of minutes.
- **Nothing loads:** check the dot at the bottom of the sidebar. If your token expired, GitBell signs you out and asks again.

## Project layout

```
project.yml              XcodeGen project: app, widget extension and a shared framework
build.sh                 Build, and with --install copy to ~/Applications and launch
Sources/GitBell          The app: window, popover, settings, GitHub client, store
Sources/GitBellShared    Code used by both app and widget: models, palette, Octicons
Sources/GitBellWidget    The WidgetKit extension and its App Intents
Resources                Info.plists, widget entitlements, app icon
scripts/make-icon.swift  Regenerates Resources/AppIcon.icns
```

Icons are from GitHub's [Octicons](https://github.com/primer/octicons) (MIT).
