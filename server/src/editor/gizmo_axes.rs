use bevy::color::palettes::css;
use bevy::prelude::*;

use super::selection::Selection;

pub fn draw_world_axes(mut gizmos: Gizmos) {
    let len = 5.0;
    gizmos.line(Vec3::ZERO, Vec3::X * len, css::RED);
    gizmos.line(Vec3::ZERO, Vec3::Y * len, css::LIME);
    gizmos.line(Vec3::ZERO, Vec3::Z * len, css::DODGER_BLUE);
}

pub fn draw_grid(mut gizmos: Gizmos) {
    let extent = 200.0_f32;
    let step = 5.0_f32;
    let major = 25.0_f32;
    let n = (extent / step) as i32;
    let minor_color = Color::srgba(0.4, 0.4, 0.45, 0.18);
    let major_color = Color::srgba(0.6, 0.6, 0.65, 0.45);

    for i in -n..=n {
        let p = i as f32 * step;
        let color = if (p.rem_euclid(major)).abs() < 0.001 {
            major_color
        } else {
            minor_color
        };
        gizmos.line(Vec3::new(p, 0.0, -extent), Vec3::new(p, 0.0, extent), color);
        gizmos.line(Vec3::new(-extent, 0.0, p), Vec3::new(extent, 0.0, p), color);
    }
}

pub fn draw_selection_axes(
    mut gizmos: Gizmos,
    selection: Res<Selection>,
    transforms: Query<&Transform>,
) {
    let Some(entity) = selection.0 else { return };
    let Ok(t) = transforms.get(entity) else { return };
    let len = 4.0;
    let origin = t.translation;
    gizmos.line(origin, origin + t.right() * len, css::RED);
    gizmos.line(origin, origin + t.up() * len, css::LIME);
    gizmos.line(origin, origin + t.back() * len, css::DODGER_BLUE);
}
