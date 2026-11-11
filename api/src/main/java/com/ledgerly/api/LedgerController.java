package com.ledgerly.api;

import java.net.InetAddress;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class LedgerController {

    private final LedgerRepository repo;
    private final PortfolioCache cache;
    private final ReportService reports;
    private final String version;

    public LedgerController(LedgerRepository repo, PortfolioCache cache, ReportService reports,
                            @Value("${ledgerly.version:1.0.0}") String version) {
        this.repo = repo;
        this.cache = cache;
        this.reports = reports;
        this.version = version;
    }

    /** Always HTTP 200 (used by liveness/readiness probes); dependency state is in the body. */
    @GetMapping("/health")
    public Map<String, Object> health() {
        boolean db;
        try {
            repo.ping();
            db = true;
        } catch (Exception e) {
            db = false;
        }
        boolean redis = cache.ping();
        Map<String, Object> h = new LinkedHashMap<>();
        h.put("status", db && redis ? "UP" : "DEGRADED");
        h.put("db", db ? "UP" : "DOWN");
        h.put("cache", redis ? "UP" : "DOWN");
        h.put("version", version);
        h.put("host", hostName());
        return h;
    }

    @GetMapping("/portfolios")
    public List<Map<String, Object>> portfolios() {
        return cache.portfolios();
    }

    @GetMapping("/portfolios/{id}/positions")
    public List<Map<String, Object>> positions(@PathVariable long id) {
        return repo.findPositions(id);
    }

    @GetMapping("/reports/monthly")
    public Map<String, Object> monthly(@RequestParam int year, @RequestParam int month) {
        return reports.monthly(year, month);
    }

    /** Triggered by the "Run monthly report" button; returns a summary without the detail rows. */
    @PostMapping("/reports/run")
    public Map<String, Object> run(@RequestParam(required = false) Integer year,
                                   @RequestParam(required = false) Integer month) {
        LocalDate prev = LocalDate.now().minusMonths(1);
        Map<String, Object> full = reports.monthly(year != null ? year : prev.getYear(),
                                                   month != null ? month : prev.getMonthValue());
        Map<String, Object> summary = new LinkedHashMap<>(full);
        summary.remove("portfolios");
        summary.put("status", "COMPLETED");
        return summary;
    }

    private static String hostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown";
        }
    }
}
