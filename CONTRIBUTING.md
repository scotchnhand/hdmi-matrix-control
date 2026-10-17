# Contributing

Thanks for looking at this. Short version:

1. Bug or idea? Open an issue using the templates (Issues → New Issue).
2. Want to fix/build it yourself? Read **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**
   for setup, how to run tests, branch/commit conventions, and the PR
   checklist.
3. Check **[docs/ROADMAP.md](docs/ROADMAP.md)** first — your idea might
   already be a planned item (or a deliberately-rejected one, with the
   reasoning written down).

Normal changes go through a PR against `dev`; releases go through a PR from
`dev` to protected `main`. CI (lint, tests, HA manifest validation, a check
that the two copies of the shared protocol client haven't diverged, and branch
routing) has to pass. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and
[docs/BRANCHING-AND-PROTECTION.md](docs/BRANCHING-AND-PROTECTION.md) for
details.
