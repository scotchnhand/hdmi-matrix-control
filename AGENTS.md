# Repository Guidelines

## Project Structure

This repository contains three clients for the HDMI matrix:

- `hdmi-matrix-ui/backend/` contains the standard-library Python server and its tests; `frontend/` contains the installable web app and assets.
- `ha-hdmi-matrix/custom_components/hdmi_matrix/` contains the Home Assistant integration; its tests are in `ha-hdmi-matrix/tests/`.
- `ios-app/` contains the SwiftUI app, the `MatrixKit` Swift package, and UI tests.
- `docs/` holds the wire-protocol reference, development notes, roadmap, and iOS guide. Read `docs/PROTOCOL.md` before changing device commands.

## Build, Test, and Development

Install development dependencies in the subproject you are changing: `pip install -r requirements-dev.txt` from either Python subproject. The HA test environment requires Python 3.13+; use a separate virtual environment from the web backend.

Run Python tests from the relevant subproject directory with `pytest tests/ -v`; add `--cov=. --cov-report=term-missing` for coverage. Run repository-wide lint from the root with `ruff check .` (or `ruff check --fix .` to apply safe fixes). For iOS, run `cd ios-app/MatrixKit && swift test`; UI tests require Xcode 26+ and an iOS simulator, for example `xcodebuild test -project ios-app/HDMIMatrix.xcodeproj -scheme HDMIMatrix -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` from the repository root.

## Code Style and Changes

Python formatting and lint rules are configured in root `pyproject.toml`: Ruff, 110-character configured line length, import sorting, and Python 3.11 syntax. Follow existing Swift and JavaScript conventions in their respective modules. Name Python tests `test_*.py` and test functions `test_*`.

The web app and Home Assistant integration have separate copies of `matrix_client.py`. Keep both protocol clients in sync when changing shared behavior; CI checks their consistency. Add or update focused tests for behavior changes. Tests use mocks and fakes; they do not require real matrix hardware.

## Commits and Pull Requests

Use Conventional Commits, such as `fix(web-app): handle failed routing request` or `docs(protocol): clarify polling response`. Branch from `main` with a descriptive prefix such as `fix/` or `feat/`. Open changes as a PR against `main`, explain the behavior and rationale, and list the checks you ran. Include screenshots for visible iOS or web UI changes; update `docs/ROADMAP.md` when changing planned work. CI must pass before merge.

## Configuration and Hardware

Keep local credentials in untracked configuration files; start from `hdmi-matrix-ui/backend/config.example.json`. Avoid rapid or concurrent real-device requests: the matrix has a fragile embedded HTTP server. Prefer mocks and the demo client during development.
