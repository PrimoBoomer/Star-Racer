use bevy::prelude::*;
use star_racer_server::editor::EditorPlugin;

fn main() {
    let arg_path = std::env::args().nth(1);

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Star Racer — Track Editor".into(),
                resolution: (1600.0, 1000.0).into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(EditorPlugin {
            startup_track: arg_path,
        })
        .run();
}
