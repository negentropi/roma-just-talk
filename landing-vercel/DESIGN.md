# Roma Just Talk Landing Design Contract

Purpose: exploration contract for the tiny static `landing-vercel` site. Do not add Open Design, React, animation libraries, or design-system packages to production until a direction proves itself in plain HTML/CSS.

## Product Read

Roma Just Talk is a Mac dictation tool for people who already write fast but lose ideas to the usual dictation startup delay.

Core sentence:

> Say first. Press later.

Support sentence:

> Roma keeps a short audio buffer, so dictation starts with the thought instead of the hotkey.

## Current Constraints

- Keep production as static HTML/CSS/JS.
- Keep the primary CTA as GitHub releases latest.
- Keep GitHub as the secondary action.
- Keep contact as lower priority than download.
- Use existing repo assets first:
  - `docs/assets/roma-just-talk-logo.png`
  - `docs/assets/roma-just-talk-how-to-use.png`
  - `landing/public/screenshot.jpeg`
- No production dependency on Open Design.
- No framework migration for button or hero tweaks.

## Direction A: Quiet Switch

Best if the site needs to feel credible, calm, and installable.

Tokens:

- Background: `#f7f5ef`
- Ink: `#151515`
- Muted: `#62605b`
- Accent: `#f6b21a`
- Radius: `8px`
- Button shape: square-ish, compact, high-contrast

Use:

- Hero headline: `Say first. Press later.`
- Subcopy: `Roma keeps a short buffer, so the first words arrive with the rest of the thought.`
- Primary button: `Download macOS`
- Secondary button: `GitHub`

Avoid:

- Big gradients
- Decorative marks
- Long explanations above the fold

## Direction B: Signal Color

Best if the page needs to feel memorable and founder-led without becoming messy.

Tokens:

- Background: `#fff8e7`
- Ink: `#16120f`
- Accent: `#ff6b4a`
- Support: `#46d9ff`
- Energy: `#b8ff3d`
- Radius: `8px`
- Button shape: thick border, offset shadow

Use:

- Hero headline: `No wait. Just speak.`
- Subcopy: `Start talking while your hand moves. Roma catches the beginning.`
- Primary button: `Download macOS`
- Secondary button: `See source`

Avoid:

- More than three accent colors
- Extra badges near the CTA
- Comic styling outside the hero

## Direction C: Mac Glass

Best if the page should feel like a native Mac utility with a premium, quiet install path.

Tokens:

- Background: `#101215`
- Ink: `#f4f7fb`
- Muted: `#a8b0bb`
- Accent: `#7dd3fc`
- Edge: `rgba(255,255,255,.16)`
- Radius: `8px` for layout, pill only for buttons

Use:

- Hero headline: `Thought before hotkey.`
- Subcopy: `A short rolling buffer turns dictation from a sequence into a parallel action.`
- Primary button: `Download macOS`
- Secondary button: `GitHub`

Avoid:

- Calling this Apple Liquid Glass
- Low-contrast glass buttons
- Too many translucent panels

## Recommended Pick

Start from Direction A for production. Borrow the stronger CTA treatment from Direction B if the page feels too quiet. Keep Direction C as a later premium polish pass after the product screenshot and setup flow are cleaner.

## Porting Rule

When a direction is chosen, port only:

1. Color tokens.
2. Hero layout.
3. Button system.
4. One supporting visual treatment.

Do not copy every sandbox section into production.
