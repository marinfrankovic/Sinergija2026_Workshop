#!/bin/sh
# Writes positions-<timestamp>.csv to /reports.
# legacy smell: errors are swallowed (|| true) and the exit code is always 0.
[ -f /app/env.sh ] && . /app/env.sh

TS=$(date +%Y%m%d-%H%M%S)
OUT="${REPORT_DIR:-/reports}/positions-$TS.csv"
SSL_OPT=""
# Azure Database for MySQL requires TLS
[ "${DB_SSL:-false}" = "true" ] && SSL_OPT="--ssl"

MYSQL_PWD="$DB_PASSWORD" mysql $SSL_OPT -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "$DB_USER" "$DB_NAME" --batch -e "
  SELECT p.code AS portfolio, i.symbol, pos.quantity, pos.avg_cost,
         ROUND(pos.quantity * i.last_price, 2) AS market_value
  FROM positions pos
  JOIN portfolios  p ON p.id = pos.portfolio_id
  JOIN instruments i ON i.id = pos.instrument_id
  ORDER BY p.code, i.symbol" | tr '\t' ',' > "$OUT" || true

echo "ledgerly-batch: wrote $OUT ($(wc -l < "$OUT" 2>/dev/null || echo 0) lines)"
exit 0
