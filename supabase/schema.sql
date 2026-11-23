-- Brazada: clases, reservas y pagos.
-- Pegar completo en Supabase > SQL Editor > Run. Se puede volver a ejecutar sin perder datos.
-- Horas en America/Costa_Rica. Las reglas de negocio se validan aquí, no solo en la página.

create extension if not exists pgcrypto;

-- Catálogo -------------------------------------------------------------------

create table if not exists public.class_types (
  id text primary key,
  nombre text not null,
  edades text not null,
  minutos int not null,
  cupo int not null check (cupo > 0),
  orden int not null default 0
);

create table if not exists public.schedule (
  id bigint generated always as identity primary key,
  weekday int not null check (weekday between 0 and 6), -- 0 = domingo, igual que Date.getDay()
  start_time time not null,
  class_type text not null references public.class_types(id) on delete cascade,
  unique (weekday, start_time, class_type)
);

create table if not exists public.plans (
  name text primary key,
  price int not null check (price >= 0),
  monthly boolean not null
);

-- Cuentas, alumnos, reservas y pagos ----------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  phone text not null default '',
  plan text references public.plans(name) on update cascade,
  role text not null default 'alumno' check (role in ('alumno', 'profe')),
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  age text not null default '',
  is_self boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_type text not null references public.class_types(id),
  starts_at timestamptz not null,
  status text not null default 'reservada' check (status in ('reservada', 'cancelada', 'asistió')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists bookings_one_per_student_slot
  on public.bookings (student_id, starts_at) where status = 'reservada';
create index if not exists bookings_by_slot
  on public.bookings (class_type, starts_at) where status = 'reservada';

-- month va de 1 a 12. "Vencido" no se guarda: es un pago pendiente cuya due_date ya pasó.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.profiles(id) on delete cascade,
  year int not null,
  month int not null check (month between 1 and 12),
  amount int not null check (amount >= 0),
  due_date date not null,
  paid_date date,
  status text not null default 'pendiente' check (status in ('pendiente', 'en revisión', 'pagado')),
  created_at timestamptz not null default now(),
  unique (account_id, year, month)
);

-- Datos iniciales (ejemplos: Emily los ajusta aquí) --------------------------

insert into public.class_types (id, nombre, edades, minutos, cupo, orden) values
  ('ninos-inicio',     'Niños principiantes',          '4 a 7 años',          45, 6, 1),
  ('ninos-intermedio', 'Niños nivel intermedio',       '8 a 12 años',         45, 8, 2),
  ('adultos-inicio',   'Adultos principiantes',        'Adultos',             60, 6, 3),
  ('adultos-tecnica',  'Técnica y acondicionamiento',  'Adultos',             60, 8, 4),
  ('privada',          'Clase privada',                'Todas las edades',    45, 1, 5)
on conflict (id) do nothing;
update public.class_types set nombre = 'Clase privada a domicilio', edades = 'Bebés, niños, adultos y adultos mayores' where id = 'privada';

insert into public.schedule (weekday, start_time, class_type) values
  (1, '16:00', 'ninos-inicio'), (1, '17:00', 'ninos-intermedio'), (1, '18:30', 'adultos-inicio'),
  (3, '16:00', 'ninos-inicio'), (3, '17:00', 'ninos-intermedio'), (3, '18:30', 'adultos-inicio'),
  (2, '06:00', 'adultos-tecnica'), (2, '16:00', 'ninos-inicio'), (2, '17:00', 'ninos-intermedio'),
  (4, '06:00', 'adultos-tecnica'), (4, '16:00', 'ninos-inicio'), (4, '17:00', 'ninos-intermedio'),
  (5, '15:00', 'privada'), (5, '16:00', 'privada'), (5, '17:00', 'privada'),
  (6, '08:00', 'ninos-inicio'), (6, '09:00', 'ninos-intermedio'), (6, '10:00', 'adultos-inicio')
on conflict (weekday, start_time, class_type) do nothing;

insert into public.plans (name, price, monthly) values
  ('1 clase por semana', 28000, true),
  ('2 clases por semana', 48000, true),
  ('Clase suelta', 9000, false),
  ('Clase privada', 15000, false)
on conflict (name) do nothing;

-- Funciones de apoyo ---------------------------------------------------------

create or replace function public.is_profe() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'profe');
$$;

create or replace function public.cr_today() returns date
language sql stable set search_path = pg_catalog, public as $$
  select (now() at time zone 'America/Costa_Rica')::date;
$$;

-- Crea el perfil y el primer alumno a partir de los datos del registro.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_plan text := m->>'plan';
begin
  if v_plan is not null and not exists (select 1 from public.plans where name = v_plan) then
    v_plan := null;
  end if;
  insert into public.profiles (id, name, email, phone, plan)
  values (new.id,
          coalesce(nullif(trim(m->>'name'), ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Alumno'),
          coalesce(new.email, ''),
          coalesce(m->>'phone', ''),
          v_plan)
  on conflict (id) do nothing;
  if nullif(trim(m->>'student_name'), '') is not null then
    insert into public.students (account_id, name, age, is_self)
    values (new.id, trim(m->>'student_name'), coalesce(m->>'student_age', ''),
            coalesce(m->>'is_self', 'false') = 'true');
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Comprueba que la hora pedida existe en el horario y está dentro de la ventana de reservas.
create or replace function public.check_slot(p_class text, p_starts timestamptz) returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  local_ts timestamp := p_starts at time zone 'America/Costa_Rica';
begin
  if p_starts <= now() then
    raise exception 'Esa clase ya empezó. Elegí otro horario.';
  end if;
  if p_starts > now() + interval '29 days' then
    raise exception 'Solo se puede reservar en las próximas 4 semanas.';
  end if;
  if not exists (
    select 1 from public.schedule
    where class_type = p_class
      and weekday = extract(dow from local_ts)::int
      and start_time = local_ts::time
  ) then
    raise exception 'Ese horario no existe.';
  end if;
end $$;

-- Cupos ocupados por clase, sin revelar quién reservó. Visible para todos.
create or replace function public.slot_counts(p_from timestamptz, p_to timestamptz)
returns table (class_type text, starts_at timestamptz, taken int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if p_to <= p_from or p_to - p_from > interval '35 days' then
    raise exception 'El rango de fechas no es válido.';
  end if;
  return query
    select b.class_type, b.starts_at, count(*)::int
    from public.bookings b
    where b.status = 'reservada' and b.starts_at >= p_from and b.starts_at < p_to
    group by b.class_type, b.starts_at;
end $$;

-- Acciones del alumno --------------------------------------------------------

create or replace function public.book_class(p_student uuid, p_class text, p_starts timestamptz)
returns public.bookings
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b public.bookings;
  cap int;
begin
  p_starts := date_trunc('minute', p_starts);
  perform 1 from public.students where id = p_student and account_id = auth.uid() for share;
  if not found then
    raise exception 'No se encontró el alumno en tu cuenta.';
  end if;
  perform public.check_slot(p_class, p_starts);
  perform pg_advisory_xact_lock(hashtext(p_class || ':' || extract(epoch from p_starts)::text));
  if exists (select 1 from public.bookings
             where student_id = p_student and starts_at = p_starts and status = 'reservada') then
    raise exception 'Este alumno ya tiene una reserva en ese horario.';
  end if;
  select cupo into cap from public.class_types where id = p_class;
  if cap is null then
    raise exception 'Tipo de clase no válido.';
  end if;
  if (select count(*) from public.bookings
      where class_type = p_class and starts_at = p_starts and status = 'reservada') >= cap then
    raise exception 'La clase ya está llena.';
  end if;
  insert into public.bookings (student_id, class_type, starts_at)
  values (p_student, p_class, p_starts)
  returning * into b;
  return b;
end $$;

create or replace function public.reschedule_booking(p_booking uuid, p_starts timestamptz)
returns public.bookings
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b public.bookings;
  cap int;
begin
  p_starts := date_trunc('minute', p_starts);
  select bk.* into b from public.bookings bk
  join public.students s on s.id = bk.student_id
  where bk.id = p_booking and s.account_id = auth.uid() and bk.status = 'reservada'
  for update of bk;
  if not found then
    raise exception 'No se encontró la reserva.';
  end if;
  if b.starts_at - now() < interval '12 hours' then
    raise exception 'Faltan menos de 12 horas para la clase. Escribile a la profe por WhatsApp.';
  end if;
  if p_starts - now() < interval '12 hours' then
    raise exception 'El nuevo horario debe ser al menos 12 horas después de ahora.';
  end if;
  perform public.check_slot(b.class_type, p_starts);
  perform pg_advisory_xact_lock(hashtext(b.class_type || ':' || extract(epoch from p_starts)::text));
  if exists (select 1 from public.bookings
             where student_id = b.student_id and starts_at = p_starts
               and status = 'reservada' and id <> b.id) then
    raise exception 'Este alumno ya tiene una reserva en ese horario.';
  end if;
  select cupo into cap from public.class_types where id = b.class_type;
  if (select count(*) from public.bookings
      where class_type = b.class_type and starts_at = p_starts
        and status = 'reservada' and id <> b.id) >= cap then
    raise exception 'La clase ya está llena.';
  end if;
  update public.bookings set starts_at = p_starts, updated_at = now()
  where id = b.id returning * into b;
  return b;
end $$;

create or replace function public.cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b public.bookings;
begin
  select bk.* into b from public.bookings bk
  join public.students s on s.id = bk.student_id
  where bk.id = p_booking and s.account_id = auth.uid() and bk.status = 'reservada'
  for update of bk;
  if not found then
    raise exception 'No se encontró la reserva.';
  end if;
  if b.starts_at - now() < interval '12 hours' then
    raise exception 'Faltan menos de 12 horas para la clase. Escribile a la profe por WhatsApp.';
  end if;
  update public.bookings set status = 'cancelada', updated_at = now() where id = b.id;
end $$;

create or replace function public.remove_student(p_student uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform 1 from public.students where id = p_student and account_id = auth.uid() for update;
  if not found then
    raise exception 'No se encontró el alumno.';
  end if;
  if exists (select 1 from public.bookings
             where student_id = p_student and status = 'reservada' and starts_at > now()) then
    raise exception 'Primero cancelá las clases futuras de este alumno.';
  end if;
  delete from public.students where id = p_student;
end $$;

-- Crea el cobro del próximo mes para planes mensuales (vence el día 5). La página lo llama al iniciar sesión.
create or replace function public.ensure_my_payment() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  p public.profiles;
  v_price int;
  v_monthly boolean;
  today date := public.cr_today();
  due date;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found or p.role <> 'alumno' or p.plan is null then
    return;
  end if;
  select price, monthly into v_price, v_monthly from public.plans where name = p.plan;
  if not coalesce(v_monthly, false) then
    return;
  end if;
  -- Si la cuenta ya existía antes de este mes, también le corresponde el cobro del mes en curso.
  if extract(day from today) > 5 and p.created_at < date_trunc('month', today) then
    due := make_date(extract(year from today)::int, extract(month from today)::int, 5);
    insert into public.payments (account_id, year, month, amount, due_date)
    values (p.id, extract(year from due)::int, extract(month from due)::int, v_price, due)
    on conflict (account_id, year, month) do nothing;
  end if;
  if extract(day from today) <= 5 then
    due := make_date(extract(year from today)::int, extract(month from today)::int, 5);
  else
    due := (date_trunc('month', today) + interval '1 month')::date + 4;
  end if;
  insert into public.payments (account_id, year, month, amount, due_date)
  values (p.id, extract(year from due)::int, extract(month from due)::int, v_price, due)
  on conflict (account_id, year, month) do nothing;
end $$;

create or replace function public.report_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.payments set status = 'en revisión'
  where id = p_payment and account_id = auth.uid() and status = 'pendiente';
  if not found then
    raise exception 'No se puede reportar este pago.';
  end if;
end $$;

-- Acciones de la profe -------------------------------------------------------

create or replace function public.confirm_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_profe() then
    raise exception 'Esta acción es solo para la profe.';
  end if;
  update public.payments set status = 'pagado', paid_date = public.cr_today()
  where id = p_payment and status <> 'pagado';
  if not found then
    raise exception 'No se encontró el pago o ya estaba confirmado.';
  end if;
end $$;

create or replace function public.admin_cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_profe() then
    raise exception 'Esta acción es solo para la profe.';
  end if;
  update public.bookings set status = 'cancelada', updated_at = now()
  where id = p_booking and status = 'reservada';
  if not found then
    raise exception 'No se encontró la reserva.';
  end if;
end $$;

-- Asistencia: la profe marca si la persona vino ('asistió'), no vino ('ausente') o lo deshace ('reservada').
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('reservada', 'cancelada', 'asistió', 'ausente'));

create or replace function public.mark_attendance(p_booking uuid, p_status text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_profe() then
    raise exception 'Esta acción es solo para la profe.';
  end if;
  if p_status not in ('asistió', 'ausente', 'reservada') then
    raise exception 'Estado de asistencia no válido.';
  end if;
  update public.bookings set status = p_status, updated_at = now()
  where id = p_booking and status in ('reservada', 'asistió', 'ausente') and starts_at <= now();
  if not found then
    raise exception 'Solo se puede marcar asistencia de una clase que ya empezó.';
  end if;
end $$;

-- Permisos de funciones ------------------------------------------------------

revoke execute on function
  public.handle_new_user(), public.check_slot(text, timestamptz),
  public.book_class(uuid, text, timestamptz), public.reschedule_booking(uuid, timestamptz),
  public.cancel_booking(uuid), public.remove_student(uuid), public.ensure_my_payment(),
  public.report_payment(uuid), public.confirm_payment(uuid), public.admin_cancel_booking(uuid),
  public.mark_attendance(uuid, text)
  from public, anon;
revoke execute on function public.handle_new_user(), public.check_slot(text, timestamptz) from authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;
grant execute on function
  public.book_class(uuid, text, timestamptz), public.reschedule_booking(uuid, timestamptz),
  public.cancel_booking(uuid), public.remove_student(uuid), public.ensure_my_payment(),
  public.report_payment(uuid), public.confirm_payment(uuid), public.admin_cancel_booking(uuid),
  public.mark_attendance(uuid, text)
  to authenticated;
grant execute on function public.slot_counts(timestamptz, timestamptz), public.is_profe(), public.cr_today()
  to anon, authenticated;

-- Seguridad por filas (RLS) --------------------------------------------------

alter table public.class_types enable row level security;
alter table public.schedule    enable row level security;
alter table public.plans       enable row level security;
alter table public.profiles    enable row level security;
alter table public.students    enable row level security;
alter table public.bookings    enable row level security;
alter table public.payments    enable row level security;

drop policy if exists "catalogo publico" on public.class_types;
create policy "catalogo publico" on public.class_types for select to anon, authenticated using (true);
drop policy if exists "horario publico" on public.schedule;
create policy "horario publico" on public.schedule for select to anon, authenticated using (true);
drop policy if exists "planes publicos" on public.plans;
create policy "planes publicos" on public.plans for select to anon, authenticated using (true);

drop policy if exists "ver perfil" on public.profiles;
create policy "ver perfil" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_profe());
drop policy if exists "editar mi perfil" on public.profiles;
create policy "editar mi perfil" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "ver alumnos" on public.students;
create policy "ver alumnos" on public.students for select to authenticated
  using (account_id = auth.uid() or public.is_profe());
drop policy if exists "agregar alumno" on public.students;
create policy "agregar alumno" on public.students for insert to authenticated
  with check (account_id = auth.uid());
drop policy if exists "editar alumno" on public.students;
create policy "editar alumno" on public.students for update to authenticated
  using (account_id = auth.uid()) with check (account_id = auth.uid());

drop policy if exists "ver reservas" on public.bookings;
create policy "ver reservas" on public.bookings for select to authenticated
  using (public.is_profe()
         or exists (select 1 from public.students s where s.id = student_id and s.account_id = auth.uid()));

drop policy if exists "ver pagos" on public.payments;
create policy "ver pagos" on public.payments for select to authenticated
  using (account_id = auth.uid() or public.is_profe());

-- Las tablas solo se modifican con las funciones de arriba, salvo estos casos:
revoke insert, update, delete on public.class_types, public.schedule, public.plans,
  public.bookings, public.payments from anon, authenticated;
revoke insert, update, delete on public.profiles, public.students from anon;
revoke update (name, email, phone, plan, role) on public.profiles from authenticated;
revoke insert, update, delete on public.profiles from authenticated;
grant update (name, phone) on public.profiles to authenticated; -- el plan lo cambia la profe
revoke update (name, age, is_self, account_id) on public.students from authenticated;
revoke update, delete on public.students from authenticated;
grant update (name, age) on public.students to authenticated;

-- Productos de la tienda --------------------------------------------------------
-- Todos ven los productos activos; solo la profe crea, edita u oculta productos (panel > Productos).
create table if not exists public.products (
  id text primary key check (id ~ '^[a-z0-9-]+$'),
  cat text not null check (cat in ('gafas', 'gorras', 'entrenamiento', 'trajes', 'accesorios')),
  nombre text not null check (length(trim(nombre)) > 0),
  precio int not null check (precio >= 0),
  para text not null default 'Todos' check (para in ('Niños', 'Adultos', 'Todos')),
  corto text not null default '',
  descripcion text not null default '',
  profe text,
  colores text[] not null default array['Celeste']::text[] check (cardinality(colores) > 0),
  tallas text[],
  talla_nombre text not null default 'Talla',
  dibujo text not null default 'kit',
  tag text check (tag in ('recomendado', 'nuevo', 'ultimas')),
  detalles text[] not null default '{}'::text[],
  agotado boolean not null default false,
  activo boolean not null default true,
  orden int not null default 100,
  updated_at timestamptz not null default now()
);

alter table public.products enable row level security;
drop policy if exists "ver productos" on public.products;
create policy "ver productos" on public.products for select to anon, authenticated
  using (activo or public.is_profe());
drop policy if exists "profe crea productos" on public.products;
create policy "profe crea productos" on public.products for insert to authenticated
  with check (public.is_profe());
drop policy if exists "profe edita productos" on public.products;
create policy "profe edita productos" on public.products for update to authenticated
  using (public.is_profe()) with check (public.is_profe());
revoke insert, update, delete on public.products from anon;
revoke delete on public.products from authenticated;

insert into public.products (id, cat, nombre, precio, para, corto, descripcion, profe, colores, tallas, talla_nombre, dibujo, tag, detalles, orden) values
  ('gafas-junior', 'gafas', 'Gafas Junior Antiempañante', 6500, 'Niños', 'Ajuste cómodo para tus primeras brazadas.', 'Gafas para niños de 6 a 12 años, con ajuste suave y lentes antiempañantes para ver con claridad durante la clase.', 'Son las que uso con mis alumnos de 6 a 12 años: ajustan sin apretar y no se empañan.', array['Lila', 'Celeste', 'Rosa']::text[], null, 'Edad', 'gafas', 'recomendado', array['Recomendadas para edades de 6 a 12 años.', 'Puente y correa ajustables para un sello cómodo.', 'Lentes antiempañantes para piscina.']::text[], 1),
  ('gafas-entreno', 'gafas', 'Gafas de Entrenamiento', 9900, 'Adultos', 'Lente claro para piscina techada.', 'Gafas cómodas para entrenamiento frecuente en piscina techada. Su lente claro ayuda a mantener una visión natural bajo techo.', null, array['Negro', 'Celeste', 'Transparente']::text[], null, 'Talla', 'gafas', null, array['Lente claro para piscinas techadas.', 'Correa ajustable para un calce firme.', 'Diseñadas para sesiones frecuentes.']::text[], 2),
  ('gafas-espejo', 'gafas', 'Gafas Espejadas Pro', 14900, 'Adultos', 'Protección UV para nadar al aire libre.', 'Gafas con lente espejado para entrenar al aire libre. La protección UV ayuda a cuidar tus ojos cuando nadás bajo el sol.', null, array['Plateado', 'Azul', 'Lila']::text[], null, 'Talla', 'gafas', 'nuevo', array['Lente espejado para reducir el brillo.', 'Protección UV para piscina al aire libre.', 'Correa ajustable de buen soporte.']::text[], 3),
  ('gorra-silicona', 'gorras', 'Gorra de Silicona', 5500, 'Todos', 'Ayuda a proteger el pelo del cloro.', 'Gorra flexible de silicona para cubrir el cabello y ayudar a reducir el contacto con el cloro. Disponible en tallas para niño y adulto.', 'Dura más que la de tela y protege mejor el pelo del cloro.', array['Lila', 'Celeste', 'Negro', 'Blanco']::text[], array['Niño', 'Adulto']::text[], 'Talla', 'gorra', 'recomendado', array['Material flexible de silicona.', 'Disponible en talla de niño y adulto.', 'Se enjuaga con facilidad después de la clase.']::text[], 4),
  ('gorra-lycra', 'gorras', 'Gorra de Lycra', 3900, 'Niños', 'Cómoda para los más pequeños; no jala el pelo.', 'Gorra suave de lycra, cómoda para los más pequeños y fácil de poner. No jala el pelo al retirarla.', null, array['Celeste', 'Rosa', 'Amarillo']::text[], array['Niño', 'Adulto']::text[], 'Talla', 'gorra', null, array['Tela suave que no jala el pelo.', 'Fácil de poner y quitar.', 'Disponible en talla de niño y adulto.']::text[], 5),
  ('tabla', 'entrenamiento', 'Tabla de Nado', 8500, 'Todos', 'Practique la patada con buen apoyo.', 'Tabla de nado liviana que brinda apoyo para practicar la patada y mejorar la posición de las piernas. La Junior es para menores de 10 años.', 'La base para aprender a patear bien. La Junior es para menores de 10 años.', array['Celeste', 'Lila', 'Amarillo']::text[], array['Junior', 'Adulto']::text[], 'Tamaño', 'tabla', 'recomendado', array['Ayuda a trabajar la patada por separado.', 'Tamaño Junior recomendado para menores de 10 años.', 'Espuma liviana fácil de sujetar.']::text[], 6),
  ('pull-buoy', 'entrenamiento', 'Pull Buoy', 7500, 'Adultos', 'Aísle las piernas y practique la brazada.', 'Flotador para colocar entre las piernas y concentrarse en la técnica de brazos y la posición del cuerpo.', null, array['Lila', 'Celeste']::text[], null, 'Talla', 'pullbuoy', null, array['Diseñado para entrenar la brazada.', 'Se coloca entre los muslos.', 'Liviano y fácil de llevar.']::text[], 7),
  ('manoplas', 'entrenamiento', 'Manoplas de Entrenamiento', 8900, 'Adultos', 'Sienta mejor el agarre del agua.', 'Manoplas para trabajar el agarre y la fuerza de la brazada. Elegí una talla cómoda para tu mano.', null, array['Celeste', 'Lila', 'Negro']::text[], array['S', 'M', 'L']::text[], 'Talla', 'manoplas', null, array['Para practicar el agarre del agua.', 'Correa ajustable para sujetarlas a la mano.', 'Tallas S, M y L.']::text[], 8),
  ('aletas', 'entrenamiento', 'Aletas Cortas de Silicona', 18500, 'Todos', 'Impulso y control para tus entrenamientos.', 'Aletas cortas de silicona para trabajar la patada con control en piscina. Seleccioná tu talla de pie.', null, array['Celeste', 'Lila', 'Amarillo']::text[], array['32-33', '34-35', '36-37', '38-39', '40-41', '42-43']::text[], 'Talla de pie', 'aletas', 'ultimas', array['Diseño corto para entrenamientos en piscina.', 'Silicona flexible y cómoda.', 'Elegí la talla según tu número de calzado.']::text[], 9),
  ('traje-dama', 'trajes', 'Traje Enterizo Dama', 24900, 'Adultos', 'Tela resistente al cloro para entrenar.', 'Traje enterizo de natación con tela resistente al cloro y calce pensado para acompañar tus entrenamientos.', null, array['Negro/Lila', 'Azul/Celeste', 'Coral/Negro']::text[], array['XS', 'S', 'M', 'L', 'XL']::text[], 'Talla', 'traje', 'recomendado', array['Tela resistente al cloro.', 'Diseño enterizo para nadar con comodidad.', 'Cambio de talla sujeto a condiciones de higiene.']::text[], 10),
  ('jammer', 'trajes', 'Jammer Caballero', 19900, 'Adultos', 'Calce firme para tus sesiones de piscina.', 'Jammer de natación de largo a la rodilla, pensado para un calce firme y cómodo durante el entrenamiento.', null, array['Negro/Celeste', 'Azul/Lila']::text[], array['28', '30', '32', '34', '36']::text[], 'Talla', 'jammer', null, array['Largo a la rodilla para entrenar.', 'Cintura elástica con cordón ajustable.', 'Tallas numéricas del 28 al 36.']::text[], 11),
  ('traje-nina', 'trajes', 'Traje de Baño Niña', 15900, 'Niños', 'Enterizo con protección UV 50+.', 'Traje de baño enterizo para niña con protección UV 50+, listo para clases y juegos en el agua.', null, array['Lila/Celeste', 'Rosa/Lila', 'Turquesa/Amarillo']::text[], array['4', '6', '8', '10', '12', '14']::text[], 'Talla', 'trajenina', null, array['Protección UV 50+.', 'Diseño enterizo cómodo para nadar.', 'Tallas infantiles del 4 al 14.']::text[], 12),
  ('boxer-nino', 'trajes', 'Bóxer de Natación Niño', 12900, 'Niños', 'Bóxer cómodo para la clase de natación.', 'Bóxer de natación para niño con cintura ajustable y calce cómodo para moverse con libertad en la piscina.', null, array['Celeste/Negro', 'Azul/Amarillo', 'Lila/Negro']::text[], array['4', '6', '8', '10', '12', '14']::text[], 'Talla', 'boxer', null, array['Cintura elástica con ajuste.', 'Diseño cómodo para clases de natación.', 'Tallas infantiles del 4 al 14.']::text[], 13),
  ('tapones', 'accesorios', 'Tapones de Silicona', 2500, 'Todos', 'Incluye estuche para guardarlos.', 'Tapones de silicona reutilizables para ayudar a evitar que entre agua en los oídos. Incluye estuche.', null, array['Celeste', 'Lila', 'Amarillo']::text[], null, 'Talla', 'tapones', null, array['Silicona suave y reutilizable.', 'Incluye estuche de guardado.', 'Enjuague y deje secar después de usar.']::text[], 14),
  ('toalla', 'accesorios', 'Toalla de Microfibra', 9500, 'Todos', 'Secado rápido, 70 x 140 cm.', 'Toalla de microfibra liviana y compacta, de secado rápido. Medida: 70 x 140 cm.', null, array['Lila', 'Celeste', 'Turquesa']::text[], null, 'Talla', 'toalla', null, array['Medida de 70 x 140 cm.', 'Secado rápido después de nadar.', 'Liviana para llevar a clase.']::text[], 15),
  ('bolso', 'accesorios', 'Bolso de Malla', 7900, 'Todos', 'Llevá tu equipo mojado con ventilación.', 'Bolso de malla para transportar el equipo de natación mojado y dejar que circule el aire.', null, array['Negro', 'Lila', 'Celeste']::text[], null, 'Talla', 'bolso', null, array['Malla ventilada para guardar equipo mojado.', 'Cordón ajustable para cerrar.', 'Cómodo para llevar a tus clases.']::text[], 16),
  ('kit', 'accesorios', 'Kit Primera Clase', 12900, 'Todos', 'Gafas Junior, gorra de silicona y tapones.', 'Todo lo esencial para empezar: gafas Junior, gorra de silicona y tapones. Por separado cuesta ₡14.500, así que con el kit ahorra ₡1.600.', 'Es lo que pido para la primera clase. Con esto ya podés empezar.', array['Lila', 'Celeste', 'Rosa']::text[], array['Niño', 'Adulto']::text[], 'Talla de gorra', 'kit', 'recomendado', array['Incluye gafas Junior, gorra de silicona y tapones.', 'El kit cuesta ₡12.900; por separado suma ₡14.500.', 'Una opción práctica para tu primera clase.']::text[], 17)
on conflict (id) do nothing;

-- Paquetes mensuales (fuente de verdad del recomendador) --------------------------

create table if not exists public.packages (
  id serial primary key,
  clases int not null check (clases > 0),
  personas int not null check (personas between 1 and 3),
  precio int not null check (precio >= 0),
  activo boolean not null default true,
  unique (clases, personas)
);
grant select on public.packages to anon, authenticated;
grant all on public.packages to service_role;
grant usage, select on sequence public.packages_id_seq to service_role;
alter table public.packages enable row level security;
drop policy if exists "paquetes publicos" on public.packages;
create policy "paquetes publicos" on public.packages for select to anon, authenticated using (activo);
drop policy if exists "profe edita paquetes" on public.packages;
create policy "profe edita paquetes" on public.packages for all to authenticated
  using (public.is_profe()) with check (public.is_profe());
grant insert, update, delete on public.packages to authenticated;
grant usage, select on sequence public.packages_id_seq to authenticated;

insert into public.packages (clases, personas, precio) values
  (4,1,37000),(4,2,58000),(4,3,75000),
  (8,1,72000),(8,2,110000),(8,3,145000),
  (12,1,98000),(12,2,145000),(12,3,190000)
on conflict (clases, personas) do nothing;

-- Solicitudes del recomendador de paquetes (solo las ve la profe) ------------------

create table if not exists public.recommendation_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  nombre text, contacto text,
  objetivos text not null, experiencia text not null, disponibilidad text not null,
  para_quien text, personas int,
  paquete_clases int, paquete_personas int, paquete_precio int, tipo_clase text, razon text
);
grant all on public.recommendation_requests to service_role;
grant select, delete on public.recommendation_requests to authenticated;
alter table public.recommendation_requests enable row level security;
drop policy if exists "profe ve solicitudes" on public.recommendation_requests;
create policy "profe ve solicitudes" on public.recommendation_requests for select to authenticated using (public.is_profe());
drop policy if exists "profe borra solicitudes" on public.recommendation_requests;
create policy "profe borra solicitudes" on public.recommendation_requests for delete to authenticated using (public.is_profe());

-- Mensajes de la página de contacto (cualquiera envía, solo la profe lee) -----------

create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  nombre text not null check (char_length(nombre) between 1 and 100),
  telefono text check (char_length(telefono) <= 30),
  correo text check (char_length(correo) <= 255),
  motivo text check (char_length(motivo) <= 60),
  mensaje text not null check (char_length(mensaje) between 1 and 1500),
  leido boolean not null default false
);
grant insert on public.contact_messages to anon, authenticated;
grant select, update, delete on public.contact_messages to authenticated;
grant all on public.contact_messages to service_role;
alter table public.contact_messages enable row level security;
drop policy if exists "enviar mensaje" on public.contact_messages;
create policy "enviar mensaje" on public.contact_messages for insert to anon, authenticated with check (leido = false);
drop policy if exists "profe lee mensajes" on public.contact_messages;
create policy "profe lee mensajes" on public.contact_messages for select to authenticated using (public.is_profe());
drop policy if exists "profe marca mensajes" on public.contact_messages;
create policy "profe marca mensajes" on public.contact_messages for update to authenticated using (public.is_profe()) with check (public.is_profe());
drop policy if exists "profe borra mensajes" on public.contact_messages;
create policy "profe borra mensajes" on public.contact_messages for delete to authenticated using (public.is_profe());
