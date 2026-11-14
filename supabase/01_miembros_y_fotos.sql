-- 01_miembros_y_fotos.sql
-- Paso 1 (ADITIVO, no rompe la web actual): cuentas del grupo + fotos en reseñas.
-- Ejecutar en el SQL Editor del dashboard de Supabase ANTES de fusionar la PR de la web.
-- No toca las políticas actuales de anon; el acceso público se cierra en el paso 02,
-- y solo después de la verificación de seguridad (ver README, fase de pruebas).

-- ---------- Lista de miembros del grupo ----------
create table if not exists public.allowed_emails (
  email text primary key,
  added_at timestamptz not null default now()
);
alter table public.allowed_emails enable row level security;
-- Sin políticas + sin permisos de lectura: nadie lee la lista desde la API (ni miembros).
revoke select on public.allowed_emails from anon, authenticated;
-- Solo se gestiona desde el dashboard (Table Editor) con la sesión del dueño.

-- ¿El usuario conectado está en la lista? (security definer: no expone la tabla)
create or replace function public.es_del_grupo()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.allowed_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.es_del_grupo() from public;
grant execute on function public.es_del_grupo() to authenticated;

-- ---------- Reseñas: acceso del grupo (además de las políticas anon actuales) ----------
-- Autoría: cada reseña nueva queda ligada a su autor (las antiguas quedan sin autor).
alter table public.reviews
  add column if not exists user_id uuid references auth.users(id) default auth.uid();

create policy "grupo lee aprobadas" on public.reviews
  for select to authenticated
  using (approved and public.es_del_grupo());

create policy "grupo publica" on public.reviews
  for insert to authenticated
  with check (approved and public.es_del_grupo() and user_id = auth.uid());

-- ---------- Fotos de las reseñas ----------
create table if not exists public.review_photos (
  id bigint generated always as identity primary key,
  review_id bigint not null references public.reviews(id) on delete cascade,
  path text not null,
  position smallint not null default 0,
  created_at timestamptz not null default now(),
  unique (review_id, path)
);
alter table public.review_photos enable row level security;

-- ¿Es mía esta reseña? (security definer, sin exponer nada extra)
create or replace function public.es_autor_resena(rid bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.reviews r
    where r.id = rid and r.user_id = auth.uid()
  );
$$;
revoke all on function public.es_autor_resena(bigint) from public;
grant execute on function public.es_autor_resena(bigint) to authenticated;

-- Solo miembros, y solo fotos de reseñas aprobadas (si se oculta una reseña, sus fotos también)
create policy "grupo ve fotos de aprobadas" on public.review_photos
  for select to authenticated
  using (public.es_del_grupo() and exists (
    select 1 from public.reviews r where r.id = review_id and r.approved
  ));

-- Solo el autor de la reseña adjunta fotos a esa reseña
create policy "autor adjunta fotos" on public.review_photos
  for insert to authenticated
  with check (public.es_del_grupo() and position between 0 and 4
              and public.es_autor_resena(review_id));

-- Solo el autor borra las filas de fotos de su reseña
create policy "autor borra fotos" on public.review_photos
  for delete to authenticated
  using (public.es_autor_resena(review_id));

-- Máximo 5 fotos por reseña en la tabla, también si alguien llama a la API a mano
create or replace function public.max_cinco_fotos()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.review_photos where review_id = new.review_id) >= 5 then
    raise exception 'maximo 5 fotos por reseña';
  end if;
  return new;
end
$$;
revoke all on function public.max_cinco_fotos() from public;
drop trigger if exists max_cinco_fotos on public.review_photos;
create trigger max_cinco_fotos
  before insert on public.review_photos
  for each row execute function public.max_cinco_fotos();

-- ---------- Almacenamiento (bucket privado) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'review-photos', 'review-photos', false,
  2097152, -- 2 MB por archivo (la web comprime a ~300 KB antes de subir)
  array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif']
)
on conflict (id) do nothing;

-- id de reseña del primer tramo de la ruta ("<review_id>/<n>.jpg"), NULL si no cuadra
create or replace function public.ruta_rid(obj_name text)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return ((storage.foldername(obj_name))[1])::bigint;
exception when others then
  return null;
end
$$;
revoke all on function public.ruta_rid(text) from public;
grant execute on function public.ruta_rid(text) to authenticated;

-- ¿La foto pertenece a una reseña aprobada?
create or replace function public.foto_visible(obj_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  rid bigint;
begin
  rid := public.ruta_rid(obj_name);
  if rid is null then
    return false;
  end if;
  return exists (select 1 from public.reviews r where r.id = rid and r.approved);
end
$$;
revoke all on function public.foto_visible(text) from public;
grant execute on function public.foto_visible(text) to authenticated;

-- Cuántas fotos hay ya subidas en la carpeta de una reseña (límite 5 también en storage)
create or replace function public.fotos_en_carpeta(rid bigint)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from storage.objects
  where bucket_id = 'review-photos'
    and (storage.foldername(name))[1] = rid::text;
$$;
revoke all on function public.fotos_en_carpeta(bigint) from public;
grant execute on function public.fotos_en_carpeta(bigint) to authenticated;

-- Subir: solo el autor de la reseña, a su carpeta, y sin pasar de 5 archivos
create policy "autor sube fotos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'review-photos'
    and public.es_del_grupo()
    and public.ruta_rid(name) is not null
    and public.es_autor_resena(public.ruta_rid(name))
    and public.fotos_en_carpeta(public.ruta_rid(name)) < 5
  );

-- Ver: solo miembros, y solo si la reseña sigue aprobada (descarga autenticada, sin URL pública)
create policy "grupo ve fotos" on storage.objects
  for select to authenticated
  using (bucket_id = 'review-photos' and public.es_del_grupo() and public.foto_visible(name));

-- Borrar: solo el autor de la reseña (la limpieza general se hace desde el dashboard)
create policy "autor borra archivos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'review-photos' and public.es_autor_resena(public.ruta_rid(name)));

-- ---------- Miembros iniciales ----------
-- Adrián añade los correos del grupo desde el dashboard (Table Editor > allowed_emails).
-- Sin correos reales en el repo.
