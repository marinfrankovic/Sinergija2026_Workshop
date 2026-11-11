#!/bin/sh
# Starts the API. The Application Insights agent is attached only when a
# connection string is present (i.e. in Azure), so local runs stay quiet.
AGENT=""
if [ -n "$APPLICATIONINSIGHTS_CONNECTION_STRING" ]; then
  AGENT="-javaagent:/app/applicationinsights-agent.jar"
fi
echo "Starting ledgerly-api with JAVA_OPTS='$JAVA_OPTS' profiles='${SPRING_PROFILES_ACTIVE:-default}'"
exec java $AGENT $JAVA_OPTS -jar /app/app.jar
