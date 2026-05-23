-- barber_likes: customers vote for their favourite barber.
-- Each customer (user) can vote for exactly ONE barber at a time.
-- Switching votes first removes the old row, then inserts a new one.

create table if not exists barber_likes (
  id         uuid        default gen_random_uuid() primary key,
  barber_id  uuid        not null references barbers(id) on delete cascade,
  user_id    uuid        not null references users(id)   on delete cascade,
  created_at timestamptz default now(),
  unique(user_id)   -- one active vote per customer
);

create index if not exists barber_likes_barber_id_idx on barber_likes(barber_id);
create index if not exists barber_likes_user_id_idx   on barber_likes(user_id);
