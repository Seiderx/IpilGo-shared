// Studies one place's photos and menus with Gemini vision and saves plain notes
// in destinations.ai_notes. AI Search reads the notes on every search, so the
// images only have to be sent once per place.
//
// Auth: custom. The caller sends the project's service key in x-service-key,
// and it is proven by making one admin call with it. verify_jwt stays false.
//
// Secrets: GEMINI_API_KEY.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const GEMINI_MODELS = ["gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"];
const MAX_IMAGES = 14;
const MAX_NOTES_CHARS = 1500;

const INSTRUCTIONS = `You are writing private notes about a place in Ipil, Zamboanga Sibugay, Philippines,
for an AI that recommends places to tourists. Look at every photo and menu.

Write plain sentences, 150 words at most, covering only what you can see:
- Mood and setting: relaxed, lively, family, romantic, outdoor, air-conditioned, by the sea, garden.
- Seating and features: tables, cottages, pool, parking, playground, rooms, view.
- Good for: groups, couples, families, quick snacks, photos, sunsets, swimming.
- Food and drink: name the main dishes on any menu, with prices in pesos where readable.
- Rooms or rates, if a rates list is shown.

Rules:
- Only state what is visible. If a menu is unreadable, say so. Do not guess.
- Name pork dishes when a menu shows them.
- Never say a place is halal, pork-free, vegetarian or safe for any diet.
- Do not describe or identify people.
- No markdown. No heading.`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function imagePart(url: string) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`image ${res.status}: ${url}`);
  const type = res.headers.get("content-type") ?? "image/jpeg";
  const data = encodeBase64(new Uint8Array(await res.arrayBuffer()));
  return { inline_data: { mime_type: type.split(";")[0], data } };
}

async function readImages(parts: unknown[], key: string): Promise<string> {
  const body = JSON.stringify({
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
      thinkingConfig: { thinkingLevel: "minimal" },
    },
  });
  let last = "no model tried";
  for (const model of GEMINI_MODELS) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      { method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": key }, body },
    );
    if (!res.ok) {
      last = `${model} ${res.status}: ${(await res.text()).slice(0, 200)}`;
      if ([429, 503, 404].includes(res.status)) continue;
      throw new Error(last);
    }
    const data = await res.json();
    const pieces: { text?: string }[] = data?.candidates?.[0]?.content?.parts ?? [];
    const text = pieces.map((p) => p.text ?? "").join("").trim();
    if (text) return text;
    last = `${model} returned no text (${data?.candidates?.[0]?.finishReason ?? "unknown"})`;
  }
  throw new Error(last);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = req.headers.get("x-service-key") ?? "";
  if (!serviceKey) return json({ error: "Forbidden" }, 403);
  const caller = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { error: authError } = await caller.auth.admin.listUsers({ page: 1, perPage: 1 });
  if (authError) return json({ error: "Forbidden" }, 403);

  const input = await req.json().catch(() => null);
  if (typeof input?.id !== "string") return json({ error: "id is required" }, 400);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ error: "GEMINI_API_KEY not set" }, 503);

  const { data: place, error } = await caller
    .from("destinations")
    .select("id, name, category, description, images")
    .eq("id", input.id)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!place) return json({ error: "Place not found" }, 404);
  const images: string[] = (place.images ?? []).slice(0, MAX_IMAGES);
  if (!images.length) return json({ error: "Place has no photos" }, 422);

  try {
    const parts = [
      { text: `${INSTRUCTIONS}\n\nPlace: ${place.name} (${place.category ?? "place"}).` },
      ...(await Promise.all(images.map(imagePart))),
    ];
    const notes = (await readImages(parts, key)).slice(0, MAX_NOTES_CHARS);
    const { error: saveError } = await caller
      .from("destinations")
      .update({ ai_notes: notes, ai_notes_at: new Date().toISOString() })
      .eq("id", place.id);
    if (saveError) return json({ error: saveError.message }, 500);
    return json({ name: place.name, images: images.length, notes });
  } catch (e) {
    return json({ error: (e as Error).message }, 502);
  }
});
