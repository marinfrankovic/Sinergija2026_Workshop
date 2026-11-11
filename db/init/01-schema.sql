-- Ledgerly schema – MySQL 5.7 (legacy).
-- Executed automatically by the mysql image on first start (docker-entrypoint-initdb.d).
-- Legacy smells kept on purpose for the workshop:
--   * DEFAULT CHARSET=utf8 (= utf8mb3, deprecated in 8.0)
--   * no foreign keys / no secondary index on transactions (portfolio_id, booking_date)
CREATE DATABASE IF NOT EXISTS ledgerly DEFAULT CHARACTER SET utf8;
USE ledgerly;

CREATE TABLE portfolios (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  code       VARCHAR(16)  NOT NULL,
  name       VARCHAR(100) NOT NULL,
  owner      VARCHAR(100) NOT NULL,
  currency   CHAR(3)      NOT NULL DEFAULT 'EUR',
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY ux_portfolios_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE instruments (
  id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  symbol      VARCHAR(12)   NOT NULL,
  name        VARCHAR(100)  NOT NULL,
  asset_class VARCHAR(20)   NOT NULL,
  currency    CHAR(3)       NOT NULL DEFAULT 'EUR',
  last_price  DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY ux_instruments_symbol (symbol)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE positions (
  id            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  portfolio_id  INT UNSIGNED  NOT NULL,
  instrument_id INT UNSIGNED  NOT NULL,
  quantity      DECIMAL(14,2) NOT NULL,
  avg_cost      DECIMAL(12,2) NOT NULL,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY ux_positions (portfolio_id, instrument_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ~200k rows. NOTE: no index on booking_date (or portfolio_id) -> the monthly
-- report does full table scans. Fixed in block 5 (db/migrations/001-ix-transactions-booking-date.sql).
CREATE TABLE transactions (
  id            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  portfolio_id  INT UNSIGNED  NOT NULL,
  instrument_id INT UNSIGNED  NOT NULL,
  type          VARCHAR(4)    NOT NULL,          -- BUY / SELL
  quantity      DECIMAL(14,2) NOT NULL,
  price         DECIMAL(12,2) NOT NULL,
  booking_date  DATE          NOT NULL,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
