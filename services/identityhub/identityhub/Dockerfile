FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    libmicrohttpd12 \
    libjansson4 \
    libssl1.1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY libhub_auth.so \
     libhub_search.so \
     libhub_resolve.so \
     libhub_protocol.so \
     libhub_export.so \
     /usr/lib/

RUN ldconfig

COPY identity_hub .

RUN mkdir -p /data/identities

EXPOSE 8080

CMD ["/app/identity_hub"]
