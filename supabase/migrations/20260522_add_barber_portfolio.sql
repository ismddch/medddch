-- Work photos gallery for each barber (shown to customers on the details sheet)
create table if not exists barber_portfolio (
  id         uuid        default gen_random_uuid() primary key,
  barber_id  uuid        not null references barbers(id) on delete cascade,
  photo_url  text        not null,
  created_at timestamptz default now()
);
create index if not exists barber_portfolio_barber_id_idx on barber_portfolio(barber_id);
alter table barber_portfolio disable row level security;
