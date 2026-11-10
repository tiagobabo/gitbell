---
version: 1
slug: "docs-index-html"
primary_target: "docs/index.html"
related_targets: []
---

## Scope

The GitBell product page, `docs/index.html`, served by GitHub Pages. Mode: Persuade. Visitors are engineers on busy teams arriving from GitHub, a colleague's link or a post; the action is downloading the DMG. They should leave believing GitBell tells them what to do next. Proof is the real app (demo-data screenshots) and the mechanism working in the page; no invented testimonials, numbers or claims. The user rejected the earlier transit-signage version outright and asked for the alternate direction.

## Direction contract

THESIS: Each pull request is a flight progress strip, and control passes to whoever holds it. The page is an air traffic control strip board, not a dev-tool landing page or station signage: it refuses the dark glow hero with a bento grid.

OWN-WORLD: A grey-green console ground (#d6d9d1) with near-black strip holders and rails (#2b2e2a). Paper strips in pastel stock, one per action (review buff, fix pink, on hold lilac, reply blue, failed after merge orange, merge green, mergeable pale green, re-review plain), split into typed fields by hairline rules: action code tab, PR callsign, title and reason, waiting time. Courier Prime for everything typed on a strip; Barlow Semi Condensed for headings; Barlow for body. Red grease-pencil marks drawn by hand in SVG: a ring round the failing check, a tick on the mergeable one.

STORY: The visitor sees their own morning as a strip bay: what's waiting, why, for how long. They learn every strip colour is an action, their pull requests move bay by bay to production, everything has a key, and setup is three honest steps. They download.

FIRST VIEWPORT: The nav rail, then "Your turn." at display scale with the lede and Download for Mac on the left; on the right, a Your turn bay of six demo strips with a count, a keyboard hint and a Bring back control. The mounted app screenshot starts below the fold edge.

FORM: Flight strip bay, the round's IMPECCABLE'S PICK, chosen by the user's request for the other approach; seed:7cd8f2afbfb105e9. Signature interaction: click a strip, or J/K then E, and it slides out of the bay, hidden until it changes, with the count updating and Bring back restoring them. Motion grammar: strips slide horizontally with exponential ease-out, nothing animates on scroll.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
