pub mod camera;
pub mod gizmo_axes;
pub mod io;
pub mod panel;
pub mod segments;
pub mod selection;
pub mod snap;
pub mod spawn;
pub mod state;
pub mod transform_mode;

use bevy::prelude::*;
use bevy_egui::EguiPlugin;
use std::path::PathBuf;

use panel::{LoadRequested, PanelState, SaveRequested};
use selection::Selection;
use state::{EditorSettings, PrimRef, TrackDoc};
use transform_mode::{DocDirty, TransformMode};

pub struct EditorPlugin {
    pub startup_track: Option<String>,
}

#[derive(Resource)]
struct StartupArg(Option<PathBuf>);

impl Plugin for EditorPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(EguiPlugin)
            .insert_resource(ClearColor(Color::srgb(0.07, 0.08, 0.10)))
            .insert_resource(StartupArg(self.startup_track.as_ref().map(PathBuf::from)))
            .insert_resource(Selection::default())
            .insert_resource(EditorSettings::default())
            .insert_resource(TransformMode::default())
            .insert_resource(DocDirty::default())
            .insert_resource(PanelState::default())
            .insert_resource(AmbientLight {
                color: Color::WHITE,
                brightness: 250.0,
            })
            .add_event::<SaveRequested>()
            .add_event::<LoadRequested>()
            .add_systems(Startup, setup_scene)
            .add_systems(
                Update,
                (
                    panel::draw_panels,
                    selection::pick_on_click
                        .after(panel::draw_panels)
                        .before(transform_mode::handle_transform_hotkeys),
                    transform_mode::handle_transform_hotkeys.after(panel::draw_panels),
                    handle_delete_hotkey.after(panel::draw_panels),
                    handle_save_shortcut.after(panel::draw_panels),
                    process_save_events,
                    process_load_events,
                    sync_edits,
                    respawn_structural.after(sync_edits),
                    selection::highlight_selection
                        .after(sync_edits)
                        .after(respawn_structural),
                    camera::update_orbit_camera.after(panel::draw_panels),
                    camera::focus_on_selection_hotkey.after(panel::draw_panels),
                    gizmo_axes::draw_grid,
                    gizmo_axes::draw_world_axes,
                    gizmo_axes::draw_selection_axes,
                ),
            );
    }
}

fn setup_scene(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    arg: Res<StartupArg>,
) {
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            illuminance: 9_000.0,
            shadows_enabled: false,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(
            EulerRot::XYZ,
            -0.9,
            -0.5,
            0.0,
        )),
        ..default()
    });

    camera::spawn_orbit_camera(&mut commands);

    let doc = match arg.0.as_ref() {
        Some(p) => match io::load_path(p) {
            Ok(d) => {
                info!(
                    "Loaded track: {} ({} primitives)",
                    p.display(),
                    d.def.primitives.len()
                );
                d
            }
            Err(e) => {
                error!("Failed to load track {}: {e}", p.display());
                TrackDoc::empty()
            }
        },
        None => TrackDoc::empty(),
    };

    spawn::spawn_all(&mut commands, &mut meshes, &mut materials, &doc);
    commands.insert_resource(doc);
}

fn sync_edits(
    mut dirty: ResMut<DocDirty>,
    doc: Res<TrackDoc>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut q: Query<(
        &PrimRef,
        &mut Transform,
        &mut Handle<Mesh>,
        &state::PrimMaterialBase,
    )>,
) {
    if dirty.structural || !dirty.edit {
        return;
    }
    dirty.edit = false;

    for (prim_ref, mut transform, mut mesh_h, mat_base) in q.iter_mut() {
        let Some(prim) = doc.def.primitives.get(prim_ref.0) else {
            continue;
        };
        let size = Vec3::new(
            prim.size[0] as f32,
            prim.size[1] as f32,
            prim.size[2] as f32,
        );
        transform.translation = Vec3::new(
            prim.position[0] as f32,
            prim.position[1] as f32,
            prim.position[2] as f32,
        );
        transform.rotation = Quat::from_euler(
            EulerRot::XYZ,
            (prim.rotation_deg[0] as f32).to_radians(),
            (prim.rotation_deg[1] as f32).to_radians(),
            (prim.rotation_deg[2] as f32).to_radians(),
        );
        *mesh_h = meshes.add(Cuboid::new(size.x, size.y, size.z));
        if let Some(mat) = materials.get_mut(&mat_base.0) {
            mat.base_color = spawn::pick_color(prim);
        }
    }
}

fn respawn_structural(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut dirty: ResMut<DocDirty>,
    doc: Res<TrackDoc>,
    existing: Query<(Entity, &PrimRef)>,
    mut selection: ResMut<Selection>,
) {
    if !dirty.structural {
        return;
    }
    dirty.structural = false;
    dirty.edit = false;

    let selected_idx: Option<usize> = selection
        .0
        .and_then(|e| existing.get(e).ok().map(|(_, pr)| pr.0));

    for (e, _) in existing.iter() {
        commands.entity(e).despawn_recursive();
    }

    let mut new_selected: Option<Entity> = None;
    for (idx, prim) in doc.def.primitives.iter().enumerate() {
        let entity = spawn::spawn_one(&mut commands, &mut meshes, &mut materials, idx, prim);
        if Some(idx) == selected_idx {
            new_selected = Some(entity);
        }
    }
    selection.0 = new_selected;
}

fn handle_delete_hotkey(
    keys: Res<ButtonInput<KeyCode>>,
    mut selection: ResMut<Selection>,
    prims: Query<&PrimRef>,
    mode: Res<TransformMode>,
    mut doc: ResMut<TrackDoc>,
    mut dirty: ResMut<DocDirty>,
    mut egui_contexts: bevy_egui::EguiContexts,
) {
    if egui_contexts.ctx_mut().wants_keyboard_input() {
        return;
    }
    if !matches!(mode.mode, transform_mode::Mode::Idle) {
        return;
    }
    if !keys.just_pressed(KeyCode::Delete) {
        return;
    }
    let Some(entity) = selection.0 else { return };
    let Ok(prim_ref) = prims.get(entity) else { return };
    let idx = prim_ref.0;
    if idx < doc.def.primitives.len() {
        doc.def.primitives.remove(idx);
        doc.dirty = true;
        dirty.mark_structural();
        selection.0 = None;
    }
}

fn handle_save_shortcut(
    keys: Res<ButtonInput<KeyCode>>,
    mut save_evt: EventWriter<SaveRequested>,
    mut egui_contexts: bevy_egui::EguiContexts,
) {
    if egui_contexts.ctx_mut().wants_keyboard_input() {
        return;
    }
    let ctrl = keys.any_pressed([KeyCode::ControlLeft, KeyCode::ControlRight]);
    let shift = keys.any_pressed([KeyCode::ShiftLeft, KeyCode::ShiftRight]);
    if ctrl && keys.just_pressed(KeyCode::KeyS) {
        save_evt.send(SaveRequested { save_as: shift });
    }
}

fn process_save_events(
    mut events: EventReader<SaveRequested>,
    mut doc: ResMut<TrackDoc>,
    mut panel: ResMut<PanelState>,
) {
    for ev in events.read() {
        let target_path = if ev.save_as || doc.path.is_none() {
            rfd::FileDialog::new()
                .add_filter("track json", &["json"])
                .set_file_name(
                    doc.path
                        .as_ref()
                        .and_then(|p| p.file_name())
                        .map(|s| s.to_string_lossy().to_string())
                        .unwrap_or_else(|| format!("{}.json", doc.def.id)),
                )
                .save_file()
        } else {
            doc.path.clone()
        };

        let Some(path) = target_path else {
            panel.status = "Save cancelled".into();
            continue;
        };

        match io::save_to_path(&doc, &path) {
            Ok(()) => {
                doc.path = Some(path.clone());
                doc.dirty = false;
                panel.status = format!("Saved {}", path.display());
                info!("Saved track to {}", path.display());
            }
            Err(e) => {
                panel.status = format!("Save error: {e}");
                error!("{e}");
            }
        }
    }
}

fn process_load_events(
    mut events: EventReader<LoadRequested>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    existing: Query<Entity, With<PrimRef>>,
    mut doc: ResMut<TrackDoc>,
    mut panel: ResMut<PanelState>,
    mut selection: ResMut<Selection>,
) {
    for _ in events.read() {
        let Some(path) = rfd::FileDialog::new()
            .add_filter("track json", &["json"])
            .pick_file()
        else {
            panel.status = "Load cancelled".into();
            continue;
        };

        match io::load_path(&path) {
            Ok(new_doc) => {
                for e in existing.iter() {
                    commands.entity(e).despawn_recursive();
                }
                selection.0 = None;
                spawn::spawn_all(&mut commands, &mut meshes, &mut materials, &new_doc);
                panel.status = format!("Loaded {}", path.display());
                *doc = new_doc;
            }
            Err(e) => {
                panel.status = format!("Load error: {e}");
                error!("{e}");
            }
        }
    }
}
