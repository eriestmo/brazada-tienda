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
    raise exception 'Esa clase ya empezó. Elija otro horario.';
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
    raise exception 'No se encontró el alumno en su cuenta.';
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
    raise exception 'Faltan menos de 12 horas para la clase. Escríbale a la profe por WhatsApp.';
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
    raise exception 'Faltan menos de 12 horas para la clase. Escríbale a la profe por WhatsApp.';
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
    raise exception 'Primero cancele las clases futuras de este alumno.';
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

-- Permisos de funciones ------------------------------------------------------

revoke execute on function
  public.handle_new_user(), public.check_slot(text, timestamptz),
  public.book_class(uuid, text, timestamptz), public.reschedule_booking(uuid, timestamptz),
  public.cancel_booking(uuid), public.remove_student(uuid), public.ensure_my_payment(),
  public.report_payment(uuid), public.confirm_payment(uuid), public.admin_cancel_booking(uuid)
  from public, anon;
revoke execute on function public.handle_new_user(), public.check_slot(text, timestamptz) from authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;
grant execute on function
  public.book_class(uuid, text, timestamptz), public.reschedule_booking(uuid, timestamptz),
  public.cancel_booking(uuid), public.remove_student(uuid), public.ensure_my_payment(),
  public.report_payment(uuid), public.confirm_payment(uuid), public.admin_cancel_booking(uuid)
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
