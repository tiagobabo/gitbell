# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The design work this file covers is the product website in `docs/`, served by GitHub Pages (tiagobabo.github.io/gitbell, moving to gitbell.dev). The product itself is a native macOS app written in Swift and SwiftUI; its UI is out of scope here, but the site must show it truthfully.

## Users

Engineers on busy teams who review and ship many pull requests a day on GitHub, usually across company organisations, with CI (often CircleCI) and deploys in the loop. They lose time hopping between GitHub tabs, notification emails and CI dashboards to work out what is actually waiting on them.

## Product Purpose

GitBell is a Mac app for GitHub notifications and pull requests. It turns GitHub activity into what to do next: everything waiting on you in one list, and each of your own pull requests followed from draft to deployed. Success is a developer who stops checking GitHub to find out whether it's their turn.

## Positioning

GitBell tells you what to do, not what happened. GitHub's notifications are a feed of events; GitBell's "Your turn" list sorts them into actions (review, re-review, fix, reply, approve a held CI job, deal with a failed merge, merge) and names the reason, such as which check broke. Your pull requests are tracked by stage through review, merge and deploy, with how long each step took.

## Operating Context

- Lives on the developer's Mac all day: a Mail-like window, an optional menu bar icon and popover, a Dock badge counting what's waiting, and macOS notifications.
- Keyboard driven: J/K to move, O to open, E to hide an item until it changes, T for a pull request's timeline, ⌘F to search.
- Signs in with the GitHub CLI login or a classic personal access token (`notifications`, `repo`, `read:org`), kept in the Keychain. A CircleCI token is optional, for approving held jobs.
- Visitors to the site arrive from GitHub, a link from a colleague, or a post; they decide whether to download a DMG.

## Capabilities and Constraints

- Pages: Your turn (Review, Re-review, Fix, Failed after merge, On hold, Reply, Merge, Mergeable) and Your pull requests (Drafts, In review, Needs fixing, Ready to merge, Shipping, Shipped).
- Stacks: pull requests based on each other's branches show together.
- Filters by organisation, personal repositories, and people and teams.
- Requires macOS 14 or later; Liquid Glass on macOS 26. Updates itself with Sparkle.
- Not notarised yet: first launch needs System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine /Applications/GitBell.app`. The site must say so plainly.
- Distributed as a DMG from GitHub Releases; the site's download buttons resolve the latest DMG from the GitHub API.
- Free, MIT licensed, open source. Not affiliated with GitHub.
- The site is static HTML and CSS in `docs/`, with no build step.

## Brand Commitments

- Name: GitBell (one word, capital G and B).
- App icon: the GitHub mark on a dark rounded square with a blue notification dot (`docs/assets/icon.png`, source `Resources/AppIcon.icns`).
- Icons in the app are GitHub's Octicons.
- Voice: plain, short, concrete sentences in British English. Say what the app does and what the user does, without marketing superlatives.
- Site look: follows Apple's product-page conventions and the app's own macOS look (system font, white and #f5f5f7 sections, blue pill buttons, real window screenshots). The user asked for this after rejecting two themed directions. No Apple logos, names or trade dress beyond that general style.

## Evidence on Hand

- Real app screenshots from the built-in demo data (`GITBELL_DEMO=1`): `docs/assets/hero-light.png`, `docs/assets/hero-dark.png`, `docs/assets/yours-dark.png` (window with macOS shadow, 2x) and crops `docs/assets/crop-*.png`.
- Feature overview image: `docs/gitbell.png`.
- Demo data uses made-up repos and people (alice, bob, carol, web#482, api#1203); it is not real usage.
- No testimonials, customer logos, usage numbers or press exist. Do not invent any.

## Product Principles

1. Actions over events: show what to do next and why, never a raw feed.
2. Calm by default: only what's waiting on you, with ways to hide the rest.
3. Native and quick: behaves like a Mac app, with a keyboard shortcut for everything.
4. Honest about setup: state the macOS version, the token scopes, telemetry and the notarisation step up front.
5. Private: talks to GitHub from the user's Mac; anonymous usage counts and crash reports in release builds only, never tokens or names, and they can be turned off.
