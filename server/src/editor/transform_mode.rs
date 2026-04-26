use bevy::input::mouse::MouseMotion;
use bevy::prelude::*;
use bevy::window::PrimaryWindow;
use bevy_egui::EguiContexts;

use super::camera::OrbitCamera;
use super::selection::Selection;
use super::snap::snap_vec3;
use super::state::{EditorSettings, PrimRef, TrackDoc};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Axis {
    X,
    Y,
    Z,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Mode {
    Idle,
    Translate { axis: Option<Axis>, start_pos: [f64; 3] },
    Rotate { axis: Axis, start_rot_deg: [f64; 3], accumulated_deg: f64 },
}

#[derive(Resource)]
pub struct TransformMode {
    pub mode: Mode,
    pub no_snap: bool,
}

impl Default for TransformMode {
    fn default() -> Self {
        Self {
            mode: Mode::Idle,
            no_snap: false,
        }
    }
}

#[derive(Resource, Default)]
pub struct DocDirty {
    pub edit: bool,
    pub structural: bool,
}

impl DocDirty {
    pub fn mark_edit(&mut self) {
        self.edit = true;
    }
    pub fn mark_structural(&mut self) {
        self.structural = true;
    }
}

pub fn handle_transform_hotkeys(
    keys: Res<ButtonInput<KeyCode>>,
    mouse: Res<ButtonInput<MouseButton>>,
    mut motion: EventReader<MouseMotion>,
    selection: Res<Selection>,
    settings: Res<EditorSettings>,
    prims: Query<&PrimRef>,
    cam_q: Query<&Transform, With<OrbitCamera>>,
    windows: Query<&Window, With<PrimaryWindow>>,
    mut doc: ResMut<TrackDoc>,
    mut state: ResMut<TransformMode>,
    mut dirty: ResMut<DocDirty>,
    mut egui_contexts: EguiContexts,
) {
    let ctx = egui_contexts.ctx_mut();
    if ctx.wants_keyboard_input() {
        return;
    }
    let Some(entity) = selection.0 else {
        return;
    };
    let Ok(prim_ref) = prims.get(entity) else {
        return;
    };
    let idx = prim_ref.0;

    let mouse_delta: Vec2 = motion.read().fold(Vec2::ZERO, |acc, e| acc + e.delta);

    state.no_snap = keys.any_pressed([KeyCode::ShiftLeft, KeyCode::ShiftRight]);
    let no_snap = state.no_snap;

    match state.mode {
        Mode::Idle => {
            if keys.just_pressed(KeyCode::KeyG) {
                let Some(prim) = doc.def.primitives.get(idx) else {
                    return;
                };
                state.mode = Mode::Translate {
                    axis: None,
                    start_pos: prim.position,
                };
            } else if keys.just_pressed(KeyCode::KeyR) {
                let Some(prim) = doc.def.primitives.get(idx) else {
                    return;
                };
                state.mode = Mode::Rotate {
                    axis: Axis::Y,
                    start_rot_deg: prim.rotation_deg,
                    accumulated_deg: 0.0,
                };
            }
        }

        Mode::Translate { ref mut axis, start_pos } => {
            if keys.just_pressed(KeyCode::KeyX) {
                *axis = Some(Axis::X);
            }
            if keys.just_pressed(KeyCode::KeyY) {
                *axis = Some(Axis::Y);
            }
            if keys.just_pressed(KeyCode::KeyZ) {
                *axis = Some(Axis::Z);
            }

            if keys.just_pressed(KeyCode::Escape) || mouse.just_pressed(MouseButton::Right) {
                if let Some(prim) = doc.def.primitives.get_mut(idx) {
                    prim.position = start_pos;
                    dirty.mark_edit();
                }
                state.mode = Mode::Idle;
                return;
            }

            if keys.just_pressed(KeyCode::Enter) || mouse.just_pressed(MouseButton::Left) {
                state.mode = Mode::Idle;
                return;
            }

            let Ok(window) = windows.get_single() else { return };
            let Ok(cam_xf) = cam_q.get_single() else { return };
            let world_per_pixel = world_per_pixel_at_focus(cam_xf, window);

            let dx = mouse_delta.x as f64 * world_per_pixel as f64;
            let dy = mouse_delta.y as f64 * world_per_pixel as f64;

            let cam_right = cam_xf.right();
            let cam_up = cam_xf.up();

            let Some(prim) = doc.def.primitives.get_mut(idx) else {
                return;
            };
            let mut delta_world = Vec3::new(
                cam_right.x * dx as f32 - cam_up.x * dy as f32,
                cam_right.y * dx as f32 - cam_up.y * dy as f32,
                cam_right.z * dx as f32 - cam_up.z * dy as f32,
            );
            if let Some(a) = axis {
                let unit = match a {
                    Axis::X => Vec3::X,
                    Axis::Y => Vec3::Y,
                    Axis::Z => Vec3::Z,
                };
                delta_world = unit * delta_world.dot(unit);
            }

            prim.position[0] += delta_world.x as f64;
            prim.position[1] += delta_world.y as f64;
            prim.position[2] += delta_world.z as f64;

            if !no_snap {
                prim.position = snap_vec3(prim.position, settings.snap_translate as f64);
            }
            dirty.mark_edit();
        }

        Mode::Rotate { ref mut axis, start_rot_deg, ref mut accumulated_deg } => {
            if keys.just_pressed(KeyCode::KeyX) {
                *axis = Axis::X;
            }
            if keys.just_pressed(KeyCode::KeyY) {
                *axis = Axis::Y;
            }
            if keys.just_pressed(KeyCode::KeyZ) {
                *axis = Axis::Z;
            }

            if keys.just_pressed(KeyCode::Escape) || mouse.just_pressed(MouseButton::Right) {
                if let Some(prim) = doc.def.primitives.get_mut(idx) {
                    prim.rotation_deg = start_rot_deg;
                    dirty.mark_edit();
                }
                state.mode = Mode::Idle;
                return;
            }

            if keys.just_pressed(KeyCode::Enter) || mouse.just_pressed(MouseButton::Left) {
                state.mode = Mode::Idle;
                return;
            }

            *accumulated_deg += mouse_delta.x as f64 * 0.5;

            let mut applied = *accumulated_deg;
            if !no_snap {
                let step = settings.snap_rotate_deg as f64;
                if step > 0.0 {
                    applied = (applied / step).round() * step;
                }
            }

            let axis_idx = match *axis {
                Axis::X => 0,
                Axis::Y => 1,
                Axis::Z => 2,
            };
            let Some(prim) = doc.def.primitives.get_mut(idx) else {
                return;
            };
            prim.rotation_deg = start_rot_deg;
            prim.rotation_deg[axis_idx] += applied;
            dirty.mark_edit();
        }
    }
}

fn world_per_pixel_at_focus(_cam_xf: &Transform, window: &Window) -> f32 {
    // Approximation : scale the mouse movement based on window size and a fixed factor.
    // Good enough for translate-on-camera-plane in iter 1.
    let h = window.height().max(1.0);
    100.0 / h
}
