use bevy::prelude::*;
use std::path::PathBuf;

use crate::track::{LapConfig, Spawn, TrackDef};

#[derive(Resource)]
pub struct TrackDoc {
    pub path: Option<PathBuf>,
    pub def: TrackDef,
    pub dirty: bool,
}

impl TrackDoc {
    pub fn empty() -> Self {
        Self {
            path: None,
            def: TrackDef {
                id: "untitled".into(),
                name: "Untitled".into(),
                spawn: Spawn {
                    position: [0.0, 3.0, 0.0],
                    y_rotation_deg: 0.0,
                },
                lap: LapConfig {
                    finish_x: 0.0,
                    finish_half_width: 20.0,
                    checkpoint_x: 0.0,
                    checkpoint_half_width: 20.0,
                    positive_z_threshold: 50.0,
                    laps_to_win: 3,
                },
                primitives: vec![],
            },
            dirty: false,
        }
    }
}

#[derive(Resource)]
pub struct EditorSettings {
    pub snap_translate: f32,
    pub snap_rotate_deg: f32,
}

impl Default for EditorSettings {
    fn default() -> Self {
        Self {
            snap_translate: 1.0,
            snap_rotate_deg: 15.0,
        }
    }
}

#[derive(Component)]
pub struct PrimRef(pub usize);

#[derive(Component)]
pub struct PrimMaterialBase(pub Handle<StandardMaterial>);
