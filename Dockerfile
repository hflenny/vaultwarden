# Bundle cloudflared into the official vaultwarden image so a single
# container runs both processes. ARM64-compatible on Mac Mini.
FROM cloudflare/cloudflared:latest AS cloudflared

FROM vaultwarden/server:latest

COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared

COPY start.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
