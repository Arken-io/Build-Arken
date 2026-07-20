-- BuildArken: profiles table + role system + auto-create-on-signup trigger
-- Run this once in Supabase Dashboard → SQL Editor.
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / OR REPLACE / DROP IF EXISTS).

-- 1. Table -------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid references auth.users(id) on delete cascade primary key,
  email       text,
  full_name   text,
  avatar_url  text,
  role        text not null default 'user' check (role in ('user', 'creator', 'admin')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2. Row Level Security --------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- 3. Auto-create a profile row on first sign-in ------------------------
-- Fires once per new auth.users row (i.e. once per person, regardless of
-- which provider — Google, GitHub, or email — they first sign in with).
-- "Reuse existing profile if user already exists" is handled by the
-- ON CONFLICT DO NOTHING below: if a profile row already exists for that
-- id, this is a no-op and nothing is overwritten.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Keep updated_at current on manual edits ----------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

-- Promoting someone to creator/admin is a manual step for now, e.g.:
--   update public.profiles set role = 'creator' where email = 'someone@example.com';
