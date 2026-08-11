FROM pandoc/core:3.10.0.0-alpine AS builder

WORKDIR /source

COPY docs/PRIVACY_POLICY.md ./PRIVACY_POLICY.md
COPY deploy/privacy/template.html ./template.html

RUN mkdir -p /output && \
    pandoc PRIVACY_POLICY.md \
      --from=gfm \
      --to=html5 \
      --standalone \
      --template=template.html \
      --metadata title="BikeGoGo 隐私政策" \
      --output=/output/index.html

FROM nginx:1.28-alpine

COPY deploy/privacy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /output/index.html /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -O - http://127.0.0.1/health | grep -q '^ok$'
