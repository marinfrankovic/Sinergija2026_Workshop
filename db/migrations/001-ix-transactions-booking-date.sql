-- Fix for fault 3 (slow monthly report). Online DDL on MySQL 8.0 (InnoDB, ALGORITHM=INPLACE).
CREATE INDEX ix_transactions_booking_date ON transactions (booking_date);
