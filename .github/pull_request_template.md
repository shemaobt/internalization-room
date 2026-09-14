## What changes

<!-- The argument, in prose. What used to happen, what holds now. -->

## Does this touch one of Marcia's artifacts?

`DOCTRINE.md` §5.1 — "`prompts/*.md`, the model ladder and its parameters are **Marcia's
artifacts**: any change is a ruling with her word, never an engineering default."

No prompt and no model parameter lives in this repo — they run in `tripod-backend`, and
`docs/doctrine/MODEL_SEAM` records them there. What this repo can move is the vendored doctrine
itself and the §4 acceptance bar, and `dart run tool/sync_doctrine.dart --check` fails the build
when either does.

- [ ] the pin in `docs/doctrine/DOCTRINE_PIN` (a re-sync of the vendored doctrine)
- [ ] a row of `docs/doctrine/ACCEPTANCE_BAR` — a line moving off `PENDING`, or a claim changing
- [ ] the room's behaviour on a line of §4: the circle at `done`, or the voice opening the session
- [ ] none of the above

**Her words:**

**Where it is written:**

<!-- Both, or none of the boxes above. A decision with no sentence of hers behind it is the
engineering default §5.1 names, and review stops here: the ruling goes in
docs/doctrine/rulings/ as its own file, and the row that changed points at it by slug. -->

## Verification

<!-- Test count, `flutter analyze`, and whether the fix was reverted to prove the test fails
without it. -->
