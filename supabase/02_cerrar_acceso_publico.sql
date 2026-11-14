-- 02_cerrar_acceso_publico.sql
-- Paso 2 (CIERRA EL ACCESO PÚBLICO): ejecutar DESPUÉS de fusionar la PR de la web,
-- cuando la nueva versión ya esté publicada y comprobada con una cuenta del grupo.
-- A partir de aquí, las reseñas y fotos solo se leen con sesión de un miembro del grupo.

drop policy if exists "ver aprobadas" on public.reviews;  -- SELECT para anon
drop policy if exists "publicar" on public.reviews;      -- INSERT para anon

-- Resultado:
-- - anon (sin sesión): no lee ni publica reseñas; la API responde 401/vacío.
-- - con sesión pero fuera de la lista: tampoco (las políticas del paso 01 exigen es_del_grupo()).
-- - miembros: leen reseñas aprobadas y sus fotos, y publican.
-- Para volver atrás: basta recrear las dos políticas como estaban:
--   create policy "ver aprobadas" on public.reviews for select to anon using (approved);
--   create policy "publicar" on public.reviews for insert to anon with check (approved);
