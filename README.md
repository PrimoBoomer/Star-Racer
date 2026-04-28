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

## Credits

All third-party assets are CC0 (public domain).

| Asset | Source | License |
|---|---|---|
| Car models (`kenney_race_car.glb`, `race_car_red.glb`, `race-future.glb`) | [Kenney Racing Kit](https://kenney.nl/assets/racing-kit) — kenney.nl | CC0 |
| Wall concrete texture (`concrete_color.png`, `concrete_normal.png`) | [Concrete012 — ambientCG](https://ambientcg.com/view?id=Concrete012) — ambientcg.com | CC0 |
