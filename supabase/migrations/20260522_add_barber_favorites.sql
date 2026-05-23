-- Saved barbers list — a customer can save multiple barbers (separate from the 1-vote system)
create table if not exists barber_favorites (
  id         uuid        default gen_random_uuid() primary key,
  user_id    uuid        not null references users(id)   on delete cascade,
  barber_id  uuid        not null references barbers(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, barber_id)
);
create index if not exists barber_favorites_user_id_idx   on barber_favorites(user_id);
create index if not exists barber_favorites_barber_id_idx on barber_favorites(barber_id);
