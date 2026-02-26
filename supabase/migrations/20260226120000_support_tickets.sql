-- Support tickets between assessorias and the platform
create table if not exists public.support_tickets (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.coaching_groups(id) on delete cascade,
  subject     text not null check (char_length(subject) between 1 and 200),
  status      text not null default 'open' check (status in ('open','answered','closed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index idx_support_tickets_group on public.support_tickets(group_id);
create index idx_support_tickets_status on public.support_tickets(status);

create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.support_tickets(id) on delete cascade,
  sender_id   uuid not null,
  sender_role text not null check (sender_role in ('staff','platform')),
  body        text not null check (char_length(body) between 1 and 5000),
  created_at  timestamptz not null default now()
);

create index idx_support_messages_ticket on public.support_messages(ticket_id);

-- Auto-update updated_at on ticket when a message is inserted
create or replace function public.fn_support_ticket_touch()
returns trigger language plpgsql security definer as $$
begin
  update public.support_tickets set updated_at = now() where id = new.ticket_id;
  return new;
end;
$$;

create trigger trg_support_message_touch
  after insert on public.support_messages
  for each row execute function public.fn_support_ticket_touch();

-- RLS
alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;

-- Staff of the assessoria can read their own tickets
create policy "staff_read_own_tickets" on public.support_tickets
  for select using (
    exists (
      select 1 from public.coaching_members cm
      where cm.group_id = support_tickets.group_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','professor','assistente')
    )
  );

-- Staff can insert tickets for their assessoria
create policy "staff_insert_tickets" on public.support_tickets
  for insert with check (
    exists (
      select 1 from public.coaching_members cm
      where cm.group_id = support_tickets.group_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','professor','assistente')
    )
  );

-- Platform admin can read all tickets
create policy "platform_read_all_tickets" on public.support_tickets
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.platform_role = 'admin'
    )
  );

-- Platform admin can update any ticket (status changes)
create policy "platform_update_tickets" on public.support_tickets
  for update using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.platform_role = 'admin'
    )
  );

-- Staff can also update their own tickets (to reopen)
create policy "staff_update_own_tickets" on public.support_tickets
  for update using (
    exists (
      select 1 from public.coaching_members cm
      where cm.group_id = support_tickets.group_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','professor','assistente')
    )
  );

-- Messages: staff reads messages of their tickets
create policy "staff_read_own_messages" on public.support_messages
  for select using (
    exists (
      select 1 from public.support_tickets t
      join public.coaching_members cm on cm.group_id = t.group_id
      where t.id = support_messages.ticket_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','professor','assistente')
    )
  );

-- Staff inserts messages on their tickets
create policy "staff_insert_messages" on public.support_messages
  for insert with check (
    sender_role = 'staff'
    and sender_id = auth.uid()
    and exists (
      select 1 from public.support_tickets t
      join public.coaching_members cm on cm.group_id = t.group_id
      where t.id = support_messages.ticket_id
        and cm.user_id = auth.uid()
        and cm.role in ('admin_master','professor','assistente')
    )
  );

-- Platform admin reads all messages
create policy "platform_read_all_messages" on public.support_messages
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.platform_role = 'admin'
    )
  );

-- Platform admin inserts messages
create policy "platform_insert_messages" on public.support_messages
  for insert with check (
    sender_role = 'platform'
    and sender_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.platform_role = 'admin'
    )
  );
