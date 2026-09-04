# Specification and prototype, vendored

The two artefacts the app's rules are measured against, vendored into this repo on 2026-09-03
so the code and its source can be read side by side.

- `interaction-flows.html` — *Tripod Internalization · Interaction Flows*, the client-validated
  interaction flows, byte-for-byte from a saved Claude artifact page.
  Origin: <https://claude.ai/code/artifact/1fc144ec-2a7c-4614-85e4-d745838fd4d6>.
- `interaction-flows.md` — a text extraction of the file above (every heading and every
  paragraph/list item, in document order, unreworded), for grep-ability. The HTML is canonical;
  this file is derived and does not carry the diagrams, the §10 role table, or the verbatim
  prompt bodies.
- `prototype/Sala de Internalização.dc.html` — the Claude Design prototype: template, the
  spoken script per state, design notes, and the Meaning Map of Ruth 1. Byte-for-byte from the
  source. **Does not render outside Claude Design** — it needs React and the Claude Design
  runtime (`support.js`, `_ds_bundle.js`) from the host page, neither of which is vendored here,
  and it needs fonts not vendored here either.
  Origin: <https://claude.ai/design/p/d84c8097-c273-4832-a568-4daea5fbb31d?file=Sala+de+Internaliza%C3%A7%C3%A3o.dc.html>.
- `prototype/_ds/shema-design-system-019e212c-f4fe-79fa-a411-538fe69dfa47/` — the design tokens
  (`colors_and_type.css`) and the two icons (`assets/icon-branco.svg`, `assets/icon-telha.svg`)
  the prototype references, plus the design system's own `README.md` (doctrine). Kept at the
  relative path the prototype's `<link>`/`<script>`/`<img>` tags use, so a reader can see which
  files it expects. That doctrine `README.md` also names `fonts/`, `preview/`, `ui_kits/website/`,
  a few more assets, and a `SKILL.md` — none of those are part of this design system export and
  none are vendored here; only the three files above are.
- `github.md` — provenance: which `sound-necklace` files the prototype was built from.

## Not vendored

- The prototype's runtime (`support.js`, `_ds_bundle.js`) and its fonts — see above.
- The *máquina de estados* artifact, which could not be fetched. Linked only:
  <https://claude.ai/code/artifact/e57dcc45-1b38-4d70-bbd6-91d831d7df12>.
