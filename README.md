# Star-Racer
Online arcade racing game

[![Client](https://github.com/PrimoBoomer/Star-Racer/actions/workflows/client.yml/badge.svg)](https://github.com/PrimoBoomer/Star-Racer/actions/workflows/client.yml)

[![Server](https://github.com/PrimoBoomer/Star-Racer/actions/workflows/server.yml/badge.svg)](https://github.com/PrimoBoomer/Star-Racer/actions/workflows/server.yml)

Powered by Godot, Rust, Tokio, Rapier

## Setup

Godot addons (debug_draw_3d, godot-rapier3d) are not committed. Fetch them once before opening the project:

- macOS / Linux / Git Bash: `bash scripts/fetch-addons.sh`
- Windows PowerShell: `pwsh scripts/fetch-addons.ps1`

Versions are pinned in [scripts/addons.lock](scripts/addons.lock).

Created by Claude AI
