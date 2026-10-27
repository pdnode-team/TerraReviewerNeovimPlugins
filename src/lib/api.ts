import { invoke } from "@tauri-apps/api/core";
import type { ReviewResponse } from "./types";

const LOCAL_STORAGE_KEY = "terra_jwt_token";

export async function getApiKey(): Promise<string | null> {
  // 1. Try Tauri backend first
  try {
    const tauriKey = await invoke<string | null>("load_api_key");
    if (tauriKey && tauriKey.trim().length > 0) {
      localStorage.setItem(LOCAL_STORAGE_KEY, tauriKey.trim());
      return tauriKey.trim();
    }
  } catch (err) {
    // Tauri not available or command failed, ignore and check localStorage
  }

  // 2. Try localStorage
  if (typeof window !== "undefined") {
    const local = localStorage.getItem(LOCAL_STORAGE_KEY);
    if (local && local.trim().length > 0) {
      return local.trim();
    }
  }

  return null;
}

export async function saveApiKey(key: string): Promise<void> {
  const trimmed = key.trim();
  if (typeof window !== "undefined") {
    localStorage.setItem(LOCAL_STORAGE_KEY, trimmed);
  }
  try {
    await invoke("save_api_key", { apiKey: trimmed });
  } catch (err) {
    // Tauri not available
  }
}

export async function clearApiKey(): Promise<void> {
  if (typeof window !== "undefined") {
    localStorage.removeItem(LOCAL_STORAGE_KEY);
  }
  try {
    await invoke("clear_api_key");
  } catch (err) {
    // Tauri not available
  }
}

export async function fetchReviews(apiKey: string, filter: string = "waiting"): Promise<ReviewResponse> {
  const token = apiKey.trim();

  // Try Tauri command first (completely bypasses browser CORS)
  try {
    const rawJson = await invoke<string>("fetch_review_queue", {
      apiKey: token,
      filter,
    });
    return JSON.parse(rawJson) as ReviewResponse;
  } catch (tauriError) {
    // If not running inside Tauri webview, fallback to Vite proxy or direct fetch
    const url = typeof window !== "undefined" && window.location.port === "1420"
      ? `/api/review?filter=${encodeURIComponent(filter)}`
      : `https://api.terra.hackclub.com/review?filter=${encodeURIComponent(filter)}`;

    const res = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Request failed (${res.status}): ${errText || res.statusText}`);
    }

    return (await res.json()) as ReviewResponse;
  }
}
