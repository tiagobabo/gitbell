# GitBell

GitHub notifications and pull requests in a native Mac app.

![GitBell](docs/gitbell.png)

- **Your turn:** everything waiting on you in one list: pull requests to review, your pull requests to fix (failing checks named, one click from their logs, plus conflicts and requested changes), threads to reply to, pull requests ready to merge, and approved ones you can merge while optional checks are still running. Checks your branch protection doesn't require never hold a pull request back. Merges that broke the build in the last two days show up too. Notifications about a pull request fold into it instead of showing twice. Press E to hide an item until something changes on it, or show hidden items again with the eye button. The Dock icon counts these.
- **Inbox:** unread notifications grouped by repository, each saying who commented, approved, pushed or merged.
- **Pull requests:** review requests for you and your team, and your own PRs by status, with checks.
- **Merged:** your pull requests merged in the last week, and how their merge commits did: deploying, deployed, failing after merge, or cancelled by a newer merge. Deploys are recognised by name (CircleCI's `deploy_*` jobs and the like).
- **Repositories:** the repos you work in, ranked by your pull requests and reviews, plus pins. Each has a page with its main branch's checks, open pull requests, merges and time to merge over the last 30 days, and who's shipping. ⌘K jumps to any repo in your organizations.
- **Organizations:** a map of each organization's repositories, sized by commits or open pull requests over the last 30 days and coloured by language. Click a tile to open that repository.
- **Menu bar:** an optional menu bar icon that opens the window or a compact popover.
- **Notifications:** when someone requests your review, when checks fail on your pull request, or when it's ready to merge.
- **Appearance:** light, dark or follow the system.
- **People filter:** only show activity from the people and teams you pick.
- **Keyboard:** ↑ ↓ or J K to move, Return or O to open, E done, M read, U unsubscribe, C copy link, ⌘K go to repository.

## Install

Download the latest DMG from [Releases](https://github.com/tiagobabo/gitbell/releases) and drag GitBell to Applications. Requires macOS 14 or later.

GitBell isn't notarised yet, so macOS blocks it the first time. Open System Settings → Privacy & Security and click "Open Anyway", or run:

```sh
xattr -dr com.apple.quarantine /Applications/GitBell.app
```

GitBell asks to send notifications on first launch. Allow it, with badges on, so the Dock icon can show how many things are waiting on you; you can change this later in System Settings → Notifications → GitBell.

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
