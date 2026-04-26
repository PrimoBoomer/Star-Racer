use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;
use bevy::window::PrimaryWindow;
use bevy_egui::EguiContexts;

#[derive(Component)]
pub struct OrbitCamera {
    pub focus: Vec3,
    pub yaw: f32,
    pub pitch: f32,
    pub distance: f32,
}

impl Default for OrbitCamera {
    fn default() -> Self {
        Self {
            focus: Vec3::ZERO,
            yaw: 0.6,
            pitch: -0.5,
            distance: 200.0,
        }
    }
}

pub fn spawn_orbit_camera(commands: &mut Commands) {
    let cam = OrbitCamera::default();
    let transform = compute_transform(&cam);
    commands.spawn((
        Camera3dBundle {
            transform,
            ..default()
        },
        cam,
    ));
}

pub fn update_orbit_camera(
    mut motion: EventReader<MouseMotion>,
    mut wheel: EventReader<MouseWheel>,
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window, With<PrimaryWindow>>,
    mut q: Query<(&mut Transform, &mut OrbitCamera)>,
    mut egui_contexts: EguiContexts,
) {
    let Ok(window) = windows.get_single() else { return };
    let cursor_in_window = window.cursor_position().is_some();

    let ctx = egui_contexts.ctx_mut();
    let over_panel = ctx.is_pointer_over_area() || ctx.is_using_pointer();

    let Ok((mut transform, mut cam)) = q.get_single_mut() else { return };

    let mut delta = Vec2::ZERO;
    for ev in motion.read() {
        delta += ev.delta;
    }

    let mut wheel_delta = 0.0_f32;
    for ev in wheel.read() {
        wheel_delta += ev.y;
    }

    if cursor_in_window && !over_panel {
        if mouse.pressed(MouseButton::Right) {
            cam.yaw -= delta.x * 0.005;
            cam.pitch = (cam.pitch - delta.y * 0.005).clamp(-1.5, 1.5);
        }

        if mouse.pressed(MouseButton::Middle) {
            let right = transform.right();
            let up = transform.up();
            let pan_speed = cam.distance * 0.0015;
            cam.focus -= right * delta.x * pan_speed;
            cam.focus += up * delta.y * pan_speed;
        }

        if wheel_delta.abs() > 0.0 {
            let factor = (1.0 - wheel_delta * 0.1).clamp(0.5, 1.5);
            cam.distance = (cam.distance * factor).clamp(5.0, 1500.0);
        }
    }

    *transform = compute_transform(&cam);
}

fn compute_transform(cam: &OrbitCamera) -> Transform {
    let rot = Quat::from_axis_angle(Vec3::Y, cam.yaw) * Quat::from_axis_angle(Vec3::X, cam.pitch);
    let offset = rot * Vec3::new(0.0, 0.0, cam.distance);
    Transform::from_translation(cam.focus + offset).looking_at(cam.focus, Vec3::Y)
}

pub fn focus_on_selection_hotkey(
    keys: Res<ButtonInput<KeyCode>>,
    selection: Res<crate::editor::selection::Selection>,
    transforms: Query<&Transform, Without<OrbitCamera>>,
    mut cams: Query<&mut OrbitCamera>,
) {
    if !keys.just_pressed(KeyCode::KeyF) {
        return;
    }
    let Some(entity) = selection.0 else { return };
    let Ok(target) = transforms.get(entity) else { return };
    let Ok(mut cam) = cams.get_single_mut() else { return };
    cam.focus = target.translation;
}
