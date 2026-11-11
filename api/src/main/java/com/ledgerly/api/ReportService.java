package com.ledgerly.api;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class ReportService {

    private static final Logger log = LoggerFactory.getLogger(ReportService.class);
    private final LedgerRepository repo;

    public ReportService(LedgerRepository repo) {
        this.repo = repo;
    }

    public Map<String, Object> monthly(int year, int month) {
        long t0 = System.currentTimeMillis();
        LocalDate from = LocalDate.of(year, month, 1);
        LocalDate to = from.plusMonths(1);

        List<Map<String, Object>> rows = new ArrayList<>();
        long txCount = 0;
        // legacy N+1: two un-indexed scans per portfolio
        for (Map<String, Object> p : repo.findPortfolios()) {
            long id = ((Number) p.get("id")).longValue();
            Map<String, Object> totals = repo.monthlyTotals(id, from, to);
            txCount += ((Number) totals.get("cnt")).longValue();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("portfolioId", id);
            row.put("code", p.get("code"));
            row.put("totals", totals);
            row.put("byInstrument", repo.monthlyByInstrument(id, from, to));
            rows.add(row);
        }

        long duration = System.currentTimeMillis() - t0;
        if (duration > 2000) {
            log.warn("SLOW monthly report {}-{} took {} ms ({} portfolios)", year, month, duration, rows.size());
        } else {
            log.info("Monthly report {}-{} took {} ms", year, month, duration);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("period", String.format("%04d-%02d", year, month));
        result.put("durationMs", duration);
        result.put("portfolioCount", rows.size());
        result.put("transactionCount", txCount);
        result.put("portfolios", rows);
        return result;
    }
}
