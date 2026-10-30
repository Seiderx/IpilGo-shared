// Server-side gateway to the paid third-party APIs the tourist app uses:
// Gemini (AI reasoning), OpenWeatherMap (weather) and the Google Maps web
// services (Directions, Distance Matrix). The keys live only here as Supabase
// secrets, so they are never built into the APK where anyone could extract
// them.
//
// Auth: the caller must be a signed-in user (verify_jwt on, plus getUser).
// Every call is counted per user per day (bump_api_usage, migration
// 20261030000000) so a leaked session can't run up the bill.
//
// Secrets: GEMINI_API_KEY, OPENWEATHER_API_KEY, GOOGLE_MAPS_SERVER_KEY.
// A missing secret answers 503 "not configured" and the app degrades the same
// way it did when the key was absent from .env.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const GEMINI_MODEL = "gemini-3.5-flash";
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// Calls allowed per user per day (Philippine time).
const DAILY_LIMITS = { gemini: 300, weather: 300, maps: 500 } as const;

const MAX_PROMPT_CHARS = 30_000;
const MAX_OUTPUT_TOKENS = 4096;
const MAX_MATRIX_DESTINATIONS = 25;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

class BadRequest extends Error {}

type Point = { lat: number; lng: number };

function point(v: unknown): Point {
  const p = v as Point;
  if (
    !p || typeof p.lat !== "number" || typeof p.lng !== "number" ||
    Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180
  ) {
    throw new BadRequest("Invalid coordinates");
  }
  return { lat: p.lat, lng: p.lng };
}

function travelMode(v: unknown): "driving" | "walking" {
  if (v !== "driving" && v !== "walking") throw new BadRequest("Invalid mode");
  return v;
}

// --- Gemini ---------------------------------------------------------------------

async function gemini(input: Record<string, unknown>, key: string): Promise<Response> {
  const prompt = input.prompt;
  if (typeof prompt !== "string" || !prompt || prompt.length > MAX_PROMPT_CHARS) {
    throw new BadRequest("Invalid prompt");
  }
  const system = typeof input.system === "string" ? input.system.slice(0, MAX_PROMPT_CHARS) : undefined;
  const temperature = typeof input.temperature === "number"
    ? Math.min(Math.max(input.temperature, 0), 2)
    : 0.4;
  const maxOutputTokens = typeof input.maxOutputTokens === "number"
    ? Math.min(Math.max(Math.round(input.maxOutputTokens), 1), MAX_OUTPUT_TOKENS)
    : 1024;

  const body: Record<string, unknown> = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature,
      maxOutputTokens,
      // Gemini 3.x Flash cannot fully disable thinking, but "minimal" matches
      // "no thinking" for most queries (per Gemini's own docs) and keeps
      // thinking tokens from silently eating the visible-output budget —
      // none of the app's agent tasks (classification, JSON generation,
      // short conversational replies) need deep multi-step reasoning.
      thinkingConfig: { thinkingLevel: "minimal" },
      ...(input.json === true ? { responseMimeType: "application/json" } : {}),
    },
  };
  if (system) body.systemInstruction = { parts: [{ text: system }] };

  const res = await fetch(GEMINI_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    return json({ error: `Reasoning model request failed (${res.status}): ${errText.slice(0, 300)}` }, 502);
  }
  const data = await res.json();
  const parts: { text?: string }[] = data?.candidates?.[0]?.content?.parts ?? [];
  return json({
    text: parts.map((p) => p.text ?? "").join("").trim(),
    finishReason: data?.candidates?.[0]?.finishReason ?? "unknown",
  });
}

// --- OpenWeatherMap -------------------------------------------------------------

// One Call 3.0 first; if the key isn't subscribed to it, the free 2.5
// current-weather endpoint. The app parses whichever comes back.
async function weather(input: Record<string, unknown>, key: string): Promise<Response> {
  const { lat, lng } = point(input.point);
  const oneCall = await fetch(
    `https://api.openweathermap.org/data/3.0/onecall?lat=${lat}&lon=${lng}` +
      `&units=metric&exclude=minutely,hourly,alerts&appid=${key}`,
  );
  if (oneCall.ok) return json({ source: "onecall-3.0", data: await oneCall.json() });

  const current = await fetch(
    `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lng}&units=metric&appid=${key}`,
  );
  if (!current.ok) return json({ error: `Weather request failed (${current.status})` }, 502);
  return json({ source: "current-2.5", data: await current.json() });
}

// --- Google Maps web services ---------------------------------------------------

async function directions(input: Record<string, unknown>, key: string): Promise<Response> {
  const o = point(input.origin);
  const d = point(input.destination);
  const mode = travelMode(input.mode);
  const res = await fetch(
    `https://maps.googleapis.com/maps/api/directions/json?origin=${o.lat},${o.lng}` +
      `&destination=${d.lat},${d.lng}&mode=${mode}&departure_time=now&key=${key}`,
  );
  if (!res.ok) return json({ error: `directions ${res.status}` }, 502);
  return json(await res.json());
}

async function distanceMatrix(input: Record<string, unknown>, key: string): Promise<Response> {
  const o = point(input.origin);
  if (!Array.isArray(input.destinations) || !input.destinations.length) {
    throw new BadRequest("destinations is required");
  }
  if (input.destinations.length > MAX_MATRIX_DESTINATIONS) {
    throw new BadRequest(`At most ${MAX_MATRIX_DESTINATIONS} destinations per call`);
  }
  const dests = input.destinations.map(point);
  const mode = travelMode(input.mode);
  const res = await fetch(
    `https://maps.googleapis.com/maps/api/distancematrix/json?origins=${o.lat},${o.lng}` +
      `&destinations=${dests.map((p) => `${p.lat},${p.lng}`).join("|")}` +
      `&mode=${mode}&departure_time=now&key=${key}`,
  );
  if (!res.ok) return json({ error: `distance matrix ${res.status}` }, 502);
  return json(await res.json());
}

// --- Entry ----------------------------------------------------------------------

const ACTIONS = {
  gemini: { quota: "gemini", secret: "GEMINI_API_KEY", run: gemini },
  weather: { quota: "weather", secret: "OPENWEATHER_API_KEY", run: weather },
  directions: { quota: "maps", secret: "GOOGLE_MAPS_SERVER_KEY", run: directions },
  distancematrix: { quota: "maps", secret: "GOOGLE_MAPS_SERVER_KEY", run: distanceMatrix },
} as const;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Sign in required" }, 401);

  const input = await req.json().catch(() => null);
  if (typeof input?.action !== "string" || !Object.hasOwn(ACTIONS, input.action)) {
    return json({ error: "Unknown action" }, 400);
  }
  const action = ACTIONS[input.action as keyof typeof ACTIONS];

  const key = Deno.env.get(action.secret);
  if (!key) return json({ error: "not configured" }, 503);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: allowed, error: quotaError } = await admin.rpc("bump_api_usage", {
    p_user: user.id,
    p_kind: action.quota,
    p_limit: DAILY_LIMITS[action.quota],
  });
  if (quotaError) return json({ error: quotaError.message }, 500);
  if (!allowed) return json({ error: "Daily limit reached, please try again tomorrow" }, 429);

  try {
    return await action.run(input, key);
  } catch (e) {
    if (e instanceof BadRequest) return json({ error: e.message }, 400);
    return json({ error: (e as Error).message ?? "Request failed" }, 502);
  }
});
