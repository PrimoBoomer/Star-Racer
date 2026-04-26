pub fn snap_to(value: f64, step: f64) -> f64 {
    if step <= 0.0 {
        value
    } else {
        (value / step).round() * step
    }
}

pub fn snap_vec3(v: [f64; 3], step: f64) -> [f64; 3] {
    [snap_to(v[0], step), snap_to(v[1], step), snap_to(v[2], step)]
}
