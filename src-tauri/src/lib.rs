use std::fs;
use std::path::PathBuf;

fn get_key_file_path() -> Option<PathBuf> {
    let base = dirs::data_dir().or_else(dirs::config_dir)?;
    let dir = base.join("terra-reviewer");
    let _ = fs::create_dir_all(&dir);
    Some(dir.join("api_key"))
}

#[tauri::command]
fn save_api_key(api_key: String) -> Result<(), String> {
    let path = get_key_file_path().ok_or_else(|| "Failed to determine config path".to_string())?;
    fs::write(path, api_key.trim()).map_err(|e| format!("Failed to save API key: {}", e))
}

#[tauri::command]
fn load_api_key() -> Result<Option<String>, String> {
    let path = match get_key_file_path() {
        Some(p) => p,
        None => return Ok(None),
    };
    if !path.exists() {
        return Ok(None);
    }
    match fs::read_to_string(path) {
        Ok(key) => {
            let trimmed = key.trim().to_string();
            if trimmed.is_empty() {
                Ok(None)
            } else {
                Ok(Some(trimmed))
            }
        }
        Err(e) => Err(format!("Failed to read API key: {}", e)),
    }
}

#[tauri::command]
fn clear_api_key() -> Result<(), String> {
    if let Some(path) = get_key_file_path() {
        if path.exists() {
            let _ = fs::remove_file(path);
        }
    }
    Ok(())
}

#[tauri::command]
async fn fetch_review_queue(api_key: String, filter: Option<String>) -> Result<String, String> {
    let filter_param = filter.unwrap_or_else(|| "waiting".to_string());
    let url = format!("https://api.terra.hackclub.com/review?filter={}", filter_param);

    let client = reqwest::Client::new();
    let resp = client
        .get(&url)
        .header("Authorization", format!("Bearer {}", api_key.trim()))
        .header("Accept", "application/json")
        .header("User-Agent", "terra-reviewer/0.1.0")
        .send()
        .await
        .map_err(|e| format!("Network request failed: {}", e))?;

    let status = resp.status();
    let body = resp
        .text()
        .await
        .map_err(|e| format!("Failed to read response body: {}", e))?;

    if !status.is_success() {
        return Err(format!("API returned {}: {}", status, body));
    }

    Ok(body)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            save_api_key,
            load_api_key,
            clear_api_key,
            fetch_review_queue
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
