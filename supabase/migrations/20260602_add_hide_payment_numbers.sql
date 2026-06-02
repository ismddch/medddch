alter table barbers
  add column if not exists hide_payment_numbers boolean not null default false;
