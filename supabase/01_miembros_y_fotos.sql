-- 01_miembros_y_fotos.sql
-- Paso 1 (ADITIVO, no rompe la web actual): cuentas del grupo + fotos en reseñas.
-- Ejecutar en el SQL Editor del dashboard de Supabase ANTES de fusionar la PR de la web.
-- No toca las políticas actuales de anon; el acceso público se cierra en el paso 02.

-- ---------- Lista de miembros del grupo ----------
create table if not exists public.allowed_emails (
  email text primary key,
  added_at timestamptz not null default now()
);
alter table public.allowed_emails enable row level security;
-- Sin políticas: nadie puede leer la lista desde la API (ni miembros).
-- Solo se gestiona desde el dashboard (Table Editor) con la sesión del dueño.

-- ¿El usuario conectado está en la lista? (security definer: no expone la tabla)
create or replace function public.es_del_grupo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.allowed_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.es_del_grupo() from public;
grant execute on function public.es_del_grupo() to anon, authenticated;

-- ---------- Reseñas: acceso del grupo (además de las políticas anon actuales) ----------
create policy "grupo lee aprobadas" on public.reviews
  for select to authenticated
  using (approved and public.es_del_grupo());

create policy "grupo publica" on public.reviews
  for insert to authenticated
  with check (approved and public.es_del_grupo());

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

-- Solo miembros, y solo fotos de reseñas aprobadas (si se oculta una reseña, sus fotos también)
create policy "grupo ve fotos de aprobadas" on public.review_photos
  for select to authenticated
  using (public.es_del_grupo() and exists (
    select 1 from public.reviews r where r.id = review_id and r.approved
  ));

create policy "grupo adjunta fotos" on public.review_photos
  for insert to authenticated
  with check (public.es_del_grupo() and position between 0 and 4);

-- Máximo 5 fotos por reseña, también si alguien llama a la API a mano
create or replace function public.max_cinco_fotos()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.review_photos where review_id = new.review_id) >= 5 then
    raise exception 'maximo 5 fotos por reseña';
  end if;
  return new;
end
$$;
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

-- ¿La foto pertenece a una reseña aprobada? (cast seguro del primer tramo de la ruta)
create or replace function public.foto_visible(obj_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rid bigint;
begin
  begin
    rid := ((storage.foldername(obj_name))[1])::bigint;
  exception when others then
    return false;
  end;
  return exists (select 1 from public.reviews r where r.id = rid and r.approved);
end
$$;
revoke all on function public.foto_visible(text) from public;
grant execute on function public.foto_visible(text) to anon, authenticated;

create policy "grupo sube fotos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'review-photos' and public.es_del_grupo());

create policy "grupo ve fotos" on storage.objects
  for select to authenticated
  using (bucket_id = 'review-photos' and public.es_del_grupo() and public.foto_visible(name));

-- ---------- Miembros iniciales ----------
-- Adrián añade los correos del grupo desde el dashboard (Table Editor > allowed_emails)
-- o descomentando y editando esta línea (sin correos reales en el repo):
-- insert into public.allowed_emails (email) values ('correo1@ejemplo.com'), ('correo2@ejemplo.com');
