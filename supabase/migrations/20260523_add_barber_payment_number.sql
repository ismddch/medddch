-- Payment number the barber sets so customers know where to send money
alter table barbers add column if not exists payment_number text;
