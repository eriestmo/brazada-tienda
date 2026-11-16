# Design

Identidad pinned by the Emily Natación brandbook (`~/Downloads/Brandbook Emily Natacion.pdf`). Applies to `index.html` (tienda) and `clases.html` (clases y cuentas). Product truth lives in `PRODUCT.md`.

## Logos (`assets/`)
- `logo-emily.webp`: purple wordmark, NATACIÓN in purple. Light backgrounds (header, footer).
- `logo-emily-blanco.webp`: original, NATACIÓN in white. Dark mode and cyan surfaces (via `<picture>` + `prefers-color-scheme: dark`).
- `emily-kids.webp`: Emily Kids mascot logo. Only on things for children (kids band, "Emily Kids" badge on products for Niños, kids class cards).
- Never stretch, recolor the letters, or cover part of a logo (brandbook "usos no adecuados").

## Color tokens
| Token | Light | Dark | Use |
|---|---|---|---|
| `--lila` | #6A2C95 | #9C22C0 | primary buttons, announcement bar (white text) |
| `--agua` | #00BDD6 | #00BDD6 | secondary buttons, wave lines, focus ring |
| `--rosa` | #FF4DA4 | #FF4DA4 | Emily Kids, cart count, selection |
| `--hero-bg` | #00BDD6 | #2A1352 | hero band |
| `--hero-accent` | #472796 | #00CAF2 | Playfair accent words in the hero |
| `--ink` | #040205 | #F2EDFA | text |
| `--agua-ink` / `--rosa-ink` / `--lila-ink` | #00707F / #B0105F / #6A2C95 | #5FDDEA / #FF8CC4 / #D9A8F2 | text on soft fills; darker/lighter than the brand hue on purpose so text passes 4.5:1 |

All text pairs were measured ≥4.5:1 in both themes (2026-11-16).

## Type
- Poppins 400–800 for everything; headings 700–800, letter-spacing -0.02em.
- Playfair Display italic only for short accent phrases inside headings (`h1 em`, `h2 em`), as the brandbook's "afirmación" style. Never a whole headline.

## Elements
- Wave: brand "icono/onda". Cyan wave line as section divider (`.rope`), white wave lines at the foot of the hero band.
- No eyebrow labels above headings. No decorative stripe textures.
