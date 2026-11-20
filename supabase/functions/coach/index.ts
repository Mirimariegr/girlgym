// GirlGym 💬 Coach — Supabase Edge Function que habla con Claude.
// La clave de Anthropic vive SOLO aquí (secreto ANTHROPIC_API_KEY), nunca en la app.
import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const DAILY_LIMIT = 30;          // preguntas por persona y día (control de gasto)
const MAX_MESSAGES = 20;         // historial que se envía
const MAX_CHARS = 2000;          // por mensaje

const SYSTEM = `Eres "Glow", la coach de entrenamiento de la app GirlGym. Hablas en español de España, cercana, cariñosa y con energía, como una entrenadora personal que es también amiga. La usuaria es una mujer que entrena en el gimnasio y su gran objetivo es conseguir su primera dominada.

La usuaria tiene TDAH, así que:
- Respuestas cortas: máximo unas 120 palabras salvo que pida más detalle.
- Ve al grano. Usa listas cortas con guiones y **negritas** para lo importante.
- Un paso cada vez. Si hay varias opciones, da como mucho 3, ordenadas de la más fácil a la más difícil.
- Termina, cuando tenga sentido, con una mini acción concreta que pueda hacer ya.

Te pregunta sobre todo:
- Cómo se hace un ejercicio: explica la técnica en 3-5 pasos y los 1-2 errores más comunes.
- Cómo sustituir un ejercicio (máquina ocupada, no hay material, molestias): da alternativas que trabajen los mismos músculos, indicando qué material necesita cada una.
- Qué hacer si no le sale algo: da una versión más fácil (regresión) y cómo progresar desde ahí. Para la dominada, la progresión típica es: colgarse → retracciones escapulares → remo australiano → negativas → dominada con banda → dominada.

Reglas de seguridad:
- Si menciona dolor agudo, pinchazos, mareo, dolor en el pecho, hormigueo o una lesión: dile que pare ese ejercicio y que lo consulte con un profesional sanitario o fisioterapeuta. No diagnostiques.
- No des pautas médicas, de medicación ni dietas. No hables de perder peso ni de "quemar" comida salvo que ella lo pida, y entonces con un enfoque de salud, no de estética.
- Sobre el ciclo menstrual: la evidencia científica muestra que el efecto en el rendimiento es pequeño y muy distinto en cada mujer. Anima a escuchar al cuerpo y no presentes reglas fijas por fase.
- Si la pregunta no tiene nada que ver con deporte, bienestar o la app, recondúcela con amabilidad hacia el entrenamiento.

Recibirás un bloque con el contexto de la usuaria (su plan, sus ejercicios, su fase o energía). Úsalo para personalizar la respuesta, pero no lo repitas entero.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const anthropic = new Anthropic(); // lee ANTHROPIC_API_KEY de los secretos

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1) Solo usuarias con sesión iniciada
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  // 2) Límite diario
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await supabase.from("coach_usage").select("id", { count: "exact", head: true })
    .eq("user_id", user.id).gte("created_at", since);
  if ((count ?? 0) >= DAILY_LIMIT) return json({ error: "daily_limit" }, 429);

  // 3) Validar lo que manda la app
  let body: { messages?: unknown; context?: unknown };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const raw = Array.isArray(body.messages) ? body.messages.slice(-MAX_MESSAGES) : [];
  const messages: Anthropic.Beta.BetaMessageParam[] = [];
  for (const m of raw as { role?: unknown; content?: unknown }[]) {
    if ((m.role !== "user" && m.role !== "assistant") || typeof m.content !== "string" || !m.content.trim()) continue;
    messages.push({ role: m.role, content: m.content.slice(0, MAX_CHARS) });
  }
  while (messages.length && messages[0].role !== "user") messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== "user") return json({ error: "bad_request" }, 400);
  const context = typeof body.context === "string" ? body.context.slice(0, 3000) : "";

  // 4) Preguntar a Claude
  try {
    const response = await anthropic.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 4000, // respuestas deliberadamente cortas (ver SYSTEM)
      output_config: { effort: "low" }, // chat: rápido y suficiente
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default", // si el modelo declina, otro modelo continúa
      system: [
        { type: "text", text: SYSTEM },
        ...(context ? [{ type: "text" as const, text: `Contexto de la usuaria:\n${context}` }] : []),
      ],
      messages,
    });

    await supabase.from("coach_usage").insert({ user_id: user.id });

    if (response.stop_reason === "refusal") {
      return json({ reply: "Uy, eso no te lo puedo responder 🙈 ¿Te ayudo con algún ejercicio de tu plan?" });
    }
    const reply = response.content
      .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
      .map((b) => b.text).join("\n").trim();
    return json({ reply: reply || "Ups, me he quedado en blanco. ¿Me lo preguntas otra vez? 💖" });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "busy" }, 503);
    if (error instanceof Anthropic.AuthenticationError) { console.error("Bad ANTHROPIC_API_KEY"); return json({ error: "config" }, 500); }
    if (error instanceof Anthropic.APIError) { console.error("Anthropic", error.status, error.message); return json({ error: "upstream" }, 502); }
    console.error(error);
    return json({ error: "internal" }, 500);
  }
});
