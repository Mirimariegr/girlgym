# GirlGym 💖

App de entreno gamificada para conseguir tu primera dominada, con tu ciclo, un coach con IA y tus amigas.
Funciona en el móvil como una app (se puede añadir a la pantalla de inicio).

## Activar las cuentas y la nube (Supabase) — 10 minutos

1. **Crea el proyecto**: entra en [supabase.com](https://supabase.com) → *Start your project* → regístrate → *New project*.
   Ponle de nombre `girlgym`, inventa una contraseña de base de datos (guárdala) y elige la región *Europe*.
2. **Crea las tablas**: en el menú de la izquierda → *SQL Editor* → *New query* → pega todo el contenido de
   [`supabase/schema.sql`](supabase/schema.sql) → botón **Run**. Debe decir *Success*.
3. **Dirección de la app** (para los emails de confirmar cuenta y recuperar contraseña):
   *Authentication* → *URL Configuration* → en **Site URL** pon la dirección donde abres la app
   (por ejemplo la de GitHub Pages).
4. **Conecta la app**: *Project Settings* → *API* → copia **Project URL** y la clave **anon public**
   y pégalas en [`config.js`](config.js). (La clave *anon* es pública, no pasa nada por ponerla ahí.
   ⚠️ La *service_role* NO, esa nunca.)

Listo: al abrir la app verás **Entrar / Crear cuenta**.

## Qué se guarda en la nube

| Tabla | Qué contiene |
|---|---|
| `workouts` | Cada entreno: día y hora de inicio y fin, ejercicios, series, kilos, repeticiones, récords, XP |
| `user_state` | Tu perfil, plan, ejercicios, nivel, insignias, retos y camino a la dominada |
| `photos` + almacenamiento `photos` | Fotos de antes/después (privadas) |
| `workouts_resumen` (vista) | Tus entrenos en formato fácil: día, hora inicio, hora fin, minutos |

Cada persona solo puede ver sus propios datos (Row Level Security).
La app también guarda una copia en el móvil, así que funciona sin internet y sincroniza al volver la conexión.

## Activar el Coach 💬 (chat con IA)

El chat usa Claude (la IA de Anthropic). Tu clave de la IA se guarda en Supabase y **nunca** está dentro de la app.

1. **Clave de la IA**: entra en [console.anthropic.com](https://console.anthropic.com) → crea una cuenta → añade algo de saldo
   (con 5 € tienes para muchísimas preguntas) → *API Keys* → *Create Key* y cópiala.
2. **Guárdala en Supabase**: *Edge Functions* → *Secrets* → *Add new secret*:
   nombre `ANTHROPIC_API_KEY`, valor = tu clave.
3. **Crea la función**: *Edge Functions* → *Deploy a new function* → *Via Editor* → nombre **`coach`** →
   pega el contenido de [`supabase/functions/coach/index.ts`](supabase/functions/coach/index.ts) → *Deploy*.
4. Asegúrate de haber ejecutado el `schema.sql` actualizado (crea la tabla `coach_usage`).

**Gasto controlado**: máximo 30 preguntas por persona y día (se cambia en `DAILY_LIMIT`).
Cada pregunta cuesta aproximadamente 1-2 céntimos de dólar.

## Amigas 👯‍♀️

Ya viene incluido en `supabase/schema.sql` (si lo ejecutaste antes, vuelve a ejecutarlo: es seguro repetirlo).

- Cada persona tiene un **código de amiga** de 6 caracteres. Se comparte con "Invitar amiga".
- Al aceptar una solicitud, las dos veis los entrenos, insignias y pasos hacia la dominada de la otra.
- **Pregunta de la semana**: todas la responden y podéis reaccionar (💖🔥👏) y contestaros.
- **Mensajes de ánimo** 💌: aparecen en la pantalla Hoy de tu amiga.
- Privacidad: solo las amigas aceptadas ven tu actividad. El ciclo y las fotos **nunca** se comparten.
  Se puede dejar de compartir la actividad en Amigas → "Compartir mi actividad".
