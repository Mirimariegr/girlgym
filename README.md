# GlowFit 💖

App de entreno gamificada para conseguir tu primera dominada.
Funciona en el móvil como una app (se puede añadir a la pantalla de inicio).

## Activar las cuentas y la nube (Supabase) — 10 minutos

1. **Crea el proyecto**: entra en [supabase.com](https://supabase.com) → *Start your project* → regístrate → *New project*.
   Ponle de nombre `glowfit`, inventa una contraseña de base de datos (guárdala) y elige la región *Europe*.
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
