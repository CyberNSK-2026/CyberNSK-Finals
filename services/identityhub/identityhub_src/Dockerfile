FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    libmicrohttpd-dev \
    libjansson-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY CMakeLists.txt .
COPY src/ src/

RUN mkdir build && cd build && cmake .. && make -j$(nproc)

# Install shared libraries
RUN cp /app/build/libhub_auth.so \
       /app/build/libhub_search.so \
       /app/build/libhub_resolve.so \
       /app/build/libhub_protocol.so \
       /app/build/libhub_export.so \
       /usr/lib/ && \
    ldconfig

RUN strip --strip-all /usr/lib/libhub_auth.so \
                       /usr/lib/libhub_search.so \
                       /usr/lib/libhub_resolve.so \
                       /usr/lib/libhub_protocol.so \
                       /usr/lib/libhub_export.so

RUN strip --strip-all /app/build/identity_hub

RUN mkdir -p /data/identities

EXPOSE 8080

CMD ["/app/build/identity_hub"]
