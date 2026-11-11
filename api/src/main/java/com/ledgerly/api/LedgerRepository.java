package com.ledgerly.api;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** Plain JdbcTemplate data access – no ORM, just like the original app. */
@Repository
public class LedgerRepository {

    private final JdbcTemplate jdbc;

    public LedgerRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> findPortfolios() {
        return jdbc.queryForList(
            "SELECT id, code, name, owner, currency FROM portfolios ORDER BY name");
    }

    public List<Map<String, Object>> findPositions(long portfolioId) {
        return jdbc.queryForList(
            "SELECT i.symbol, i.name AS instrument, p.quantity, p.avg_cost, "
          + "       ROUND(p.quantity * i.last_price, 2) AS market_value "
          + "FROM positions p JOIN instruments i ON i.id = p.instrument_id "
          + "WHERE p.portfolio_id = ? ORDER BY market_value DESC", portfolioId);
    }

    /*
     * Legacy report query. Filters on transactions.booking_date, which has NO index,
     * and is executed once per portfolio (N+1) -> every call is a full table scan.
     * Fix (block 5): CREATE INDEX ix_transactions_booking_date ON transactions(booking_date);
     */
    public List<Map<String, Object>> monthlyByInstrument(long portfolioId, LocalDate from, LocalDate to) {
        return jdbc.queryForList(
            "SELECT i.symbol, t.type, COUNT(*) AS cnt, ROUND(SUM(t.quantity * t.price), 2) AS amount "
          + "FROM transactions t JOIN instruments i ON i.id = t.instrument_id "
          + "WHERE t.portfolio_id = ? AND t.booking_date >= ? AND t.booking_date < ? "
          + "GROUP BY i.symbol, t.type ORDER BY i.symbol, t.type",
            portfolioId, from, to);
    }

    public Map<String, Object> monthlyTotals(long portfolioId, LocalDate from, LocalDate to) {
        return jdbc.queryForMap(
            "SELECT COUNT(*) AS cnt, "
          + "       COALESCE(ROUND(SUM(CASE WHEN type = 'BUY'  THEN quantity * price ELSE 0 END), 2), 0) AS buys, "
          + "       COALESCE(ROUND(SUM(CASE WHEN type = 'SELL' THEN quantity * price ELSE 0 END), 2), 0) AS sells "
          + "FROM transactions WHERE portfolio_id = ? AND booking_date >= ? AND booking_date < ?",
            portfolioId, from, to);
    }

    public void ping() {
        jdbc.queryForObject("SELECT 1", Integer.class);
    }
}
