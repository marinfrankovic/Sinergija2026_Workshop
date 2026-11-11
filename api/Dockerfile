# Ledgerly API – multi-stage build (legacy Java 11 runtime).
FROM maven:3.9-eclipse-temurin-11 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
RUN mvn -B -q -DskipTests package

FROM eclipse-temurin:11-jre
WORKDIR /app
COPY --from=build /src/target/ledgerly-api.jar /app/app.jar
COPY --from=build /src/target/agent/applicationinsights-agent.jar /app/applicationinsights-agent.jar
COPY entrypoint.sh /app/entrypoint.sh
RUN sed -i 's/\r$//' /app/entrypoint.sh && chmod +x /app/entrypoint.sh
# legacy smell: heap hard-coded for a VM that no longer exists.
# compose limits this container to 1g (mem_limit) -> -Xmx2g can never be honoured.
ENV JAVA_OPTS="-Xms1g -Xmx2g"
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
