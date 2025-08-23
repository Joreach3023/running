-- Supabase schema for RunPacer Boss Run mode

-- Users and clans -----------------------------------------------------------
create table if not exists app_user (
    id uuid primary key default gen_random_uuid(),
    name text not null
);

create table if not exists clan (
    id uuid primary key default gen_random_uuid(),
    name text not null
);

create table if not exists clan_member (
    clan_id uuid references clan(id) on delete cascade,
    user_id uuid references app_user(id) on delete cascade,
    primary key (clan_id, user_id)
);

-- Runs and boss contributions ----------------------------------------------
create table if not exists run (
    id uuid primary key,
    user_id uuid references app_user(id) on delete cascade,
    km numeric not null,
    seconds integer not null,
    source text,
    created_at timestamptz default now()
);

create table if not exists boss_event (
    id uuid primary key default gen_random_uuid(),
    name text,
    hp_total numeric not null,
    start_time timestamptz not null,
    end_time timestamptz not null,
    status text not null check (status in ('scheduled','active','defeated','expired')),
    created_at timestamptz default now()
);

create table if not exists boss_contribution (
    id uuid primary key default gen_random_uuid(),
    boss_id uuid references boss_event(id) on delete cascade,
    run_id uuid references run(id) on delete cascade,
    user_id uuid references app_user(id) on delete cascade,
    clan_id uuid references clan(id),
    km numeric not null,
    seconds integer not null,
    source text,
    created_at timestamptz default now(),
    unique (boss_id, run_id, user_id)
);

-- Badges -------------------------------------------------------------------
create table if not exists badge (
    id uuid primary key default gen_random_uuid(),
    slug text unique,
    name text not null
);

create table if not exists user_badge (
    user_id uuid references app_user(id) on delete cascade,
    badge_id uuid references badge(id) on delete cascade,
    created_at timestamptz default now(),
    primary key (user_id, badge_id)
);

-- Materialized views -------------------------------------------------------
create materialized view if not exists boss_hp as
select
    b.id as boss_id,
    b.hp_total - coalesce(sum(c.km),0) as hp_remaining
from boss_event b
left join boss_contribution c on c.boss_id = b.id
group by b.id;

create materialized view if not exists clan_day as
select
    c.clan_id,
    date_trunc('day', c.created_at) as day,
    sum(c.km) as km
from boss_contribution c
group by c.clan_id, date_trunc('day', c.created_at);

-- Row level security -------------------------------------------------------
alter table run enable row level security;
alter table boss_contribution enable row level security;

create policy "own runs" on run
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "own contributions" on boss_contribution
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "clan member contributions" on boss_contribution
    for select using (
        exists (
            select 1 from clan_member cm
            where cm.clan_id = boss_contribution.clan_id
              and cm.user_id = auth.uid()
        )
    );

refresh materialized view boss_hp;
refresh materialized view clan_day;
