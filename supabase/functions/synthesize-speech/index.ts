// Server-side tale: ensartet stemme for alle brugere via Google Cloud Text-to-Speech.
//
// Kræver Google Cloud-projekt med "Cloud Text-to-Speech API" aktiveret og en API-nøgle:
//   supabase secrets set GOOGLE_CLOUD_TTS_API_KEY=din_nøgle
//
// Deploy (fra repo-root):
//   supabase functions deploy synthesize-speech
//
// Stemmen kan ændres i koden (voice.name) — se Google liste over da-DK stemmer.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_CHARS = 4500;

/** Fast dansk stemme — samme for alle; kan skiftes til fx da-DK-Neural2-F efter behov. */
const DEFAULT_VOICE = "da-DK-Wavenet-D";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired session" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("GOOGLE_CLOUD_TTS_API_KEY");
    if (!apiKey || !apiKey.trim()) {
      return new Response(
        JSON.stringify({
          error: "Cloud tale er ikke konfigureret (mangler GOOGLE_CLOUD_TTS_API_KEY).",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json().catch(() => ({}));
    const text = typeof body.text === "string" ? body.text.trim() : "";
    if (!text) {
      return new Response(JSON.stringify({ error: "Missing text" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (text.length > MAX_CHARS) {
      return new Response(JSON.stringify({ error: "Text too long" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const voiceName =
      typeof body.voiceName === "string" && body.voiceName.trim()
        ? body.voiceName.trim()
        : DEFAULT_VOICE;
    const speakingRate =
      typeof body.speakingRate === "number" &&
        body.speakingRate > 0.25 &&
        body.speakingRate < 4.0
        ? body.speakingRate
        : 0.92;

    const url =
      `https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(apiKey)}`;

    const gRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        input: { text },
        voice: {
          languageCode: "da-DK",
          name: voiceName,
        },
        audioConfig: {
          audioEncoding: "MP3",
          speakingRate,
          pitch: 0,
        },
      }),
    });

    if (!gRes.ok) {
      const errText = await gRes.text();
      console.error("Google TTS error", gRes.status, errText);
      return new Response(
        JSON.stringify({ error: "Kunne ikke syntetisere tale" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = (await gRes.json()) as { audioContent?: string };
    if (!data.audioContent) {
      return new Response(JSON.stringify({ error: "Tom lyd fra tale-tjeneste" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ audioContent: data.audioContent }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
