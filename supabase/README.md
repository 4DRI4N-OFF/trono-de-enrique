# Zona del grupo: cuentas + fotos en reseñas

Qué cambia: las reseñas y sus fotos dejan de ser públicas. Solo las ve y las publica
el grupo de amigos, con cuenta. Cada reseña puede llevar hasta 5 fotos.

## Cómo se activa (en este orden)

1. **SQL paso 1** — en el dashboard de Supabase (SQL Editor), ejecutar
   `01_miembros_y_fotos.sql`. Es aditivo: la web actual sigue funcionando igual.
2. **Lista del grupo** — en Table Editor > `allowed_emails`, añadir un correo por
   amigo (incluido Adrián). Nadie puede leer esa lista desde la web.
3. **Fusionar la PR** — la web pide iniciar sesión para la zona de reseñas.
   Ojo: hasta el paso 4, la API antigua todavía sirve reseñas aprobadas en público.
4. **SQL paso 2** — ejecutar `02_cerrar_acceso_publico.sql`. Se acabó lo público.

## Decisión pendiente: confirmación de correo

Supabase tiene activada la confirmación por email, pero su servidor de correo de
pruebas apenas envía (límite muy bajo). Dos caminos:

- **Quitar "Confirm email"** (Authentication > Sign In / Up > Email): alta
  instantánea. Como además hace falta estar en `allowed_emails`, un extraño no
  entra; el riesgo real es que un gracioso registre el correo de un amigo antes
  que él (dentro del grupo, reversible borrando el usuario en el dashboard).
- **SMTP propio** (p. ej. Brevo gratis) o **login con Google**: correos reales y
  verificación de verdad; algo más de configuración.

La web funciona con las dos: si la cuenta necesita confirmación, lo dice al
registrarse.

## Cómo queda protegido

- Leer reseñas: solo miembros (política con `es_del_grupo()`).
- Publicar: solo miembros; la reseña nace aprobada como hasta ahora.
- Fotos: bucket privado `review-photos`; solo miembros pueden subir (máx 2 MB,
  solo imágenes) y solo miembros pueden pedir URLs firmadas de 1 hora. Si una
  reseña se oculta (`approved=false` desde el dashboard), sus fotos también
  dejan de servirse. Las URLs firmadas caducan, pero mientras viven las puede
  abrir cualquiera que las tenga: son para compartir dentro del grupo.
- Máximo 5 fotos por reseña: en la web y en la base de datos (trigger).
- La lista de correos no se puede leer desde la web por nadie.

## Moderación (como hasta ahora)

Ocultar una reseña: dashboard > Table Editor > `reviews` > poner `approved` en
falso. Desaparece de la web junto con sus fotos.

## Mudanza futura de hosting

La web es un único `index.html` estático: se sirve igual desde GitHub Pages,
un móvil o cualquier hosting. La conexión al backend son dos líneas marcadas
al principio del script (`SB_URL` / `SB_KEY`); los datos y las fotos viven en
Supabase y habría que exportarlos solo si se cambia también de backend.
