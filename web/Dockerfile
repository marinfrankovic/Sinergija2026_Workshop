# Ledgerly web tier – static UI + reverse proxy to the API.
FROM nginx:1.25-alpine
# The official nginx image renders /etc/nginx/templates/*.template with envsubst
# at start-up, so the API upstream is configurable:
#   compose        -> http://api:8080
#   Container Apps -> http://ca-ledgerly-api-workshop  (internal ingress, port 80 -> 8080)
ENV API_UPSTREAM=http://api:8080
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
