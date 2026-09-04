# Shemá Design System

> *"Assim na terra como no céu."* — On earth as it is in heaven.

This is the design system for **Shemá – Multimodal Bible Translation**, a Brazilian missionary community ("jocumeiros" — JOCUM / YWAM Brasil) dedicated to translating Scripture into every mother tongue, in every modality: text, audio, video, sign-language. The brand takes its name from the Hebrew **שמע** ("shema" — *hear*) used in Deuteronomy 6, where Israel is called to *listen* and internalize God's word.

The visual language is warm, grounded, and human. It favors earthy color (terracotta, olive, sand, sage), strong sans-serif type paired with a quiet serif voice, full-bleed documentary photography of indigenous and missional communities, and a quarter-circle geometric pattern derived from the radio-wave half of the brand mark.

---

## Source materials

Everything here is derived from the official **Manual da Marca Shemá** (15 pages, Portuguese) authored by **Maryangela Alves** (`hello.maryangela@gmail.com`, [maryangelaalves.com](https://www.maryangelaalves.com)). Originals live in `uploads/` if you have access:

- `uploads/MANUAL_DA_MARCA_SHEMA_compressed-01.png` → `-17.png` — brand manual pages
- `uploads/LOGO*.svg`, `uploads/ÍCONE*.svg` — vector logos in all 5 brand colors
- `uploads/Montserrat-*.ttf`, `uploads/Merriweather-*.ttf`, `uploads/Playfair*` — full font families
- No codebase, Figma file, or live product was provided; everything is reconstructed from the brand manual.

---

## Index

| File / Folder | What it is |
|---|---|
| `colors_and_type.css` | All design tokens — colors, fonts, type scale, spacing, radii, shadows, motion |
| `assets/` | Logo SVGs (5 colorways × 4 lockups), icon mark, brand photography, pattern tile |
| `fonts/` | Montserrat + Merriweather `.ttf` files (subset of what was provided) |
| `preview/` | Static design-system card HTMLs that appear in the Design System tab |
| `ui_kits/website/` | Marketing site UI kit — components + assembled homepage |
| `SKILL.md` | Agent Skill manifest — makes this folder usable from Claude Code |

---

## Content Fundamentals

**Language.** Portuguese (Brazilian) is primary. The brand often pulls Hebrew (שמע, *Shemá*) and Biblical references. English is used for the descriptor "Multimodal Bible Translation" in the secondary lockup.

**Voice.** Warm, invitational, communal. Speaks *with* people, not *at* them. Not corporate, not preachy, not sentimental. The brand attributes set the tone explicitly:

> SIMPLES · ACESSÍVEL · VIVA · AMIGÁVEL · INCLUSIVA · AFIRMATIVA · HUMANA · HOLÍSTICA · LEVE
>
> *Simple · Accessible · Alive · Friendly · Inclusive · Affirming · Human · Holistic · Light*

**Specific examples from the manual:**
- Headline: **"Vem ouvir."** (*Come listen.*) — two words, second-person, an invitation
- Headline: **"Assim na terra como no céu."** — the tagline; biblical, lowercased except first letter
- Body intro: *"Shemá – Multimodal Bible Translation é também uma comunidade solidária e prestativa de jocumeiros dedicados a trabalhar em conjunto para ver a palavra de Deus celebrada em todas as línguas maternas…"*
- Card title style: **"POR QUE SHEMÁ"** — all-caps, no question mark, declarative
- Sub-tagline beneath cards: *"Assim na terra como no céu."* — set in italic serif, sentence case

**Casing.**
- All-caps Montserrat for short power words (`SHEMÁ`, attribute lists, eyebrows, section labels).
- Sentence case for headlines and body — never title case.
- The wordmark itself is lowercase (`shema`).

**Pronouns.** Tends toward "nós/nossa" (we/our) when speaking about the community; second-person ("vem", "ouça") when inviting.

**No emoji.** Never. The brand vocabulary is Hebrew letters (שמע), the icon mark, and photography — those carry the warmth.

**Punctuation.** Comfortable with period-ended fragments ("Vem ouvir.") and italic-quoted phrases inside Merriweather body copy. Hyphens never; em-dashes sparingly.

---

## Visual Foundations

**Color is the brand.** Six earthy colors plus a near-black, no gradients, no tints invented on the fly. The palette comes from soil, sky, and natural pigment — terra/clay (telha), olive bush (verde claro, verde), sand-dried grass (areia), Atlantic-coast sky (azul), warm midnight (preto). Backgrounds are usually `branco` (cream `#F6F5EB`) or one of the deep colors used full-bleed; `telha` is the call-to-action / accent and is used sparingly and confidently.

**Typography.** Two families.
- **Montserrat** (`tipografia principal`) — geometric sans, used for everything load-bearing: headlines, buttons, navigation, eyebrows, attribute lists. Heaviest weights (Black, Bold) for display; SemiBold/Bold for headings; Regular for body. Often used in ALL CAPS for impact words like `SHEMÁ` at billboard scale.
- **Merriweather** (`tipografia de apoio`) — humanist serif, used as the *quiet voice*: scripture quotes, italic taglines, soft callouts beneath cards, longer-form reading. Always feels like a whispered phrase next to Montserrat's bold statement.

**Backgrounds.** Three modes:
1. **Solid color full-bleed** — `verde claro`, `telha`, `azul`, or `preto` filling an entire panel/slide. The manual's pages are themselves examples.
2. **Cream paper** (`branco`) — quiet default, used when content needs to breathe.
3. **Geometric pattern** — the quarter-circle motif (`assets/pattern-tile.svg`) tiled across full panels or used as a decorative side-rail. Never small/repeated under text. Tile uses 3–4 brand colors only.

**Imagery.** Documentary photography of indigenous Brazilian peoples, missionaries, community gatherings, hands, faces in conversation. Warm color grade — pulled toward `telha`/sepia. Often **masked into the icon shape** (an open-book silhouette with the wave cutout in the bottom-right), so a photo becomes "a book of someone's story." See `assets/photography-1.png`–`photography-3.png`.

**Pattern.** Quarter-circle / arc shapes in three or four brand colors, tessellated on a square grid (each cell is 4 quarters = one full circle motif). The arcs riff on the *sound-wave* half of the logo. Use on hero panels, social cards, packaging, decorative half-page splits.

**Layout & rhythm.**
- Generous whitespace — type often left-aligned at ~30% from the left edge, copy block sitting at ~40–50% width.
- Strong contrast between solid color panels and cream pages.
- Many compositions are 50/50 splits: pattern | photo, color | type, photo | quote.
- Centered compositions are reserved for the wordmark itself (manual cover) and signature moments ("OBRIGADA!").

**Corner radii.** Generous and friendly — the wordmark's curves set the precedent. Cards use `--radius-lg` (22px); pill buttons (`--radius-pill`). Hard 90° corners are reserved for full-bleed color blocks and the icon's "open book" silhouette.

**Cards.** Solid color background OR cream with subtle warm shadow (`--shadow-card`). Padding `--space-6` (32px) minimum. Image-led cards use the icon-mask silhouette. No colored left-border accents. No drop-shadow + rounded-corner web tropes.

**Borders.** Almost never. Where used (form inputs, dividers), they are `verde` at 16% opacity — a soft warm line.

**Shadows.** Low, warm-tinted (`rgba(10,7,3,…)`), never blue/cool. Used as a whisper of elevation only — the brand is print-rooted, so shadows are restrained. `--shadow-card` for content blocks; `--shadow-lg` for floating overlays.

**Animation.** Gentle. Linear/ease-out 220ms for state changes. Fades and small translations preferred over scale/rotate. No bounces, no springy easings, no parallax effects. The brand is *quiet and grounded*; motion should never feel kinetic or playful.

**Hover.** Buttons darken (telha → `#A23E00`), text links underline + darken, cards lift via shadow + 1–2px translateY. Never lighten on hover.

**Press.** Brief shrink (`scale(.985)`) + darker color (`--accent-press`). 90ms in, 220ms ease-out back.

**Transparency / blur.** Rare. The pattern is solid, photography is solid. The only place opacity is regularly used is for the warm `verde @ 16%` border lines and `branco @ 18%` lines-on-dark.

**Imagery color vibe.** Warm. Earth-toned. Often sepia-graded. People-first. No stock photography, no gradients overlays. When a photo is silhouetted into the book shape, the surrounding color is one of the solid palette colors (most often telha).

---

## Iconography

**The brand mark itself is the primary icon.** The open-book-plus-sound-waves symbol (file: `assets/icon-*.svg`, five colorways) is used at hero scale, watermarked into the corner of full-bleed photography, and as the silhouette into which photos are clipped.

**There is no app, no icon font, no proprietary icon set** in the source materials provided. For UI work, we recommend pairing with **Lucide** ([unpkg.com/lucide-static](https://unpkg.com/lucide-static)) — a friendly, generous-weight open-source set whose stroke weight (1.5–2px) and rounded line-caps sit well alongside Shemá's geometry. *(This is a substitution flagged for client review — there is no canonical icon set in the brand manual.)*

When using Lucide:
- Stroke width 1.75px, line caps round, line joins round.
- Color: `var(--fg)` for default, `var(--accent)` for active/CTA.
- Size: 20px in dense UI, 24px in standard, 32px+ in marketing.

**No emoji.** No flag icons, no smileys. The brand is multicultural and missional — emoji feel reductive.

**No unicode glyphs as icons.** Don't use `→` `✓` `★` as substitutes for SVG icons in production.

**Hebrew lettering.** The script שמע (Shemá) is a legitimate brand element — use it in display contexts as decoration, set in any system Hebrew font.

---

## Substitutions flagged for review

1. **Icon set.** No icon set was provided. Lucide is suggested as the closest match in weight and tone. **Please confirm or send your preferred set.**
2. **Icon-mark extraction.** The standalone `assets/icon-*.svg` files were programmatically extracted from the vertical-logo SVGs (the original `ÍCONE - *.svg` files have a precomposed Í + combining acute in the filename that our filesystem rejects). The vector data is identical — only the wrapping viewBox is ours.
3. **No live product / Figma / codebase** was provided, so the UI kit in `ui_kits/website/` is a marketing-site recreation built directly from the brand manual's visual language, not from an existing product. **Please send screenshots, Figma, or a repo URL** if you have an in-progress product and want pixel-perfect components instead.

---

## Quick start

```html
<link rel="stylesheet" href="colors_and_type.css">
<body class="surface">
  <header class="container">
    <img src="assets/logo-tagline-verde.svg" alt="Shemá — Multimodal Bible Translation" height="44">
  </header>
  <main class="container">
    <p class="eyebrow">Por que Shemá</p>
    <h1>Assim na terra como no céu.</h1>
    <p class="lead serif">Uma comunidade solidária e prestativa de jocumeiros…</p>
  </main>
</body>
```
