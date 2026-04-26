use crate::track::{Primitive, PrimitiveKind};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SegmentKind {
    Straight,
    Curve,
}

#[derive(Clone, Debug)]
pub struct StraightParams {
    pub length: f64,
    pub width: f64,
    pub wall_height: f64,
    pub wall_thickness: f64,
}

impl Default for StraightParams {
    fn default() -> Self {
        Self {
            length: 60.0,
            width: 30.0,
            wall_height: 5.0,
            wall_thickness: 4.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CurveParams {
    pub inner_radius: f64,
    pub width: f64,
    pub angle_deg: f64,
    pub wall_height: f64,
    pub wall_thickness: f64,
    pub segments: u32,
}

impl Default for CurveParams {
    fn default() -> Self {
        Self {
            inner_radius: 30.0,
            width: 30.0,
            angle_deg: 90.0,
            wall_height: 5.0,
            wall_thickness: 4.0,
            segments: 8,
        }
    }
}

/// Bake a Straight segment into primitives at world origin (caller positions them via translation).
pub fn bake_straight(p: &StraightParams, origin: [f64; 3]) -> Vec<Primitive> {
    let half_w = p.width * 0.5;

    let floor = Primitive {
        kind: PrimitiveKind::Floor,
        name: Some("seg_straight_floor".into()),
        size: [p.width, 0.5, p.length],
        position: [origin[0], origin[1] - 0.25, origin[2]],
        rotation_deg: [0.0, 0.0, 0.0],
        color: None,
        heading: None,
        boost_strength: 20.0,
    };

    let wall_left = Primitive {
        kind: PrimitiveKind::Wall,
        name: Some("seg_straight_wall_l".into()),
        size: [p.wall_thickness, p.wall_height, p.length],
        position: [
            origin[0] - half_w - p.wall_thickness * 0.5,
            origin[1] + p.wall_height * 0.5,
            origin[2],
        ],
        rotation_deg: [0.0, 0.0, 0.0],
        color: None,
        heading: None,
        boost_strength: 20.0,
    };

    let wall_right = Primitive {
        kind: PrimitiveKind::Wall,
        name: Some("seg_straight_wall_r".into()),
        size: [p.wall_thickness, p.wall_height, p.length],
        position: [
            origin[0] + half_w + p.wall_thickness * 0.5,
            origin[1] + p.wall_height * 0.5,
            origin[2],
        ],
        rotation_deg: [0.0, 0.0, 0.0],
        color: None,
        heading: None,
        boost_strength: 20.0,
    };

    vec![floor, wall_left, wall_right]
}

/// Bake a Curve segment into primitives at world origin.
/// The curve starts pointing -Z and curves to the right (positive angle = right turn).
pub fn bake_curve(p: &CurveParams, origin: [f64; 3]) -> Vec<Primitive> {
    let mut out = Vec::with_capacity((p.segments as usize) * 3);
    let outer_radius = p.inner_radius + p.width;
    let mid_radius = p.inner_radius + p.width * 0.5;
    let segs = p.segments.max(1) as f64;
    let total = p.angle_deg.to_radians();
    let step = total / segs;
    let chord_inner = 2.0 * p.inner_radius * (step * 0.5).sin();
    let chord_outer = 2.0 * outer_radius * (step * 0.5).sin();
    let chord_floor = 2.0 * mid_radius * (step * 0.5).sin();

    for i in 0..p.segments {
        let mid_angle = step * (i as f64 + 0.5) - std::f64::consts::FRAC_PI_2;
        let mid_x = origin[0] + p.inner_radius + p.width * 0.5;
        let cos_a = mid_angle.cos();
        let sin_a = mid_angle.sin();

        let floor_x = mid_x - mid_radius * cos_a;
        let floor_z = origin[2] + mid_radius * sin_a;
        let yaw_deg = -mid_angle.to_degrees() - 90.0;

        out.push(Primitive {
            kind: PrimitiveKind::Floor,
            name: Some(format!("seg_curve_floor_{i}")),
            size: [p.width, 0.5, chord_floor.abs() + 0.2],
            position: [floor_x, origin[1] - 0.25, floor_z],
            rotation_deg: [0.0, yaw_deg, 0.0],
            color: None,
            heading: None,
            boost_strength: 20.0,
        });

        let inner_x = mid_x - p.inner_radius * cos_a;
        let inner_z = origin[2] + p.inner_radius * sin_a;
        out.push(Primitive {
            kind: PrimitiveKind::Wall,
            name: Some(format!("seg_curve_wall_in_{i}")),
            size: [p.wall_thickness, p.wall_height, chord_inner.abs() + 0.2],
            position: [inner_x, origin[1] + p.wall_height * 0.5, inner_z],
            rotation_deg: [0.0, yaw_deg, 0.0],
            color: None,
            heading: None,
            boost_strength: 20.0,
        });

        let outer_x = mid_x - outer_radius * cos_a;
        let outer_z = origin[2] + outer_radius * sin_a;
        out.push(Primitive {
            kind: PrimitiveKind::Wall,
            name: Some(format!("seg_curve_wall_out_{i}")),
            size: [p.wall_thickness, p.wall_height, chord_outer.abs() + 0.2],
            position: [outer_x, origin[1] + p.wall_height * 0.5, outer_z],
            rotation_deg: [0.0, yaw_deg, 0.0],
            color: None,
            heading: None,
            boost_strength: 20.0,
        });
    }

    out
}
