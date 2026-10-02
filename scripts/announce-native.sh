#!/usr/bin/env bash
# Sourced by native.sh after database initialization and before cache compilation.
install_native_announce() {
  local source=/opt/unit3d-announce
  apt-get install -y build-essential pkg-config cmake
  useradd --system --home /opt/unit3d-announce --shell /usr/sbin/nologin unit3d-announce
  checkout_announce "$source"
  python3 "$ROOT/scripts/announce-configure.py" "$source" native
  install -d -o unit3d-announce -g unit3d-announce /opt/unit3d-rust
  chown -R unit3d-announce:unit3d-announce "$source"
  curl -fsSL https://sh.rustup.rs -o /opt/unit3d-rust/install-rust.sh
  chmod 755 /opt/unit3d-rust/install-rust.sh
  runuser -u unit3d-announce -- env CARGO_HOME=/opt/unit3d-rust/cargo RUSTUP_HOME=/opt/unit3d-rust/rustup \
    sh /opt/unit3d-rust/install-rust.sh -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION"
  (
    cd "$source" || exit 1
    runuser -u unit3d-announce -- env CARGO_HOME=/opt/unit3d-rust/cargo RUSTUP_HOME=/opt/unit3d-rust/rustup \
      SQLX_OFFLINE=true RUSTFLAGS='-C target-cpu=x86-64' \
      /opt/unit3d-rust/cargo/bin/cargo build --release --locked --jobs 2
  )
  install -m 755 "$source/target/release/unit3d-announce" /usr/local/bin/unit3d-announce
  chown -R root:unit3d-announce "$source"
  chmod 640 "$source/.env"
  cat > /etc/systemd/system/unit3d-announce.service <<'EOF'
[Unit]
Description=UNIT3D Rust announce tracker
After=network.target mysql.service
Requires=mysql.service
[Service]
User=unit3d-announce
Group=unit3d-announce
WorkingDirectory=/opt/unit3d-announce
ExecStart=/usr/local/bin/unit3d-announce
Restart=on-failure
TimeoutStopSec=120
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now unit3d-announce
  for attempt in {1..60}; do
    if curl -fsS http://127.0.0.1:6969/announce/health/ping | grep -q PONG; then break; fi
    [[ $attempt -lt 60 ]] || fail 'UNIT3D-Announce failed to start.'
    sleep 1
  done
  install -d /etc/nginx/snippets
  cat > /etc/nginx/snippets/unit3d-announce.conf <<'EOF'
# Expose only peer announce requests. Management API and health remain private.
location ~ "^/announce/[a-fA-F0-9]{32}$" {
    proxy_pass http://127.0.0.1:6969;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header Host $host;
    access_log off;
}
location /announce/ { return 404; }
EOF
}
