// List / create / delete parent accounts and set app_role. Kun kaldbar af profiler med app_role = admin.
// Deploy: supabase functions deploy admin-app-users

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const supabaseUser = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userErr,
  } = await supabaseUser.auth.getUser();
  if (userErr || !user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: callerProf } = await supabaseUser
    .from("profiles")
    .select("app_role")
    .eq("auth_user_id", user.id)
    .maybeSingle();

  if (callerProf?.app_role !== "admin") {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const action = String(body.action ?? "");
  const admin = createClient(url, serviceKey);

  if (action === "list") {
    const { data: listData, error: listErr } = await admin.auth.admin.listUsers({
      perPage: 1000,
    });
    if (listErr) {
      return new Response(JSON.stringify({ error: listErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: profiles, error: pErr } = await admin
      .from("profiles")
      .select("id, auth_user_id, app_role");
    if (pErr) {
      return new Response(JSON.stringify({ error: pErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const profByAuth = new Map(
      (profiles ?? []).map((p: { auth_user_id: string; id: string; app_role: string }) => [
        p.auth_user_id,
        p,
      ]),
    );
    const users = (listData?.users ?? []).map((u: { id: string; email?: string }) => {
      const p = profByAuth.get(u.id) as
        | { id: string; app_role: string }
        | undefined;
      return {
        authUserId: u.id,
        email: u.email ?? "",
        profileId: p?.id ?? null,
        app_role: p?.app_role ?? "user",
      };
    });
    return new Response(JSON.stringify({ users }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (action === "create") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const app_role = body.app_role === "admin" ? "admin" : "user";
    if (!email || password.length < 6) {
      return new Response(
        JSON.stringify({ error: "Email og adgangskode (min. 6 tegn) kræves" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (cErr || !created?.user?.id) {
      return new Response(
        JSON.stringify({ error: cErr?.message ?? "Kunne ikke oprette bruger" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const uid = created.user.id;
    const { error: uErr } = await admin
      .from("profiles")
      .update({ app_role })
      .eq("auth_user_id", uid);
    if (uErr) {
      return new Response(JSON.stringify({ error: uErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true, authUserId: uid }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (action === "setRole") {
    const authUserId = String(body.authUserId ?? "");
    const app_role = body.app_role === "admin" ? "admin" : "user";
    if (!authUserId) {
      return new Response(JSON.stringify({ error: "authUserId mangler" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { error: rErr } = await admin
      .from("profiles")
      .update({ app_role })
      .eq("auth_user_id", authUserId);
    if (rErr) {
      return new Response(JSON.stringify({ error: rErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (action === "delete") {
    const authUserId = String(body.authUserId ?? "");
    if (!authUserId) {
      return new Response(JSON.stringify({ error: "authUserId mangler" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (authUserId === user.id) {
      return new Response(
        JSON.stringify({
          error: "Brug »Slet min konto« under Konto for at slette dig selv.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const { error: dErr } = await admin.auth.admin.deleteUser(authUserId);
    if (dErr) {
      return new Response(JSON.stringify({ error: dErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "Ukendt action" }), {
    status: 400,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
