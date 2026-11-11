-- Ledgerly seed data – MySQL 5.7 compatible (no CTEs, no window functions).
-- Generates 200,000 deterministic transactions with a digits cross join.
USE ledgerly;

INSERT INTO portfolios (code, name, owner, currency) VALUES
 ('PF-ADR-01','Adriatic Growth','Treasury Zagreb','EUR'),
 ('PF-ADR-02','Adriatic Income','Treasury Zagreb','EUR'),
 ('PF-DAN-01','Danube Balanced','Wealth Desk','EUR'),
 ('PF-DAN-02','Danube Conservative','Wealth Desk','EUR'),
 ('PF-NOR-01','Nordic Equity','Pension Fund','EUR'),
 ('PF-NOR-02','Nordic Bonds','Pension Fund','EUR'),
 ('PF-GLB-01','Global Tech','Strategic Investments','USD'),
 ('PF-GLB-02','Global Dividend','Strategic Investments','USD'),
 ('PF-ALP-01','Alpine Reserve','Corporate Cash','CHF'),
 ('PF-ALP-02','Alpine Opportunities','Corporate Cash','CHF'),
 ('PF-SUS-01','Sustainable Future','ESG Office','EUR'),
 ('PF-SUS-02','Green Infrastructure','ESG Office','EUR');

INSERT INTO instruments (symbol, name, asset_class, currency, last_price) VALUES
 ('ADRE','Adriatic Energy d.d.','EQUITY','EUR',41.20),
 ('ADRT','Adriatic Telecom d.d.','EQUITY','EUR',23.75),
 ('DNBK','Danube Bank AG','EQUITY','EUR',58.10),
 ('DNLG','Danube Logistics SE','EQUITY','EUR',17.45),
 ('NRDP','Nordic Paper ASA','EQUITY','EUR',9.80),
 ('NRDW','Nordic Wind AB','EQUITY','EUR',112.30),
 ('ALPF','Alpine Foods AG','EQUITY','CHF',76.40),
 ('ALPR','Alpine Rail AG','EQUITY','CHF',134.90),
 ('CLDX','CloudNimbus Inc.','EQUITY','USD',245.60),
 ('CHPX','ChipForge Corp.','EQUITY','USD',88.15),
 ('DATQ','DataQuarry Inc.','EQUITY','USD',61.70),
 ('ROBO','Robotica Holdings','EQUITY','USD',33.05),
 ('MEDX','MediAxis Plc','EQUITY','EUR',47.90),
 ('PHRM','PharmaNova SE','EQUITY','EUR',152.25),
 ('SOLR','SolarRidge SpA','EQUITY','EUR',12.60),
 ('HYDR','HydroLink d.o.o.','EQUITY','EUR',21.35),
 ('AGRI','AgriPannon Zrt.','EQUITY','EUR',8.95),
 ('SHIP','Kvarner Shipping d.d.','EQUITY','EUR',29.40),
 ('TOUR','Dalmatia Tourism d.d.','EQUITY','EUR',36.80),
 ('INSR','Sava Mutual Insurance','EQUITY','EUR',64.10),
 ('HRGB30','Croatia Gov Bond 2030','BOND','EUR',98.70),
 ('DEGB28','Germany Bund 2028','BOND','EUR',101.15),
 ('ATGB32','Austria Gov Bond 2032','BOND','EUR',96.40),
 ('USTB29','US Treasury 2029','BOND','USD',97.85),
 ('CHGB31','Swiss Confed 2031','BOND','CHF',103.20),
 ('EUCB27','EuroCorp IG 2027','BOND','EUR',99.10),
 ('GRNB33','Green Bond EU 2033','BOND','EUR',94.60),
 ('MMEUR','Euro Money Market Fund','FUND','EUR',100.05),
 ('ETFWLD','World Equity ETF','FUND','USD',87.30),
 ('ETFESG','ESG Leaders ETF','FUND','EUR',54.45);

-- helper table for the number generator (dropped at the end)
CREATE TABLE digits (d TINYINT UNSIGNED NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- n = 0..199999 ; portfolio = n % 12, instrument = (n DIV 12) % 30, date spread over 2024-01-01 .. 2025-12-31
INSERT INTO transactions (portfolio_id, instrument_id, type, quantity, price, booking_date)
SELECT 1 + (seq.n % 12),
       1 + ((seq.n DIV 12) % 30),
       IF(seq.n % 5 = 0, 'SELL', 'BUY'),
       1 + (seq.n % 50),
       ROUND(5 + ((seq.n * 13) % 2500) / 10, 2),
       DATE_ADD('2024-01-01', INTERVAL (seq.n % 731) DAY)
FROM (
  SELECT a.d + b.d * 10 + c.d * 100 + e.d * 1000 + f.d * 10000 + g.d * 100000 AS n
  FROM digits a
  CROSS JOIN digits b
  CROSS JOIN digits c
  CROSS JOIN digits e
  CROSS JOIN digits f
  CROSS JOIN digits g
) seq
WHERE seq.n < 200000;

-- positions derived from the ledger
INSERT INTO positions (portfolio_id, instrument_id, quantity, avg_cost)
SELECT portfolio_id,
       instrument_id,
       SUM(CASE WHEN type = 'BUY' THEN quantity ELSE -quantity END),
       ROUND(SUM(CASE WHEN type = 'BUY' THEN quantity * price ELSE 0 END)
             / NULLIF(SUM(CASE WHEN type = 'BUY' THEN quantity ELSE 0 END), 0), 2)
FROM transactions
GROUP BY portfolio_id, instrument_id;

DROP TABLE digits;
