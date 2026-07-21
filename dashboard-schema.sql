-- BuildArken: dashboard data — favorites, recently-viewed tools, and the
-- published_tools table backing Creator stats.
-- Run once in Supabase Dashboard → SQL Editor, after profiles.sql.
-- Safe to re-run: every statement is idempotent.

-- 1. Favorites -----------------------------------------------------------
create table if not exists public.user_favorites (
  user_id     uuid references auth.users(id) on delete cascade,
  tool_slug   text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, tool_slug)
);

alter table public.user_favorites enable row level security;

drop policy if exists "Users manage own favorites" on public.user_favorites;
create policy "Users manage own favorites"
  on public.user_favorites for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 2. Recently viewed -------------------------------------------------------
create table if not exists public.user_recent_tools (
  user_id         uuid references auth.users(id) on delete cascade,
  tool_slug       text not null,
  last_viewed_at  timestamptz not null default now(),
  view_count      integer not null default 1,
  primary key (user_id, tool_slug)
);

create index if not exists user_recent_tools_by_user
  on public.user_recent_tools (user_id, last_viewed_at desc);

alter table public.user_recent_tools enable row level security;

drop policy if exists "Users manage own recent tools" on public.user_recent_tools;
create policy "Users manage own recent tools"
  on public.user_recent_tools for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Atomic upsert used by the client on every "Open" click — avoids a
-- read-then-write race and keeps a running view_count per tool.
create or replace function public.log_tool_view(p_slug text)
returns void
language plpgsql
as $$
begin
  insert into public.user_recent_tools (user_id, tool_slug, last_viewed_at, view_count)
  values (auth.uid(), p_slug, now(), 1)
  on conflict (user_id, tool_slug)
  do update set last_viewed_at = now(), view_count = public.user_recent_tools.view_count + 1;
end;
$$;

grant execute on function public.log_tool_view(text) to authenticated;

-- 3. Published tools (backs the Creator dashboard stats now; the actual
--    publish/edit UI is a later phase — this just gives Creators a real
--    table to report zeros against until then). ---------------------------
create table if not exists public.published_tools (
  id           uuid primary key default gen_random_uuid(),
  creator_id   uuid references auth.users(id) on delete cascade not null,
  name         text not null,
  slug         text not null unique,
  description  text,
  url          text,
  status       text not null default 'draft' check (status in ('draft','published','archived')),
  views        integer not null default 0,
  likes        integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.published_tools enable row level security;

drop policy if exists "Anyone can view published tools" on public.published_tools;
create policy "Anyone can view published tools"
  on public.published_tools for select
  using (status = 'published' or auth.uid() = creator_id);

drop policy if exists "Creators manage own tools" on public.published_tools;
create policy "Creators manage own tools"
  on public.published_tools for all
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

drop trigger if exists set_published_tools_updated_at on public.published_tools;
create trigger set_published_tools_updated_at
  before update on public.published_tools
  for each row execute procedure public.set_updated_at(); -- reuses the function from profiles.sql

-- Promoting/demoting creators is currently self-service from the dashboard
-- ("Become a Creator" button just sets role='creator' on your own profile,
-- allowed by the existing "Users can update own profile" policy). If you'd
-- rather gate this behind manual approval later, swap that button for a
-- request row and revoke self-update on the role column specifically.
