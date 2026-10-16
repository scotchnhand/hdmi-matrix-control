# Contributing

Thanks for looking at this. Short version:

1. Bug or idea? Open an issue using the templates (Issues → New Issue).
2. Want to fix/build it yourself? Read **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**
   for setup, how to run tests, branch/commit conventions, and the PR
   checklist.
3. Check **[docs/ROADMAP.md](docs/ROADMAP.md)** first — your idea might
   already be a planned item (or a deliberately-rejected one, with the
   reasoning written down).

All changes go through a PR against `main`; CI (lint, tests, HA manifest
validation, a check that the two copies of the shared protocol client
haven't diverged) has to pass. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
for details.
