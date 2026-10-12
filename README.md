# GitBell

GitHub notifications and pull requests in a native Mac app.

![GitBell](docs/gitbell.png)

- **Inbox:** unread notifications grouped by repository, each saying who commented, approved, pushed or merged.
- **Pull requests:** review requests for you and your team, and your own PRs by status, with checks.
- **Menu bar:** an optional menu bar icon that opens the window or a compact popover.
- **Banners:** a notification when someone requests your review.
- **People filter:** only show activity from the people and teams you pick.
- **Keyboard:** ↑ ↓ or J K to move, Return or O to open, E done, M read, U unsubscribe.

## Install

Download the latest DMG from [Releases](https://github.com/tiagobabo/gitbell/releases) and drag GitBell to Applications. Requires macOS 14 or later.

GitBell isn't notarised yet, so macOS blocks it the first time. Open System Settings → Privacy & Security and click "Open Anyway", or run:

```sh
xattr -dr com.apple.quarantine /Applications/GitBell.app
```

GitBell updates itself with [Sparkle](https://sparkle-project.org): it checks for a new release once a day and asks before installing. If you're on 0.3.0, install the latest release by hand once.

## Sign in

GitBell uses your [GitHub CLI](https://cli.github.com) login if you have one. Otherwise paste a [classic personal access token](https://github.com/settings/tokens/new?scopes=notifications,repo,read:org&description=GitBell) with the `notifications` and `repo` scopes (plus `read:org` to filter by team). It's stored in your Keychain. After an update macOS may ask once whether GitBell can read it; click "Always Allow".

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/tiagobabo/gitbell.git
cd gitbell
./build.sh --install
```

`GITBELL_DEMO=1 build/GitBell.app/Contents/MacOS/GitBell` runs it with made-up data, which is handy for screenshots.

## License

[MIT](LICENSE). Icons from GitHub's [Octicons](https://github.com/primer/octicons).
