# syntax=docker/dockerfile:1
FROM rust:1.93.1-bookworm AS build
WORKDIR /build
COPY announce/ ./
# Avoid baking the build host's CPU instruction set into a portable image.
ENV SQLX_OFFLINE=true RUSTFLAGS="-C target-cpu=x86-64"
RUN cargo build --release --locked --jobs 2

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --system --home /opt/unit3d-announce --shell /usr/sbin/nologin announce
WORKDIR /opt/unit3d-announce
COPY --from=build /build/target/release/unit3d-announce /usr/local/bin/unit3d-announce
USER 10001:10001
CMD ["unit3d-announce"]
