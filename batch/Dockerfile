# Ledgerly batch – nightly-ish CSV report (legacy cron container).
FROM alpine:3.19
# "mysql-client" is an alias for the MariaDB client on Alpine
RUN apk add --no-cache mysql-client tzdata
WORKDIR /app
COPY report.sh entrypoint.sh crontab /app/
RUN sed -i 's/\r$//' /app/*.sh /app/crontab \
 && chmod +x /app/*.sh \
 && crontab /app/crontab \
 && mkdir -p /reports
VOLUME ["/reports"]
ENTRYPOINT ["/app/entrypoint.sh"]
