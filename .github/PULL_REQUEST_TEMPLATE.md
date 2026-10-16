## What does this change?

<!-- One or two sentences. Link any related issue: "Closes #123". -->

## Why?

<!-- The motivation -- what was broken, missing, or annoying before this. -->

## Which part(s) does this touch?

- [ ] Web app (`hdmi-matrix-ui/`)
- [ ] Home Assistant integration (`ha-hdmi-matrix/`)
- [ ] Shared protocol (`matrix_client.py` — **check both copies are updated identically**, CI will fail otherwise)
- [ ] Docs (`docs/`, READMEs)
- [ ] CI/CD (`.github/`)

## How was this tested?

<!-- e.g. "Added/updated unit tests, `pytest` passes locally" and/or
     "Tested against the real matrix at <host>: routed all 4 inputs to both
     outputs, toggled power, renamed a port." Mock-only testing is fine and
     worth saying so explicitly. -->

## Checklist

- [ ] `ruff check .` passes
- [ ] `pytest` passes in any subproject you touched
- [ ] Updated `docs/ROADMAP.md` if this closes or adds a planned item
- [ ] Updated the relevant README if user-facing behavior changed
