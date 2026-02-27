# syntax=docker/dockerfile:1

FROM --platform=$TARGETPLATFORM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659
LABEL org.opencontainers.image.authors="honeok <i@honeok.com>"
ARG TARGETARCH TARGETVARIANT
WORKDIR /app
COPY --chmod=755 maxmind-$TARGETARCH$TARGETVARIANT ./maxmind
RUN set -ex \
    && apk add --no-cache --update curl tzdata
ENV TZ=Asia/Shanghai
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD curl -Ls http://127.0.0.1:8080 || exit 1
ENTRYPOINT ["./maxmind"]
