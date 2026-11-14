# Zona del grupo: cuentas + fotos en reseñas

Qué cambia: las reseñas y sus fotos dejan de ser públicas. Solo las ve y las publica
el grupo de amigos, con cuenta. Cada reseña puede llevar hasta 5 fotos.

## Recomendación de acceso: login con Google

La barrera de verdad es la **identidad verificada**, no solo la lista de correos:
cualquiera puede escribir el correo de otro en un registro con contraseña si no hay
verificación. El camino mínimo y gratis:

1. En el dashboard: Authentication > Sign In / Up > activar el proveedor **Google**.
2. Crear el cliente OAuth en Google Cloud (pasos oficiales, gratis):
   https://supabase.com/docs/guides/auth/social-login/auth-google
3. Mantener la lista `allowed_emails` como admisión: solo entran los correos del grupo.

Con Google no hay contraseñas que repartir ni correos de confirmación que enviar:
Google ya verifica que la cuenta es de quien entra.

Alternativa (si alguien no quiere usar Google): **email + contraseña con confirmación
activada y SMTP propio** (Authentication > Emails > SMTP Settings). El servidor de
correo de pruebas de Supabase casi no envía (límite muy bajo), así que sin SMTP
propio el registro con confirmación no es viable:
https://supabase.com/docs/guides/auth/auth-smtp

No desactivar la confirmación de email: convertiría la lista de correos en la única
barrera y permitiría registrar el correo de un amigo antes que él.

## Cómo se activa (en este orden)

1. **Pruebas de seguridad primero** (fase de verificación, abajo): todo comprobado
   en un proyecto de pruebas antes de tocar este.
2. **SQL paso 1** — en el SQL Editor, ejecutar `01_miembros_y_fotos.sql`.
   Es aditivo: la web actual sigue funcionando igual.
3. **Lista del grupo** — Table Editor > `allowed_emails`, un correo por amigo
   (incluido Adrián). Nadie puede leer esa lista desde la web.
4. **Login con Google** — configurarlo como arriba (o la alternativa SMTP).
5. **Fusionar la PR** — la web pide iniciar sesión para la zona de reseñas.
   Ojo: hasta el paso 6, la API antigua todavía sirve reseñas aprobadas en público;
   nada es privado de verdad hasta cerrar el acceso anónimo.
6. **Probar** con una cuenta real del grupo (registro, reseña con fotos, salir).
7. **SQL paso 2** — ejecutar `02_cerrar_acceso_publico.sql`. Se acabó lo público.

## Fase de verificación (antes de activar nada aquí)

Plan: crear un **segundo proyecto gratuito de Supabase** como entorno de pruebas
(el plan gratis permite 2 proyectos: https://supabase.com/pricing), aplicar ahí el
SQL con datos sintéticos y comprobar de verdad contra la API y el storage:

- anon (sin sesión): no lee reseñas ni fotos, ni por API ni por ruta directa.
- cuenta registrada que NO está en `allowed_emails`: tampoco lee nada.
- miembro: lee reseñas y fotos, publica, sube hasta 5 fotos y la 6ª falla,
  no puede subir fotos a la reseña de otro ni borrar las de otro.
- ocultar una reseña (`approved=false`) deja de servir también sus fotos.

Solo con eso en verde se toca el proyecto real. Esta fase necesita luz verde de
Adrián (crea un proyecto en su cuenta) y usuarios de prueba sintéticos.

## Decisión pendiente: formulario para visitas

Hoy cualquiera puede publicar una reseña sin cuenta y sale directamente (la
moderación es después, quitando `approved` desde el dashboard). Con la zona
privada hay dos opciones — a decidir por Adrián:

- **Mantener el formulario público**: las visitas siguen escribiendo, pero sus
  reseñas solo las verá el grupo (ya no salen en público).
- **Cerrar el formulario a miembros**: solo escribe quien tiene cuenta.

El paso 2 del SQL está escrito para cerrarlo todo; lleva comentada la línea para
mantener el formulario de visitas si se elige eso.

## Cómo queda protegido

- Leer reseñas: solo miembros (política con `es_del_grupo()`).
- Publicar: solo miembros; la reseña nace aprobada y ligada a su autor.
- Fotos: bucket privado `review-photos`. Solo miembros las ven y se descargan con
  la sesión activa: **no hay URL compartible** (nada de enlaces firmados que
  cualquiera pueda reenviar). Solo el autor sube fotos a su reseña (máx. 5, también
  verificado en servidor) y solo él puede borrarlas. Si una reseña se oculta
  (`approved=false`), sus fotos también dejan de servirse.
- La lista de correos no se puede leer desde la web por nadie.
- Las funciones `security definer` van con `search_path` vacío y nombres
  cualificados, y con permisos revocados salvo `execute` para `authenticated`.

## Moderación (como hasta ahora)

Ocultar una reseña: dashboard > Table Editor > `reviews` > poner `approved` en
falso. Desaparece de la web junto con sus fotos. Para borrar del todo: borrar la
fila y, en Storage > `review-photos`, borrar la carpeta de esa reseña.

## Mudanza futura de hosting

La web es un único `index.html` estático: se sirve igual desde GitHub Pages,
un móvil o cualquier hosting. La conexión al backend son dos líneas marcadas
al principio del script (`SB_URL` / `SB_KEY`); los datos y las fotos viven en
Supabase y habría que exportarlos solo si se cambia también de backend.
