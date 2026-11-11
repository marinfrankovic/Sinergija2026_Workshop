package com.ledgerly.api;

import java.time.Duration;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/** Cache-aside for the portfolio list. Redis problems never break the request – we fall back to MySQL. */
@Component
public class PortfolioCache {

    private static final Logger log = LoggerFactory.getLogger(PortfolioCache.class);
    private static final String KEY = "ledgerly:portfolios";

    private final StringRedisTemplate redis;
    private final ObjectMapper mapper;
    private final LedgerRepository repo;
    private final Duration ttl;

    public PortfolioCache(StringRedisTemplate redis, ObjectMapper mapper, LedgerRepository repo,
                          @Value("${ledgerly.cache-ttl-seconds:300}") long ttlSeconds) {
        this.redis = redis;
        this.mapper = mapper;
        this.repo = repo;
        this.ttl = Duration.ofSeconds(ttlSeconds);
    }

    public List<Map<String, Object>> portfolios() {
        try {
            String cached = redis.opsForValue().get(KEY);
            if (cached != null) {
                return mapper.readValue(cached, new TypeReference<List<Map<String, Object>>>() { });
            }
        } catch (Exception e) {
            log.warn("Redis read failed, falling back to MySQL: {}", e.getMessage());
        }
        List<Map<String, Object>> fresh = repo.findPortfolios();
        try {
            redis.opsForValue().set(KEY, mapper.writeValueAsString(fresh), ttl);
        } catch (Exception e) {
            log.warn("Redis write failed: {}", e.getMessage());
        }
        return fresh;
    }

    public boolean ping() {
        try {
            String pong = redis.execute((org.springframework.data.redis.core.RedisCallback<String>) c -> c.ping());
            return "PONG".equalsIgnoreCase(pong);
        } catch (Exception e) {
            return false;
        }
    }
}
