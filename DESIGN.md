---
name: GitBell
description: What's waiting on you on GitHub, held as flight progress strips in a bay.
colors:
  console: "#d6d9d1"
  rail: "#2b2e2a"
  rail-slot: "#3a3e39"
  rail-hover: "#3a3d37"
  rail-label: "#cfd2c8"
  rail-edge: "#6c7068"
  ink: "#1c1d1a"
  ink-2: "#464943"
  paper: "#f5f1e6"
  pencil: "#c0362c"
  stock-review: "#f0e1b3"
  stock-rereview: "#f5f1e6"
  stock-fix: "#f2c7bf"
  stock-after: "#f1cf9f"
  stock-hold: "#dcd2ee"
  stock-reply: "#cbdff1"
  stock-merge: "#cae5c4"
  stock-mergeable: "#e1edcf"
  stock-shipped: "#e7e5dc"
  stack-edge: "#8f948a"
typography:
  display:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, sans-serif"
    fontSize: "clamp(60px, 7.4vw, 96px)"
    fontWeight: 700
    lineHeight: 0.92
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, sans-serif"
    fontSize: "clamp(38px, 4.6vw, 60px)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.015em"
  title:
    fontFamily: "Barlow Semi Condensed, Arial Narrow, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Barlow, Helvetica Neue, Arial, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.5
  strip-title:
    fontFamily: "Barlow, Helvetica Neue, Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.3
  strip-field:
    fontFamily: "Courier Prime, Courier New, monospace"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.02em"
  strip-note:
    fontFamily: "Courier Prime, Courier New, monospace"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "Courier Prime, Courier New, monospace"
    fontSize: "13px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.06em"
rounded:
  strip: "2px"
  control: "3px"
  bay: "6px"
  mount: "8px"
spacing:
  strip-gap: "5px"
  bay-pad: "10px"
  field: "8px 12px"
  gutter: "clamp(16px, 4vw, 56px)"
  section: "clamp(80px, 10vw, 140px)"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.control}"
    padding: "15px 22px 15px 18px"
  button-primary-hover:
    backgroundColor: "{colors.rail-hover}"
  button-on-rail:
    backgroundColor: "{colors.stock-review}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "15px 22px 15px 18px"
  button-rail-ghost:
    textColor: "{colors.paper}"
    rounded: "{rounded.control}"
    padding: "9px 12px"
  strip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.strip}"
    height: "66px"
  bay:
    backgroundColor: "{colors.rail}"
    rounded: "{rounded.bay}"
    padding: "12px 12px 14px"
  key:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "1.8em"
  key-on-paper:
    backgroundColor: "{colors.rail}"
    textColor: "{colors.paper}"
    rounded: "{rounded.control}"
    height: "1.8em"
  nav:
    backgroundColor: "{colors.rail}"
    textColor: "{colors.paper}"
    height: "56px"
---

# Design System: GitBell

## Overview

**Creative North Star: "The Strip Bay"**

Each pull request is a flight progress strip, and control passes to whoever holds it. The system is an air traffic control console: a grey-green enamel ground, near-black rails and holders that frame every collection, and paper strips in pastel stock slotted into them, one stock per action. A strip is split by hairline rules into typed fields: an action code tab, a callsign, the title over its reason, and the waiting time. Everything typed on a strip is Courier Prime; the console's own voice is Barlow Semi Condensed for headings and Barlow for running text.

The controller's hand appears only as red grease pencil: a ring drawn round the failing check, a tick on the strip that can go. Those marks are SVG strokes drawn by hand, never icons or badges. Density is a working console: strips pack tight in their holders (5px apart), while the console ground between bays is generous.

Motion is the strip leaving the bay. A handled strip slides out sideways with exponential ease-out; a hovered strip nudges 4px toward the controller. Nothing animates on scroll. The page rejects the dark glow hero with a bento grid.

**Key Characteristics:**
- Grey-green console ground; every collection sits in a near-black rail holder with rounded 6px corners.
- Paper strips, one pastel stock per action, divided into typed fields by 1px hairlines.
- Courier Prime for everything on a strip; Barlow Semi Condensed 700 headings; Barlow 400/600 body.
- Red grease-pencil marks drawn as hand-made SVG strokes, used sparingly as annotation.
- One motion: the horizontal strip slide, exponential ease-out, off under reduced motion.

## Colors

A muted, paper-and-enamel palette: two structural greys (console and rail), warm paper, eight pastel strip stocks that carry action meaning, and one red reserved for the grease pencil.

### Primary
- **Rail Black** (`rail`): strip holders, bays, the nav rail, the board, the closing band and the footer. Every group of strips sits on it.
- **Console Enamel** (`console`): the page ground between bays. Also `theme-color`.

### Secondary
- **Strip Stock** (`stock-*`): one pastel paper per action, always on the whole strip, never as an accent. Review buff (`stock-review`), re-review plain (`stock-rereview`, equal to paper), fix pink (`stock-fix`), failed-after-merge orange (`stock-after`), on hold lilac (`stock-hold`), reply blue (`stock-reply`), merge green (`stock-merge`), mergeable pale green (`stock-mergeable`). Shipped strips on the board use a spent grey stock (`stock-shipped`).

### Tertiary
- **Grease Pencil** (`pencil`): only in hand-drawn SVG marks (ring, tick). Never text, never fills, never UI state.

### Neutral
- **Console Ink** (`ink`): all text on console and paper; the primary button; focus rings on light surfaces; text selection.
- **Typed Grey** (`ink-2`): secondary copy, ledes, strip sub-fields (6.4:1 on console, 6.0:1 or better on every stock).
- **Strip Paper** (`paper`): plain strip stock, cards, keycaps on the rail, text on the rail.
- **Rail Slot** (`rail-slot`): a stage column inside the board, one step up from the rail.
- **Rail Hover** (`rail-hover`): primary button hover.
- **Rail Label** (`rail-label`): muted mono text on the rail (nav links, bay head and foot, close meta).
- **Rail Edge** (`rail-edge`): the outline of the ghost control on the rail.
- **Stack Edge** (`stack-edge`): the edge of the strip behind a stacked strip.
- Hairlines inside strips are ink at 28% (`rgba(28,29,26,.28)`); the code tab and number tab are ink at 8% over the stock; strip outlines are an inset 1px of black at 18%.

### Named Rules
**The Stock Is the Action Rule.** A strip's paper colour names its action, identically everywhere (hero bay, legend, board, install steps). Never use a stock for anything that is not a strip, a strip field, or a step that adopts a strip's meaning.

**The Pencil Rule.** Red appears only as grease pencil drawn over paper. If it isn't a hand-drawn mark, it isn't red.

## Typography

**Display Font:** Barlow Semi Condensed (with Arial Narrow, sans-serif)
**Body Font:** Barlow (with Helvetica Neue, Arial, sans-serif)
**Label/Mono Font:** Courier Prime (with Courier New, monospace)

**Character:** A condensed console face for the board's printed labels, a plain humanist sans for the manual, and a typewriter for everything the controller typed onto a strip.

### Hierarchy
- **Display** (700, clamp(60px, 7.4vw, 96px), 0.92): the hero "Your turn." and the closing line only.
- **Headline** (700, clamp(38px, 4.6vw, 60px), 1): one per section head, beside its lede in a 5/7 split.
- **Title** (700, 22-32px, 1.2): install step names, facts, sub-heads.
- **Body** (400, 18px, 1.5): running copy; ledes at clamp(18px, 1.5vw, 20px) in Typed Grey, capped at 58ch; emphasis is Barlow 600 in Console Ink.
- **Strip Title** (Barlow 600, 17px, 1.3): the PR title on a strip, single line with ellipsis on wide screens.
- **Strip Field** (Courier Prime 700, 19px): callsign and waiting time.
- **Strip Note** (Courier Prime 400, 13-14px): reason line, author, captions, meta, footer.
- **Label** (Courier Prime 700, 11.5-14px, 0.05-0.08em, uppercase): action code tabs, nav links, bay heads, stage names, timeline field names.

### Named Rules
**The Typed Strip Rule.** Anything written on a strip, a key, a timeline or a rail label is Courier Prime. The one exception is the strip title, which stays in Barlow 600 for reading.

**The Uppercase Is Printed Rule.** Uppercase with tracking belongs to printed console labels (code tabs, stage names, nav, bay heads). Headings and prose stay sentence case.

## Layout

A centred wrap of `min(1320px, 100% - 2 * gutter)` with a fluid gutter. Sections open with clamp(80px, 10vw, 140px) of console above them. The hero is a 4.4/7.6 grid (copy left, live bay right) that stacks under 980px; section heads are a 5/7 grid (headline left, lede right, bottom-aligned) that stacks under 860px.

Collections are always bays: a rail holder with 10-12px padding and strips 5-6px apart. The legend is two strip columns (one under 800px); the stage board is six columns, three under 1000px, two under 560px. Strips use fixed field columns (code 6.6em, callsign 8.4em, flexible title, time 4.6em); under 640px the callsign field drops and titles wrap.

## Elevation & Depth

Depth is physical, not ambient: paper sits in holders. Strips carry no cast shadow, only a 1px inset outline. The rail is the frame; paper inside a frame (timeline, keys card) gets a 5px rail ring drawn as a spread shadow, so it reads as slotted. Only the bay and the screenshot mount cast a soft shadow onto the console, with a 1px light lip on top as if set into the enamel.

### Shadow Vocabulary
- **Strip outline** (`box-shadow: inset 0 0 0 1px rgba(0,0,0,.18)`): every strip and mini strip.
- **Holder ring** (`box-shadow: inset 0 0 0 1px rgba(0,0,0,.18), 0 0 0 5px #2b2e2a`): a single paper panel slotted in a rail (timeline, keys card).
- **Bay set-in** (`box-shadow: 0 1px 0 rgba(255,255,255,.5), 0 18px 40px -24px rgba(0,0,0,.55)`): the hero bay.
- **Mount set-in** (`box-shadow: 0 1px 0 rgba(255,255,255,.5), 0 30px 60px -36px rgba(0,0,0,.6)`): screenshot mounts.
- **Stacked strip** (`box-shadow: inset 0 0 0 1px rgba(0,0,0,.18), -4px 4px 0 -1px #8f948a`): a second strip of paper behind one in a stack. It represents a physical strip and appears only on stacks.

### Named Rules
**The Paper Doesn't Float Rule.** Strips never cast shadows and never lift on hover. Depth comes from the holder, not from elevation.

## Shapes

Nearly square. Strips and paper fields 2px, controls and keycaps 3px, bays and holders 6px, screenshot mounts 8px (with the image at 4px inside). Fields are divided by straight 1px hairlines; key lists use 1px dashed rules at 40% ink. The only curves are the grease-pencil strokes, round-capped at 2.4px and drawn loosely by hand.

## Components

### Buttons
- **Shape:** squared (3px).
- **Primary:** Console Ink with paper text, Barlow Semi Condensed 700 at 20px, a solid SVG download arrow at 22px leading. 15px 22px 15px 18px.
- **Hover / Focus:** background eases to Rail Hover over 0.2s with exponential ease-out; 3px ink outline offset 3px on light ground.
- **On the rail:** review-buff stock with ink text, lightening to `#fff3cf` on hover.
- **Rail ghost:** transparent, uppercase Courier Prime 700 at 13.5px, 1px Rail Edge outline turning white on hover; 45% opacity when disabled.

### Strip (signature)
- A paper strip in its action stock, 66px minimum, 2px corners, inset outline, split into typed fields by 1px hairlines.
- Fields: uppercase code tab on an 8% ink tint; callsign in Courier Prime 700 over the author; Barlow 600 title over a Courier reason line; waiting time right-aligned in Courier 700 over an uppercase unit.
- Interactive strips in a bay nudge right 4px on hover and slide out (`translateX(110%)`, fade) over 0.45s with exponential ease-out when handled. Variants reuse the same stock and field grammar: legend strips (code plus description), install strips (number tab plus step), mini strips on the board.

### Bay / Holder
- Rail Black, 6px corners, 10-12px padding, strips 5px apart. A bay head and foot in Rail Label Courier carry the count and controls.

### Grease Pencil Mark
- Absolutely positioned SVG, `pencil` stroke at 2.4px, round caps and joins, non-scaling stroke, no fill, `aria-hidden`. Two marks exist: a loose ring round a failing check name, and a tick near the waiting time of a mergeable strip.

### Keycap
- Inline grid, 1.8em square minimum, 3px corners, Courier Prime 700. Paper on the rail; rail with paper text on paper.

### Navigation
- The console's top rail: Rail Black, 56px, brand in Barlow Semi Condensed 700 at 22px with the app icon; links in uppercase Courier Prime 700 at 14px, Rail Label turning white and underlined on hover. Features drops under 520px.

## Do's and Don'ts

### Do:
- **Do** put every collection of items in a rail holder, as strips 5-6px apart.
- **Do** give every action its own stock and use it identically on every surface.
- **Do** type everything on a strip in Courier Prime, with fields split by 1px hairlines at 28% ink.
- **Do** keep red to hand-drawn grease-pencil SVG marks, sparingly, one mark per strip at most.
- **Do** keep motion to the horizontal strip slide with `cubic-bezier(.16,1,.3,1)`, and turn it off under `prefers-reduced-motion`.
- **Do** mount app screenshots in a rail frame (8px corners, 4px on the image) with the mount set-in shadow.

### Don't:
- **Don't** use a strip stock as a panel fill, an accent, or a text colour.
- **Don't** use red for text, UI state, or error badges; it is the controller's pencil.
- **Don't** cast shadows from strips or lift them on hover; depth belongs to holders.
- **Don't** animate on scroll.
- **Don't** set a dark glow hero over a screenshot, or a bento grid of feature cards.
