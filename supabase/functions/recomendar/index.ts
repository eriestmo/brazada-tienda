// Recomendador de Emily Natación: paquetes de clases y productos de la tienda.
// Llama a Lovable AI Gateway desde el servidor. Secreto requerido: LOVABLE_API_KEY
// Desplegar: supabase secrets set LOVABLE_API_KEY=... && supabase functions deploy recomendar --no-verify-jwt
const GATEWAY = "https://ai.gateway.lovable.dev/v1/responses";
const MODEL = "openai/gpt-6-astra";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const TIPOS = `Tipos de clase: niños principiantes (4-7 años), niños intermedio (8-12), adultos principiantes, técnica y acondicionamiento (adultos), clase privada a domicilio (bebés, niños, adultos, adultos mayores), Aqua Fit (entrenamiento funcional de bajo impacto en el agua).`;

const schemas = {
  paquete: {
    type: "object", additionalProperties: false,
    required: ["clases", "personas", "tipo_clase", "precio", "razon", "consejo"],
    properties: {
      clases: { type: "integer" },
      personas: { type: "integer" },
      tipo_clase: { type: "string" },
      precio: { type: "integer" },
      razon: { type: "string" },
      consejo: { type: "string" },
    },
  },
  productos: {
    type: "object", additionalProperties: false,
    required: ["productos", "consejo"],
    properties: {
      productos: {
        type: "array", maxItems: 4,
        items: {
          type: "object", additionalProperties: false,
          required: ["id", "razon"],
          properties: { id: { type: "string" }, razon: { type: "string" } },
        },
      },
      consejo: { type: "string" },
    },
  },
};

const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
async function db(path: string, init: RequestInit = {}) {
  if (!SB_URL || !SB_KEY) throw new Error("db no configurada");
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { ...init, headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json", ...(init.headers || {}) } });
  if (!r.ok) throw new Error(`db ${r.status}`);
  return r.status === 204 || init.method === "POST" ? null : r.json();
}
type Pkg = { clases: number; personas: number; precio: number };
const FALLBACK: Pkg[] = [[4,1,37000],[4,2,58000],[4,3,75000],[8,1,72000],[8,2,110000],[8,3,145000],[12,1,98000],[12,2,145000],[12,3,190000]].map(([clases,personas,precio])=>({clases,personas,precio}));

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
const clip = (v: unknown, n = 600) => String(v ?? "").slice(0, n);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  const key = Deno.env.get("LOVABLE_API_KEY");
  if (!key) return json({ error: "El recomendador no está configurado." }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Solicitud inválida." }, 400); }
  const tipo = body?.tipo === "productos" ? "productos" : "paquete";

  let instructions: string, input: string;
  let pkgs: Pkg[] = FALLBACK;
  let catalog: any[] = [];
  if (tipo === "paquete") {
    try { const rows = await db("packages?select=clases,personas,precio&activo=eq.true&order=clases,personas"); if (Array.isArray(rows) && rows.length) pkgs = rows; } catch { /* usa respaldo */ }
    const tabla = pkgs.map((k) => `- ${k.clases} clases, ${k.personas} persona(s): ₡${k.precio}`).join("\n");
    instructions = `Sos la asistente de la profe Emily Duncan (Emily Natación, Costa Rica). Recomendá UN paquete mensual adecuado. Usá solo estos datos, no inventes precios:\nPaquetes mensuales (precio total del mes; vigencia 1 mes; 1 reprogramación incluida):\n${tabla}\n${TIPOS}\nEl precio debe coincidir exactamente con la tabla. Respondé en español de Costa Rica con voseo, tono cálido y motivador, frases cortas. "razon" máximo 3 frases; "consejo" 1 frase práctica.`;
    input = `Objetivos: ${clip(body.objetivos)}\nExperiencia: ${clip(body.experiencia)}\nDisponibilidad: ${clip(body.disponibilidad)}\nPersonas que nadarían juntas: ${clip(body.personas, 10)}\nEdad o para quién: ${clip(body.edad, 100)}`;
  } else {
    try { const rows = await db("products?select=id,nombre,precio,para,corto,colores,tallas&activo=eq.true&agotado=eq.false&order=orden"); if (Array.isArray(rows)) catalog = rows; } catch { /* sin db */ }
    if (!catalog.length) catalog = Array.isArray(body.catalogo) ? body.catalogo : [];
    const catalogo = catalog.slice(0, 60)
      .map((p: any) => `- id=${clip(p.id, 60)} | ${clip(p.nombre, 80)} | ₡${Number(p.precio) || 0} | para ${clip(p.para, 20)} | ${clip(p.corto, 160)}`).join("\n");
    if (!catalogo) return json({ error: "No hay productos para recomendar." }, 400);
    instructions = `Sos la asistente de la profe Emily Duncan en su tienda de equipo de natación (Costa Rica). Recomendá de 1 a 4 productos SOLO de este catálogo, usando su id exacto:\n${catalogo}\nRespondé en español de Costa Rica con voseo, tono cálido. "razon" una frase por producto; "consejo" una frase (por ejemplo sobre tallas, invitando a consultar a la profe por WhatsApp).`;
    input = `Necesidades del cliente: ${clip(body.necesidad, 800)}`;
  }

  const upstream = await fetch(GATEWAY, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "X-Lovable-AIG-SDK": "fetch" },
    body: JSON.stringify({
      model: MODEL, instructions, input, stream: true, store: false,
      reasoning: { effort: "low" },
      text: { format: { type: "json_schema", name: tipo, strict: true, schema: schemas[tipo] } },
    }),
  });
  if (!upstream.ok || !upstream.body) {
    const status = upstream.status;
    const msg = status === 429 ? "Hay muchas consultas en este momento. Probá de nuevo en un minuto."
      : status === 402 ? "El recomendador no está disponible por ahora."
      : "No pudimos generar la recomendación.";
    return json({ error: msg }, status === 429 || status === 402 || status === 403 ? status : 502);
  }

  // Leer el stream SSE y acumular el texto final.
  const reader = upstream.body.getReader();
  const dec = new TextDecoder();
  let buf = "", text = "", refused = false;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const frame = buf.slice(0, i); buf = buf.slice(i + 2);
      const data = frame.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).join("");
      if (!data || data === "[DONE]") continue;
      try {
        const ev = JSON.parse(data);
        if (ev.type === "response.output_text.delta") text += ev.delta;
        if (ev.type === "response.refusal.delta") refused = true;
      } catch { /* frame parcial */ }
    }
  }
  if (refused || !text) return json({ error: "No pudimos generar la recomendación." }, 502);
  let out: any;
  try { out = JSON.parse(text); } catch { return json({ error: "No pudimos generar la recomendación." }, 502); }

  if (tipo === "paquete") {
    // El paquete y su precio salen de la base de datos, no del modelo.
    const personas = Math.min(3, Math.max(1, parseInt(String(body.personas)) || out.personas || 1));
    const opciones = pkgs.filter((k) => k.personas === personas);
    const lista = opciones.length ? opciones : pkgs;
    const elegido = lista.find((k) => k.clases === out.clases)
      ?? lista.reduce((a, b) => Math.abs(b.clases - out.clases) < Math.abs(a.clases - out.clases) ? b : a);
    const res = { tipo, ...out, clases: elegido.clases, personas: elegido.personas, precio: elegido.precio };
    try {
      await db("recommendation_requests", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
        nombre: clip(body.nombre, 100) || null, contacto: clip(body.contacto, 100) || null,
        objetivos: clip(body.objetivos), experiencia: clip(body.experiencia), disponibilidad: clip(body.disponibilidad),
        para_quien: clip(body.edad, 100) || null, personas,
        paquete_clases: res.clases, paquete_personas: res.personas, paquete_precio: res.precio,
        tipo_clase: clip(res.tipo_clase, 120), razon: clip(res.razon, 1000),
      }) });
    } catch (e) { console.error("no se guardó la solicitud", e); }
    return json(res);
  }

  // Solo productos que existen en la base de datos, sin repetir.
  const byId = new Map(catalog.map((p: any) => [String(p.id), p]));
  const seen = new Set<string>();
  const productos = (out.productos || []).filter((x: any) => byId.has(x.id) && !seen.has(x.id) && seen.add(x.id))
    .map((x: any) => ({ id: x.id, razon: x.razon, nombre: byId.get(x.id).nombre, precio: byId.get(x.id).precio }));
  return json({ tipo, productos, consejo: out.consejo });
});
