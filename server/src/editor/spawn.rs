use bevy::prelude::*;

use crate::track::{Primitive, PrimitiveKind};

use super::state::{PrimMaterialBase, PrimRef, TrackDoc};

pub fn spawn_all(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    doc: &TrackDoc,
) {
    for (idx, prim) in doc.def.primitives.iter().enumerate() {
        spawn_one(commands, meshes, materials, idx, prim);
    }
}

pub fn spawn_one(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    idx: usize,
    prim: &Primitive,
) -> Entity {
    let size = Vec3::new(prim.size[0] as f32, prim.size[1] as f32, prim.size[2] as f32);
    let mesh = meshes.add(Cuboid::new(size.x, size.y, size.z));
    let color = pick_color(prim);
    let mat_handle = materials.add(StandardMaterial {
        base_color: color,
        perceptual_roughness: 0.85,
        metallic: 0.05,
        ..default()
    });

    let pos = Vec3::new(
        prim.position[0] as f32,
        prim.position[1] as f32,
        prim.position[2] as f32,
    );
    let rot_rad = Vec3::new(
        (prim.rotation_deg[0] as f32).to_radians(),
        (prim.rotation_deg[1] as f32).to_radians(),
        (prim.rotation_deg[2] as f32).to_radians(),
    );
    let quat = Quat::from_euler(EulerRot::XYZ, rot_rad.x, rot_rad.y, rot_rad.z);

    commands
        .spawn((
            PbrBundle {
                mesh,
                material: mat_handle.clone(),
                transform: Transform {
                    translation: pos,
                    rotation: quat,
                    scale: Vec3::ONE,
                },
                ..default()
            },
            PrimRef(idx),
            PrimMaterialBase(mat_handle),
        ))
        .id()
}

pub fn despawn_all(commands: &mut Commands, q: &Query<Entity, With<PrimRef>>) {
    for e in q.iter() {
        commands.entity(e).despawn_recursive();
    }
}

pub fn pick_color_pub(prim: &Primitive) -> Color {
    pick_color(prim)
}

fn pick_color(prim: &Primitive) -> Color {
    if let Some(c) = prim.color {
        return Color::srgb(c[0] as f32, c[1] as f32, c[2] as f32);
    }
    match prim.kind {
        PrimitiveKind::Floor => Color::srgb(0.30, 0.30, 0.32),
        PrimitiveKind::Wall => Color::srgb(0.55, 0.55, 0.60),
        PrimitiveKind::Pad => Color::srgb(0.10, 0.30, 0.95),
        PrimitiveKind::Hazard => Color::srgb(0.85, 0.15, 0.15),
    }
}
