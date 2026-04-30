use bevy::prelude::*;
use bevy::window::PrimaryWindow;
use bevy_egui::EguiContexts;

use super::camera::OrbitCamera;
use super::state::{PrimMaterialBase, PrimRef, TrackDoc};
use super::transform_mode::{Mode, TransformMode};

#[derive(Resource, Default)]
pub struct Selection(pub Option<Entity>);

pub fn pick_on_click(
    mouse: Res<ButtonInput<MouseButton>>,
    keys: Res<ButtonInput<KeyCode>>,
    windows: Query<&Window, With<PrimaryWindow>>,
    cam_q: Query<(&Camera, &GlobalTransform), With<OrbitCamera>>,
    prims: Query<(Entity, &Transform, &PrimRef)>,
    doc: Res<TrackDoc>,
    mut selection: ResMut<Selection>,
    mut egui_contexts: EguiContexts,
    mode: Res<TransformMode>,
) {
    if !matches!(mode.mode, Mode::Idle) {
        return;
    }
    if !mouse.just_pressed(MouseButton::Left) {
        return;
    }
    if keys.any_pressed([
        KeyCode::AltLeft,
        KeyCode::AltRight,
        KeyCode::ControlLeft,
        KeyCode::ControlRight,
    ]) {
        return;
    }

    let ctx = egui_contexts.ctx_mut();
    if ctx.is_pointer_over_area() || ctx.wants_pointer_input() || ctx.is_using_pointer() {
        return;
    }

    let Ok(window) = windows.get_single() else { return };
    let Some(cursor) = window.cursor_position() else { return };
    let Ok((cam, cam_xf)) = cam_q.get_single() else { return };
    let Some(ray) = cam.viewport_to_world(cam_xf, cursor) else { return };

    let mut best: Option<(Entity, f32)> = None;
    for (entity, xf, prim_ref) in prims.iter() {
        let Some(prim) = doc.def.primitives.get(prim_ref.0) else {
            continue;
        };
        let half = Vec3::new(
            prim.size[0] as f32 * 0.5,
            prim.size[1] as f32 * 0.5,
            prim.size[2] as f32 * 0.5,
        );
        if let Some(t) = ray_obb_intersect(ray.origin, *ray.direction, xf, half) {
            if t > 0.0 && best.map_or(true, |(_, bt)| t < bt) {
                best = Some((entity, t));
            }
        }
    }

    selection.0 = best.map(|(e, _)| e);
}

fn ray_obb_intersect(origin: Vec3, dir: Vec3, xf: &Transform, half: Vec3) -> Option<f32> {
    let inv_rot = xf.rotation.inverse();
    let local_origin = inv_rot * (origin - xf.translation);
    let local_dir = inv_rot * dir;
    ray_aabb_intersect(local_origin, local_dir, -half, half)
}

fn ray_aabb_intersect(origin: Vec3, dir: Vec3, min: Vec3, max: Vec3) -> Option<f32> {
    let mut tmin = f32::NEG_INFINITY;
    let mut tmax = f32::INFINITY;
    for i in 0..3 {
        let o = origin[i];
        let d = dir[i];
        let a = min[i];
        let b = max[i];
        if d.abs() < 1e-8 {
            if o < a || o > b {
                return None;
            }
        } else {
            let t1 = (a - o) / d;
            let t2 = (b - o) / d;
            let (lo, hi) = if t1 < t2 { (t1, t2) } else { (t2, t1) };
            tmin = tmin.max(lo);
            tmax = tmax.min(hi);
            if tmin > tmax {
                return None;
            }
        }
    }
    if tmax < 0.0 {
        return None;
    }
    Some(tmin.max(0.0))
}

pub fn highlight_selection(
    selection: Res<Selection>,
    q: Query<(Entity, &PrimMaterialBase)>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    for (entity, base) in q.iter() {
        let Some(mat) = materials.get_mut(&base.0) else {
            continue;
        };
        let want = if Some(entity) == selection.0 {
            LinearRgba::rgb(0.6, 0.5, 0.0)
        } else {
            LinearRgba::BLACK
        };
        if mat.emissive != want {
            mat.emissive = want;
        }
    }
}
