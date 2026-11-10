---
name: GitBell
description: What's waiting on you on GitHub, signed like a station.
colors:
  sign: "#121212"
  sign-ink: "#ffffff"
  sign-dim: "#b9b9b9"
  sign-rule: "#2b2b2b"
  wall: "#fafaf8"
  ink: "#121212"
  ink-2: "#4a4a46"
  code-tint: "#e7e7e1"
  edge: "#fccc0a"
  line-review: "#c9470a"
  line-rereview: "#fccc0a"
  line-fix: "#d62a22"
  line-after: "#996633"
  line-hold: "#b933ad"
  line-reply: "#0039a6"
  line-merge: "#00843a"
  line-mergeable: "#6cbe45"
typography:
  display:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(56px, 8.4vw, 96px)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(30px, 4.8vw, 60px)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "22px"
    fontWeight: 800
    lineHeight: 1.3
    letterSpacing: "-0.01em"
  row-title:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(18px, 1.6vw, 21px)"
    fontWeight: 700
    lineHeight: 1.25
    fontFeature: "tnum"
  lede:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(19px, 1.6vw, 22px)"
    fontWeight: 400
    lineHeight: 1.45
  body:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "tnum"
  label:
    fontFamily: "Aileron, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1
  code:
    fontFamily: "ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.5
rounded:
  plate-sm: "4px"
  key: "5px"
  plate: "6px"
  screen: "12px"
  pill: "999px"
  bullet: "50%"
spacing:
  xs: "6px"
  sm: "14px"
  md: "18px"
  lg: "32px"
  gutter: "clamp(16px, 4vw, 56px)"
  section: "clamp(72px, 9vw, 128px)"
  max: "1320px"
components:
  exit-plate:
    backgroundColor: "{colors.sign-ink}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.plate}"
    padding: "16px 22px 16px 18px"
  exit-plate-hover:
    backgroundColor: "{colors.edge}"
  exit-plate-on-wall:
    backgroundColor: "{colors.sign}"
    textColor: "{colors.sign-ink}"
    rounded: "{rounded.plate}"
    padding: "16px 22px 16px 18px"
  line-bullet:
    backgroundColor: "{colors.line-review}"
    textColor: "{colors.sign-ink}"
    rounded: "{rounded.bullet}"
    size: "1.75em"
  line-bullet-dark:
    backgroundColor: "{colors.line-mergeable}"
    textColor: "{colors.ink}"
    rounded: "{rounded.bullet}"
    size: "1.75em"
  line-selector:
    backgroundColor: "transparent"
    textColor: "{colors.sign-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 14px 6px 6px"
  line-selector-pressed:
    backgroundColor: "{colors.sign-ink}"
    textColor: "{colors.ink}"
  key-plate:
    backgroundColor: "{colors.sign}"
    textColor: "{colors.sign-ink}"
    rounded: "{rounded.key}"
    height: "1.9em"
    padding: "0 .45em"
  train-tag:
    backgroundColor: "{colors.sign}"
    textColor: "{colors.sign-ink}"
    rounded: "{rounded.plate-sm}"
    padding: "6px 10px"
  code-block:
    backgroundColor: "{colors.sign}"
    textColor: "{colors.sign-ink}"
    typography: "{typography.code}"
    rounded: "{rounded.plate}"
    padding: "14px 16px"
---

# Design System: GitBell

## Overview

**Creative North Star: "The Station Sign"**

A sign tells you where to go next; GitBell tells you what to do next. The system is a station's signage: a white glazed subway-tile wall as the ground, black enamel sign bands running edge to edge at full strength, white Aileron set tight and bold on the black, and colour carried only by the transit devices that carry it in a real station: round line bullets, the line map's line, and the yellow platform edge. Text itself stays black and white.

Every band carries one instruction ("Every reason has a line", "Everything has a key"), the way a sign gives one direction. Information is set as a departure board: a bullet, a title, a reason, and a waiting time in a fixed tabular field at the right. Under each band the wall reads like the poster rail beside a platform: ruled lists, a legend, a line map, flat black key plates. Density is moderate; the wall breathes, the signs are packed and decisive.

Motion belongs to the sign, not the scroll. A departure row changes like a sign updating: a short vertical flip with exponential ease-out, once per change. Nothing animates on scroll.

**Key Characteristics:**
- Black enamel bands with a white hairline 7px below their top edge, full bleed.
- White subway-tile wall ground (raster `docs/assets/tile-wall.webp`, 240 x 120 CSS px per repeat).
- One self-hosted neo-grotesque, Aileron, at 400 / 700 / 800; display set at 800 with negative tracking.
- One colour per action, worn only by a round bullet with a single letter.
- Yellow platform-edge strip with a dot texture closes a sign and meets the wall.
- Tabular numerals everywhere; waiting time is always right-aligned.

## Colors

Black and white do all the reading; a fixed set of transit line colours does all the signalling.

### Primary
- **Enamel Black** (`sign`): the sign bands, nav, close band, footer, key plates, train tags and code blocks. Owned edge to edge, never tinted or gradiented.
- **Sign White** (`sign-ink`): headings and primary text on the sign, the white hairline, the exit plate face and the pressed line selector.

### Secondary
- **Platform Yellow** (`edge`): the platform-edge strip, the exit plate hover, the "you are here" stop on the line map, focus rings, text selection and the skip link. It is the system's one highlight colour.

### Tertiary: the line colours
Each action owns one colour and one letter. These colours appear only inside line devices.
- **Review Orange** (`line-review`), letter R.
- **Re-review Yellow** (`line-rereview`), letter P. Same value as Platform Yellow; it carries black text.
- **Fix Red** (`line-fix`), letter F.
- **Failed-after-merge Brown** (`line-after`), letter X.
- **On-hold Purple** (`line-hold`), letter H.
- **Reply Blue** (`line-reply`), letter C. Also the line on the pull-request line map.
- **Merge Green** (`line-merge`), letter M.
- **Mergeable Lime** (`line-mergeable`), letter G. Carries black text.

### Neutral
- **Signal Grey** (`sign-dim`): secondary text on the sign (reasons, counts, captions, inactive nav), 9.6:1 on Enamel Black.
- **Sign Rule** (`sign-rule`): 1px dividers within the sign (hero top, footer top, departure rows).
- **Glaze White** (`wall`): the tile-wall ground colour under the raster.
- **Wall Ink** (`ink`): primary text and rules on the wall, and the numbered step discs.
- **Poster Grey** (`ink-2`): secondary text on the wall, 8.3:1 on Glaze White.
- **Grout Tint** (`code-tint`): background of inline code on the wall only.

### Named Rules
**The Line Colour Rule.** A line colour appears only in a line device: a bullet, the line-map line, or a stop ring. Never on text, never as a panel fill, never as a gradient.

**The Letter-on-Light Rule.** Bullets on Re-review Yellow and Mergeable Lime carry Wall Ink letters; every other bullet carries white.

**The One Highlight Rule.** Platform Yellow is the only interaction and attention colour: focus, hover on the exit plate, selection, "here". Do not introduce a second accent.

## Typography

**Display Font:** Aileron (with Helvetica Neue, Helvetica, Arial)
**Body Font:** Aileron
**Label/Mono Font:** ui-monospace / SF Mono for code only

**Character:** One neo-grotesque doing the job of a signage alphabet: heavy and tightly tracked on the sign, plain and roomy on the wall.

### Hierarchy
- **Display** (800, clamp 56-96px, 0.95): the hero "Your turn" and the closing line only.
- **Headline** (800, clamp 30-60px, 1): one instruction per sign band.
- **Title** (800, 19-24px, 1.3, -0.01em): legend entries, line-map stations, service notes, install steps, exit plate text (21px).
- **Row title** (700, clamp 18-21px, 1.25): departure-row titles and waiting times; single line with ellipsis above 600px.
- **Lede** (400, clamp 19-23px, 1.35-1.45): the intro under each sign, max 62ch on the wall, 34ch on the hero.
- **Body** (400, 18px, 1.5; 15-17px in lists): wall copy, max 72ch.
- **Label** (700, 14-16px, 1): nav, line-selector chips, train tags, captions (400, 13-15px).

### Named Rules
**The Tabular Rule.** Numerals are tabular on every surface (`font-variant-numeric: tabular-nums` on body). Waiting times sit right-aligned in a fixed minimum width.

**The Three Weights Rule.** Aileron ships at 400, 700 and 800 only. Emphasis inside sentences is 700 in the brighter ink of the surface (white on the sign, Wall Ink on the wall), never colour.

## Layout

A single centred column, `min(1320px, 100% - 2 x gutter)` with a fluid gutter (16-56px). Sign bands run full bleed; their content sits in the column. Sections start `clamp(72px, 9vw, 128px)` apart, each with a band sign followed by wall content beneath at `clamp(28px, 3.5vw, 44px)`.

The hero is a two-column grid (instruction left, exit plate right) that collapses to one column at 860px with the exit plate moving under the board. Wall content uses ruled lists rather than cards: two-column legend and keys (one column under 760px), three-column notes, steps and facts (two then one column), a 5:7 split for timeline and screenshot (stacked under 900px). The line map runs six stations horizontally and turns vertical at 860px, its line moving to the left edge.

The app screenshot rises from behind the platform edge: it overlaps the strip by 14px, with the strip drawn above it.

## Elevation & Depth

The system is flat. Depth is the physical order of a station: the sign band, the yellow edge strip in front of it, and the wall behind. The only cast shadow is under the app screenshot, mounted on the wall like a lit poster; everything else is flat colour and rules.

### Shadow Vocabulary
- **Mounted screen** (`box-shadow: 0 1px 2px rgba(0,0,0,.12), 0 24px 60px -20px rgba(0,0,0,.28)`): app screenshots on the wall only.
- **Chip outline** (`box-shadow: inset 0 0 0 1.5px #3a3a3a`, `#8a8a8a` on hover): the line-selector chip border, drawn inset so it never shifts layout.

### Named Rules
**The Enamel Rule.** Signs, plates and keys are flat: no shadows, no gradients, no glow. A sign is a painted panel.

## Shapes

Rectangles with small, consistent corners, and circles for bullets and stops. Sign bands are square and full bleed. Plates and code blocks take 6px, key plates 5px, train tags 4px, screenshots 12px (the app window's own corner; flat top where one rises from the edge). Line-selector chips are full pills. Bullets, stops and step numbers are perfect circles. Rules are the structure of the wall: 2px Wall Ink above a group, 1px between items.

## Components

### Line Bullet (signature)
The system's unit of meaning: one circle, one letter, one action.
- **Shape:** circle, 1.75em, sized by font-size (15px in chips, 19px on the board, 22px in the legend).
- **Colour:** the action's line colour; letter 800 white, or Wall Ink on yellow and lime.
- **Use:** always paired with its action; letters are fixed (R, P, F, X, H, C, M, G).

### Departure Board
- Rows on the sign: bullet, title over reason, waiting time at the right with "waiting" beneath in Signal Grey.
- 2px white rule on top, 1px Sign Rule between rows, 11px vertical padding.
- **Motion:** a changed row flips in once: 0.5s `cubic-bezier(.16,1,.3,1)`, from 10px above with a top-down clip reveal, staggered 40ms per row. Off under reduced motion.

### Line Selector (chips)
- **Style:** transparent pill on the sign with an inset 1.5px outline, bullet inside, count in Signal Grey.
- **State:** pressed is a white pill with Wall Ink text and no outline; hover brightens the outline; disabled at 45% opacity. Transitions 0.2s with the same ease-out.

### Exit Plate (primary button)
- **Shape:** 6px corners, 30px arrow glyph drawn as SVG, 800 weight at 21px.
- **On the sign:** white plate, Wall Ink text; hover turns the plate Platform Yellow.
- **On the wall:** Enamel Black plate, white text; hover `#333`.
- **Focus:** 3px Platform Yellow outline, 3px offset (global).

### Key Plate
Flat Enamel Black keycap, white 800 letter, 5px corners, min 1.9em square; set inline in copy or paired in key lists.

### Line Map
Six stations in fixed order on a 10px Reply Blue line with 5px rounded ends. Stops are 40px white discs with a 6px blue ring; the current stop fills Platform Yellow. A black train tag names the pull request at the stop.

### Navigation
On the enamel band: app icon and "GitBell" (800, 22px) left; links right in Signal Grey 700 16px, each with a transit-style direction arrow (down for in-page, right for outbound), white on hover. Features hides under 520px.

### Platform Edge
A 26px Platform Yellow strip with a 13px grid of dark dots (14% black), between a sign and the wall.

## Do's and Don'ts

### Do:
- **Do** open every section with a full-bleed black band carrying the white hairline 7px from its top and one instruction.
- **Do** give every action its bullet, letter and line colour, and use them identically everywhere.
- **Do** put waiting time on every listed item, right-aligned, in tabular numerals.
- **Do** draw arrows as solid transit arrows in SVG, pointing in the direction of travel.
- **Do** keep wall content as ruled lists: 2px Wall Ink above a group, 1px between items.
- **Do** keep motion to the row flip; respect `prefers-reduced-motion`.

### Don't:
- **Don't** use a line colour on text, panels, backgrounds or gradients.
- **Don't** add a second accent; Platform Yellow is the only highlight.
- **Don't** put shadows, gradients or glow on signs, plates or keys; only mounted screenshots cast a shadow.
- **Don't** set the dark glow hero over a screenshot, or a bento grid of feature cards.
- **Don't** animate on scroll.
- **Don't** add Aileron weights beyond 400, 700 and 800, or a second display face.
