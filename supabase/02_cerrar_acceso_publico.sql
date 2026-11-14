-- 02_cerrar_acceso_publico.sql
-- Paso 2 (CIERRA EL ACCESO PÚBLICO): ejecutar DESPUÉS de fusionar la PR de la web
-- y DESPUÉS de la verificación de seguridad de la fase de pruebas (ver README).
-- A partir de aquí, las reseñas y fotos solo se leen con sesión de un miembro del grupo.

drop policy if exists "ver aprobadas" on public.reviews;  -- SELECT para anon
drop policy if exists "publicar" on public.reviews;      -- INSERT para anon

-- Resultado:
-- - anon (sin sesión): no lee ni publica reseñas; la API responde 401/vacío.
-- - con sesión pero fuera de la lista: tampoco (las políticas del paso 01 exigen es_del_grupo()).
-- - miembros: leen reseñas aprobadas y sus fotos, y publican.

-- Si Adrián decide mantener el formulario para visitas sin cuenta (las reseñas que
-- escriban solo las verá el grupo), mantener el INSERT anon así en vez de borrarlo:
--   create policy "publicar" on public.reviews for insert to anon
--     with check (approved and user_id is null);

-- Para volver atrás del todo: recrear las dos políticas como estaban:
--   create policy "ver aprobadas" on public.reviews for select to anon using (approved);
--   create policy "publicar" on public.reviews for insert to anon with check (approved);
