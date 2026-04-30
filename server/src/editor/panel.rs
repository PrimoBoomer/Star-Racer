use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::track::{Primitive, PrimitiveKind};

use super::segments::{bake_curve, bake_straight, CurveParams, StraightParams};
use super::selection::Selection;
use super::state::{EditorSettings, PrimRef, TrackDoc};
use super::transform_mode::DocDirty;

#[derive(Resource, Default)]
pub struct PanelState {
    pub status: String,
    pub segment_dialog: Option<SegmentDialog>,
}

pub enum SegmentDialog {
    Straight(StraightParams),
    Curve(CurveParams),
}

enum DialogAction {
    Keep,
    Cancel,
    Bake,
}

pub fn draw_panels(
    mut contexts: EguiContexts,
    mut doc: ResMut<TrackDoc>,
    mut settings: ResMut<EditorSettings>,
    selection: Res<Selection>,
    prims: Query<&PrimRef>,
    mut dirty: ResMut<DocDirty>,
    mut panel: ResMut<PanelState>,
    mut save_evt: EventWriter<SaveRequested>,
    mut load_evt: EventWriter<LoadRequested>,
) {
    let ctx = contexts.ctx_mut();

    egui::TopBottomPanel::top("topbar").show(ctx, |ui| {
        egui::menu::bar(ui, |ui| {
            ui.menu_button("File", |ui| {
                if ui.button("Open...").clicked() {
                    load_evt.send(LoadRequested);
                    ui.close_menu();
                }
                if ui.button("Save  (Ctrl+S)").clicked() {
                    save_evt.send(SaveRequested { save_as: false });
                    ui.close_menu();
                }
                if ui.button("Save As...").clicked() {
                    save_evt.send(SaveRequested { save_as: true });
                    ui.close_menu();
                }
            });

            ui.menu_button("Add", |ui| {
                if ui.button("Floor").clicked() {
                    add_default(&mut doc, PrimitiveKind::Floor);
                    dirty.mark_structural();
                    ui.close_menu();
                }
                if ui.button("Wall").clicked() {
                    add_default(&mut doc, PrimitiveKind::Wall);
                    dirty.mark_structural();
                    ui.close_menu();
                }
                if ui.button("Pad").clicked() {
                    add_default(&mut doc, PrimitiveKind::Pad);
                    dirty.mark_structural();
                    ui.close_menu();
                }
                if ui.button("Hazard").clicked() {
                    add_default(&mut doc, PrimitiveKind::Hazard);
                    dirty.mark_structural();
                    ui.close_menu();
                }
                ui.separator();
                if ui.button("Segment: Straight").clicked() {
                    panel.segment_dialog = Some(SegmentDialog::Straight(StraightParams::default()));
                    ui.close_menu();
                }
                if ui.button("Segment: Curve").clicked() {
                    panel.segment_dialog = Some(SegmentDialog::Curve(CurveParams::default()));
                    ui.close_menu();
                }
            });

            ui.separator();
            ui.label(format!(
                "Track: {}{}",
                doc.def.id,
                if doc.dirty { " *" } else { "" }
            ));
            ui.label(format!("({} prims)", doc.def.primitives.len()));
            ui.separator();
            ui.label(&panel.status);
        });
    });

    egui::TopBottomPanel::bottom("bottombar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Snap T:");
            if ui
                .add(egui::DragValue::new(&mut settings.snap_translate).speed(0.1))
                .changed()
            {}
            ui.separator();
            ui.label("Snap R°:");
            ui.add(egui::DragValue::new(&mut settings.snap_rotate_deg).speed(1.0));
            ui.separator();
            ui.label("G translate · R rotate · X/Y/Z axis · Shift no-snap · Enter confirm · Esc cancel · F focus · Del delete");
        });
    });

    if let Some(mut dialog) = panel.segment_dialog.take() {
        let mut action = DialogAction::Keep;
        egui::Window::new("Segment").collapsible(false).show(ctx, |ui| {
            match &mut dialog {
                SegmentDialog::Straight(p) => {
                    ui.label("Straight segment");
                    ui.add(egui::Slider::new(&mut p.length, 5.0..=300.0).text("length"));
                    ui.add(egui::Slider::new(&mut p.width, 5.0..=80.0).text("width"));
                    ui.add(egui::Slider::new(&mut p.wall_height, 1.0..=20.0).text("wall height"));
                    ui.add(egui::Slider::new(&mut p.wall_thickness, 1.0..=20.0).text("wall thickness"));
                    ui.horizontal(|ui| {
                        if ui.button("Bake at origin").clicked() {
                            action = DialogAction::Bake;
                        }
                        if ui.button("Cancel").clicked() {
                            action = DialogAction::Cancel;
                        }
                    });
                }
                SegmentDialog::Curve(p) => {
                    ui.label("Curve segment");
                    ui.add(egui::Slider::new(&mut p.inner_radius, 5.0..=200.0).text("inner radius"));
                    ui.add(egui::Slider::new(&mut p.width, 5.0..=80.0).text("width"));
                    ui.add(egui::Slider::new(&mut p.angle_deg, 10.0..=270.0).text("angle°"));
                    ui.add(egui::Slider::new(&mut p.wall_height, 1.0..=20.0).text("wall height"));
                    ui.add(egui::Slider::new(&mut p.wall_thickness, 1.0..=20.0).text("wall thickness"));
                    ui.add(egui::Slider::new(&mut p.segments, 2..=24).text("segments"));
                    ui.horizontal(|ui| {
                        if ui.button("Bake at origin").clicked() {
                            action = DialogAction::Bake;
                        }
                        if ui.button("Cancel").clicked() {
                            action = DialogAction::Cancel;
                        }
                    });
                }
            }
        });

        match action {
            DialogAction::Keep => {
                panel.segment_dialog = Some(dialog);
            }
            DialogAction::Cancel => {}
            DialogAction::Bake => {
                let mut new_prims = match &dialog {
                    SegmentDialog::Straight(p) => bake_straight(p, [0.0, 0.0, 0.0]),
                    SegmentDialog::Curve(p) => bake_curve(p, [0.0, 0.0, 0.0]),
                };
                doc.def.primitives.append(&mut new_prims);
                dirty.mark_structural();
                doc.dirty = true;
            }
        }
    }

    egui::SidePanel::right("inspector").default_width(280.0).show(ctx, |ui| {
        ui.heading("Inspector");
        let Some(entity) = selection.0 else {
            ui.label("(no selection)");
            return;
        };
        let Ok(prim_ref) = prims.get(entity) else {
            ui.label("(invalid selection)");
            return;
        };
        let idx = prim_ref.0;
        let Some(prim) = doc.def.primitives.get_mut(idx) else {
            ui.label("(stale selection)");
            return;
        };

        let mut changed = false;
        ui.label(format!("Index: {idx}"));

        let mut name = prim.name.clone().unwrap_or_default();
        if ui.text_edit_singleline(&mut name).changed() {
            prim.name = if name.is_empty() { None } else { Some(name) };
            changed = true;
        }

        egui::ComboBox::from_label("Kind")
            .selected_text(format!("{:?}", prim.kind))
            .show_ui(ui, |ui| {
                for k in [
                    PrimitiveKind::Floor,
                    PrimitiveKind::Wall,
                    PrimitiveKind::Pad,
                    PrimitiveKind::Hazard,
                ] {
                    if ui
                        .selectable_label(prim.kind == k, format!("{k:?}"))
                        .clicked()
                    {
                        prim.kind = k;
                        changed = true;
                    }
                }
            });

        ui.separator();
        ui.label("Size");
        changed |= drag_vec3(ui, &mut prim.size, 0.1, "S");

        ui.label("Position");
        changed |= drag_vec3(ui, &mut prim.position, 0.1, "P");

        ui.label("Rotation°");
        changed |= drag_vec3(ui, &mut prim.rotation_deg, 1.0, "R");

        let has_color = prim.color.is_some();
        let mut want_color = has_color;
        ui.checkbox(&mut want_color, "Custom color");
        if want_color != has_color {
            prim.color = if want_color { Some([0.5, 0.5, 0.5]) } else { None };
            changed = true;
        }
        if let Some(c) = prim.color.as_mut() {
            let mut rgb = [c[0] as f32, c[1] as f32, c[2] as f32];
            if ui.color_edit_button_rgb(&mut rgb).changed() {
                *c = [rgb[0] as f64, rgb[1] as f64, rgb[2] as f64];
                changed = true;
            }
        }

        if matches!(prim.kind, PrimitiveKind::Pad) {
            ui.separator();
            ui.add(
                egui::DragValue::new(&mut prim.boost_strength)
                    .speed(0.1)
                    .prefix("boost "),
            );
            let mut h = prim.heading.unwrap_or([0.0, 0.0, -1.0]);
            ui.label("Heading");
            if drag_vec3(ui, &mut h, 0.1, "H") {
                prim.heading = Some(h);
                changed = true;
            }
        }

        ui.separator();
        if ui.button("Delete primitive").clicked() {
            doc.def.primitives.remove(idx);
            dirty.mark_structural();
            doc.dirty = true;
            return;
        }

        if changed {
            dirty.mark_edit();
            doc.dirty = true;
        }
    });
}

fn drag_vec3(ui: &mut egui::Ui, v: &mut [f64; 3], speed: f64, label: &str) -> bool {
    let mut changed = false;
    ui.horizontal(|ui| {
        ui.label(label);
        for i in 0..3 {
            if ui.add(egui::DragValue::new(&mut v[i]).speed(speed)).changed() {
                changed = true;
            }
        }
    });
    changed
}

fn add_default(doc: &mut TrackDoc, kind: PrimitiveKind) {
    let (size, color): ([f64; 3], Option<[f64; 3]>) = match kind {
        PrimitiveKind::Floor => ([20.0, 1.0, 20.0], None),
        PrimitiveKind::Wall => ([10.0, 5.0, 5.0], None),
        PrimitiveKind::Pad => ([10.0, 4.0, 10.0], None),
        PrimitiveKind::Hazard => ([10.0, 5.0, 10.0], None),
    };
    doc.def.primitives.push(Primitive {
        kind,
        name: None,
        size,
        position: [0.0, size[1] * 0.5, 0.0],
        rotation_deg: [0.0, 0.0, 0.0],
        color,
        heading: if matches!(kind, PrimitiveKind::Pad) {
            Some([0.0, 0.0, -1.0])
        } else {
            None
        },
        boost_strength: 20.0,
    });
    doc.dirty = true;
}

#[derive(Event)]
pub struct SaveRequested {
    pub save_as: bool,
}

#[derive(Event)]
pub struct LoadRequested;
