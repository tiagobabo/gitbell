# GitBell

GitHub notifications and pull requests in a native Mac app.

![GitBell](docs/gitbell.png)

- **Your turn:** everything waiting on you in one list: reviews, re-reviews, fixes (with the failing checks named), replies, CircleCI jobs on hold, merges that failed afterwards, and pull requests ready to merge. The Dock icon counts them. Press E to hide one until it changes.
- **Your pull requests:** each of yours from draft to live, by stage, with what it's waiting on and for how long.
- **Timelines:** press T for a pull request's history, from opening to deploy, with how long each step took.
- **Stacks:** pull requests based on each other's branches are shown together.
- **Notifications:** for review requests, failing checks, requested changes, merges ready to go, deploys, and checks failing after a merge.
- **Like Mail:** a sidebar of pages and groups with counts, search at the top, Liquid Glass on macOS 26, and menus and keyboard shortcuts for everything (J K to move, O to open, ⌘F to search).
- **Menu bar:** an optional icon that opens the window or a compact popover.
- **People filter:** only show activity from the people and teams you pick.

## Install

Download the latest DMG from [Releases](https://github.com/tiagobabo/gitbell/releases) and drag GitBell to Applications. Requires macOS 14 or later.

GitBell isn't notarised yet, so macOS blocks it the first time. Open System Settings → Privacy & Security and click "Open Anyway", or run:

```sh
xattr -dr com.apple.quarantine /Applications/GitBell.app
```

Allow notifications, with badges, when asked during setup so the Dock icon can count what's waiting on you.

GitBell updates itself with [Sparkle](https://sparkle-project.org).

## Sign in

GitBell uses your [GitHub CLI](https://cli.github.com) login if you have one. Otherwise paste a [classic personal access token](https://github.com/settings/tokens/new?scopes=notifications,repo,read:org&description=GitBell) with the `notifications`, `repo` and `read:org` scopes. It's kept in your Keychain. A CircleCI token is optional, for approving held jobs.

## Privacy

Release builds send anonymous usage counts to [TelemetryDeck](https://telemetrydeck.com) and crash reports to [Sentry](https://sentry.io), never your token or any names. Turn it off in Settings → General → Privacy. Builds from source send nothing.

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/tiagobabo/gitbell.git
cd gitbell
./build.sh --install
```

`GITBELL_DEMO=1 build/GitBell.app/Contents/MacOS/GitBell` runs it with made-up data.

## License

[MIT](LICENSE). Icons from GitHub's [Octicons](https://github.com/primer/octicons).
