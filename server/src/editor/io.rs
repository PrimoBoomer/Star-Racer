use std::path::Path;

use crate::track::TrackDef;

use super::state::TrackDoc;

pub fn load_path(path: &Path) -> Result<TrackDoc, String> {
    let raw = std::fs::read_to_string(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let def = TrackDef::from_json(&raw).map_err(|e| format!("parse {}: {e}", path.display()))?;
    Ok(TrackDoc {
        path: Some(path.to_path_buf()),
        def,
        dirty: false,
    })
}

pub fn save_to_path(doc: &TrackDoc, path: &Path) -> Result<(), String> {
    let s = serde_json::to_string_pretty(&doc.def).map_err(|e| format!("serialize: {e}"))?;
    std::fs::write(path, s).map_err(|e| format!("write {}: {e}", path.display()))?;
    Ok(())
}
