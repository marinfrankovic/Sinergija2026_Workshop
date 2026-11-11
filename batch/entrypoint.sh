#!/bin/sh
# Two modes:
#   default        -> busybox crond in the foreground (Docker Compose "on-prem")
#   RUN_ONCE=true  -> run the report once and exit (Azure Container Apps scheduled job)
# busybox crond does not pass the container environment to jobs, so persist it first.
env | grep -E '^(DB_|REPORT_)' | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/' > /app/env.sh

if [ "${RUN_ONCE:-false}" = "true" ]; then
  exec /app/report.sh
fi
echo "ledgerly-batch: starting crond (schedule: */5 * * * *)"
exec crond -f -l 8
