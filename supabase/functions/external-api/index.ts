// Server-side gateway to the paid third-party APIs the tourist app uses:
// Gemini (AI reasoning), OpenWeatherMap (weather) and OpenRouteService
// (Directions, Distance Matrix). The keys live only here as Supabase
// secrets, so they are never built into the APK where anyone could extract
// them.
//
// Auth: the caller must be a signed-in user (verify_jwt on, plus getUser).
// Every call is counted per user per day (bump_api_usage, migration
// 20261030000000) so a leaked session can't run up the bill.
//
// Secrets: GEMINI_API_KEY, OPENWEATHER_API_KEY, OPENROUTESERVICE_API_KEY.
//
// Errors carry a machine-readable "code" next to the message so the app can
// show a plain-language explanation:
//   not_configured  the secret for this service isn't set yet
//   daily_limit     this user used up today's quota (bump_api_usage)
//   rate_limited    the provider's own limit (Gemini free tier: per minute/day)
//   busy            the provider is overloaded; usually gone within minutes

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Main model first; when it is out of free quota (429), overloaded (503) or
// unavailable, the same request goes to lighter models, each of which has its
// own free allowance. The app only ever sees one answer or one error.
const GEMINI_MODELS = ["gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"];
const geminiEndpoint = (model: string) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

// Calls allowed per user per day (Philippine time).
const DAILY_LIMITS = { gemini: 300, weather: 300, maps: 500 } as const;

const MAX_PROMPT_CHARS = 60_000;
const MAX_OUTPUT_TOKENS = 4096;
const MAX_MATRIX_DESTINATIONS = 25;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function fail(status: number, code: string, error: string): Response {
  return json({ error, code }, status);
}

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

  let res: Response | null = null;
  let model = GEMINI_MODELS[0];
  for (model of GEMINI_MODELS) {
    res = await fetch(geminiEndpoint(model), {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify(body),
    });
    // 404: model not offered to this key; try the next one too.
    if (![429, 503, 404].includes(res.status)) break;
    console.warn(`gemini ${model} -> ${res.status}, trying next model`);
    await res.body?.cancel();
  }
  if (!res) throw new Error("No Gemini model configured");
  if (res.status === 429) return fail(429, "rate_limited", "The AI has reached its limit for now");
  if (res.status === 503 || res.status === 404) return fail(503, "busy", "The AI is busy right now");
  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    return json({ error: `Reasoning model request failed (${res.status}): ${errText.slice(0, 300)}` }, 502);
  }
  const data = await res.json();
  const parts: { text?: string }[] = data?.candidates?.[0]?.content?.parts ?? [];
  return json({
    text: parts.map((p) => p.text ?? "").join("").trim(),
    finishReason: data?.candidates?.[0]?.finishReason ?? "unknown",
    model,
  });
}

// --- OpenWeatherMap -------------------------------------------------------------

// One Call 3.0 first; if the key isn't subscribed to it, the free 2.5
// endpoints: current weather plus the 5-day / 3-hour forecast rolled up into
// One Call-shaped daily entries, so the app can plan up to 5 days ahead.
// The current-weather fields stay on the payload for older app versions.
const SEVERITY = ["Thunderstorm", "Rain", "Drizzle", "Squall", "Clouds", "Mist", "Haze", "Clear"];

type Slot = { dt: number; main: { temp: number }; weather: { main: string }[]; pop?: number };

function dailyFromSlots(slots: Slot[], tzOffsetSec: number) {
  const byDay = new Map<string, Slot[]>();
  for (const s of slots) {
    const day = new Date((s.dt + tzOffsetSec) * 1000).toISOString().slice(0, 10);
    byDay.set(day, [...(byDay.get(day) ?? []), s]);
  }
  return [...byDay.entries()].map(([day, list]) => {
    // Daytime slots (6am-6pm local) decide the day; fall back to all of them.
    const daytime = list.filter((s) => {
      const h = new Date((s.dt + tzOffsetSec) * 1000).getUTCHours();
      return h >= 6 && h <= 18;
    });
    const use = daytime.length ? daytime : list;
    const counts = new Map<string, number>();
    for (const s of use) counts.set(s.weather?.[0]?.main ?? "Clear", (counts.get(s.weather?.[0]?.main ?? "Clear") ?? 0) + 1);
    // Storms or rain anywhere in the day win; otherwise the most common sky.
    const wet = SEVERITY.slice(0, 3).find((m) => counts.has(m));
    const main = wet ?? [...counts.entries()].sort((a, b) => b[1] - a[1])[0][0];
    const [y, m, d] = day.split("-").map(Number);
    return {
      dt: Date.UTC(y, m - 1, d, 12) / 1000 - tzOffsetSec, // local noon
      temp: { day: Math.max(...use.map((s) => s.main.temp)) },
      weather: [{ main }],
      pop: Math.max(...list.map((s) => s.pop ?? 0)),
    };
  });
}

// The next 24 hours, so the app can say when rain is expected rather than
// showing only the day's peak.
type RainSlot = { dt: number; pop: number; main: string };

function upcomingSlots(list: { dt: number; pop?: number; weather?: { main: string }[] }[]): RainSlot[] {
  const now = Date.now() / 1000;
  return list
    .filter((s) => s.dt > now - 3600 && s.dt <= now + 24 * 3600)
    .map((s) => ({ dt: s.dt, pop: s.pop ?? 0, main: s.weather?.[0]?.main ?? "Clear" }));
}

async function weather(input: Record<string, unknown>, key: string): Promise<Response> {
  const { lat, lng } = point(input.point);
  const oneCall = await fetch(
    `https://api.openweathermap.org/data/3.0/onecall?lat=${lat}&lon=${lng}` +
      `&units=metric&exclude=minutely,alerts&appid=${key}`,
  );
  if (oneCall.ok) {
    const { hourly, ...rest } = await oneCall.json();
    const slots = upcomingSlots(Array.isArray(hourly) ? hourly : []);
    return json({ source: "onecall-3.0", data: { ...rest, slots } });
  }

  const q = `lat=${lat}&lon=${lng}&units=metric&appid=${key}`;
  const [current, forecast] = await Promise.all([
    fetch(`https://api.openweathermap.org/data/2.5/weather?${q}`),
    fetch(`https://api.openweathermap.org/data/2.5/forecast?${q}`),
  ]);
  if (!current.ok) return json({ error: `Weather request failed (${current.status})` }, 502);
  const now = await current.json();
  if (!forecast.ok) return json({ source: "current-2.5", data: now });

  const f = await forecast.json();
  const tz = Number(f?.city?.timezone ?? now?.timezone ?? 0);
  const list = Array.isArray(f?.list) ? f.list : [];
  const daily = dailyFromSlots(list, tz);
  // Late at night the forecast starts tomorrow; today comes from current weather.
  const today = new Date((Date.now() / 1000 + tz) * 1000).toISOString().slice(0, 10);
  const firstDay = daily[0] ? new Date((daily[0].dt + tz) * 1000).toISOString().slice(0, 10) : null;
  if (firstDay !== today) {
    const [y, m, d] = today.split("-").map(Number);
    daily.unshift({
      dt: Date.UTC(y, m - 1, d, 12) / 1000 - tz,
      temp: { day: now?.main?.temp },
      weather: [{ main: now?.weather?.[0]?.main ?? "Clear" }],
      pop: 0,
    });
  }
  return json({ source: "forecast-2.5", data: { ...now, daily, slots: upcomingSlots(list) } });
}

// --- OpenRouteService -----------------------------------------------------------

// Answers keep the Google Directions / Distance Matrix shape, so the app and
// older installed versions parse them unchanged.
const ORS_BASE = "https://api.heigit.org/openrouteservice/v2";
const ORS_OLD_BASE = "https://api.openrouteservice.org/v2";
const orsProfile = (mode: "driving" | "walking") => mode === "walking" ? "foot-walking" : "driving-car";

// Beach pins can sit far from the nearest mapped road.
const SNAP_RADIUS_M = 2000;

// OpenRouteService has no live traffic. Driving times are stretched by the
// time of day in Ipil (UTC+8), so these are estimates, never live readings.
function rushFactor(): number {
  const hour = new Date(Date.now() + 8 * 3600 * 1000).getUTCHours();
  if ((hour >= 7 && hour < 9) || (hour >= 17 && hour < 19)) return 1.25;
  if (hour >= 11 && hour < 13) return 1.1;
  return 1;
}

async function orsPost(path: string, body: unknown, key: string): Promise<Response> {
  const send = (base: string) =>
    fetch(`${base}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: key },
      body: JSON.stringify(body),
    });
  try {
    const res = await send(ORS_BASE);
    // 400 and 429 would repeat on the old host. A real "no route" 404 also
    // repeats there, so retrying costs one call and changes no answer.
    if (res.ok || res.status === 400 || res.status === 429) return res;
    console.warn(`ORS new host ${res.status}, using old host`);
    await res.body?.cancel();
  } catch (e) {
    console.warn(`ORS new host unreachable, using old host: ${e}`);
  }
  return send(ORS_OLD_BASE);
}

async function orsFailure(res: Response, label: string): Promise<Response> {
  if (res.status === 429) return fail(429, "rate_limited", "Routing has reached its limit for now");
  // 404 means no road route between the points; the app shows that as such.
  if (res.status === 404) return json({ status: "ZERO_RESULTS", routes: [], rows: [] });
  const text = await res.text().catch(() => "");
  console.warn(`${label} ${res.status}: ${text.slice(0, 300)}`);
  return json({ error: `${label} ${res.status}` }, 502);
}

function decodePolyline(encoded: string): [number, number][] {
  const out: [number, number][] = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    for (const which of [0, 1]) {
      let result = 0, shift = 0, byte = 0x20;
      while (byte >= 0x20) {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      }
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (which === 0) lat += delta;
      else lng += delta;
    }
    out.push([lat / 1e5, lng / 1e5]);
  }
  return out;
}

type OrsStep = { distance: number; duration: number; instruction: string; way_points: [number, number] };

async function directions(input: Record<string, unknown>, key: string): Promise<Response> {
  const o = point(input.origin);
  const d = point(input.destination);
  const mode = travelMode(input.mode);
  const res = await orsPost(`/directions/${orsProfile(mode)}/json`, {
    coordinates: [[o.lng, o.lat], [d.lng, d.lat]],
    radiuses: [SNAP_RADIUS_M, SNAP_RADIUS_M],
    instructions: true,
    language: "en",
  }, key);
  if (!res.ok) return orsFailure(res, "directions");

  const route = (await res.json())?.routes?.[0];
  if (!route) return json({ status: "ZERO_RESULTS", routes: [] });
  const line = decodePolyline(route.geometry);
  const at = (i: number) => {
    const p = line[Math.min(i, line.length - 1)];
    return { lat: p[0], lng: p[1] };
  };
  const steps: OrsStep[] = route.segments?.[0]?.steps ?? [];
  const seconds = route.summary?.duration ?? 0;
  return json({
    status: "OK",
    routes: [{
      overview_polyline: { points: route.geometry },
      legs: [{
        distance: { value: route.summary?.distance ?? 0 },
        duration: { value: seconds },
        ...(mode === "driving" ? { duration_in_traffic: { value: seconds * rushFactor() } } : {}),
        steps: steps.map((s) => ({
          html_instructions: s.instruction,
          distance: { value: s.distance },
          duration: { value: s.duration },
          start_location: at(s.way_points[0]),
          end_location: at(s.way_points[1]),
        })),
      }],
    }],
  });
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
  const res = await orsPost(`/matrix/${orsProfile(mode)}`, {
    locations: [o, ...dests].map((p) => [p.lng, p.lat]),
    sources: [0],
    destinations: dests.map((_, i) => i + 1),
    metrics: ["distance", "duration"],
    units: "m",
  }, key);
  if (!res.ok) return orsFailure(res, "distance matrix");

  const data = await res.json();
  const factor = mode === "driving" ? rushFactor() : 1;
  const elements = dests.map((_, i) => {
    const seconds = data?.durations?.[0]?.[i];
    const meters = data?.distances?.[0]?.[i];
    if (seconds == null || meters == null) return { status: "ZERO_RESULTS" };
    return {
      status: "OK",
      distance: { value: meters },
      duration: { value: seconds },
      ...(mode === "driving" ? { duration_in_traffic: { value: seconds * factor } } : {}),
    };
  });
  return json({ status: "OK", rows: [{ elements }] });
}

// --- Entry ----------------------------------------------------------------------

const ACTIONS = {
  gemini: { quota: "gemini", secret: "GEMINI_API_KEY", run: gemini },
  weather: { quota: "weather", secret: "OPENWEATHER_API_KEY", run: weather },
  directions: { quota: "maps", secret: "OPENROUTESERVICE_API_KEY", run: directions },
  distancematrix: { quota: "maps", secret: "OPENROUTESERVICE_API_KEY", run: distanceMatrix },
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
  if (!key) return fail(503, "not_configured", "not configured");

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
  if (!allowed) return fail(429, "daily_limit", "Daily limit reached, please try again tomorrow");

  try {
    return await action.run(input, key);
  } catch (e) {
    if (e instanceof BadRequest) return json({ error: e.message }, 400);
    return json({ error: (e as Error).message ?? "Request failed" }, 502);
  }
});
