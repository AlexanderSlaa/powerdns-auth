# PowerDNS Authoritative Server Docker Image

A secure, flexible, and production-ready Docker image for **PowerDNS Authoritative Server**, supporting **all official backends** (PostgreSQL, MySQL, SQLite3, BIND, LMDB, LDAP, and more) with automatic schema initialization and runtime configuration via environment variables.

Built on **Debian `trixie-slim`**, this image follows container best practices: minimal footprint, non-root execution, and declarative setup.


## ✨ Features

- **All PowerDNS backends included**: `gpgsql`, `gmysql`, `gsqlite3`, `bind`, `lmdb`, `ldap`, `geoip`, `lua2`, `pipe`, `remote`, `tinydns`, and more.
- **Automatic database initialization** for PostgreSQL, MySQL, and SQLite3 (with optional skip flags).
- **Secure APT setup**: Uses PowerDNS’s official GPG-signed repository (`auth-50`).
- **Runtime configuration**: Generate `pdns.conf` from a template using environment variables via [`subvars`](https://github.com/kha7iq/subvars).
- **Non-root execution**: Runs as the dedicated `pdns` user.
- **Healthcheck ready**: Includes a `pdns_control ping` health probe.
- **Multi-arch support**: Works on `amd64` and `arm64`.


## 📦 Usage

### Basic (SQLite3 backend)

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  ghcr.io/<your-username>/pdns-authoritative:latest
```

### PostgreSQL Backend

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -e PDNS_launch=gpgsql \
  -e PDNS_gpgsql_host=postgres \
  -e PDNS_gpgsql_port=5432 \
  -e PDNS_gpgsql_user=pdns \
  -e PDNS_gpgsql_password=secret \
  -e PDNS_gpgsql_dbname=pdns \
  --network my-net \
  docker pull ghcr.io/alexanderslaa/powerdns-auth:latest
```

### MySQL Backend

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -e PDNS_launch=gmysql \
  -e PDNS_gmysql_host=mysql \
  -e PDNS_gmysql_port=3306 \
  -e PDNS_gmysql_user=pdns \
  -e PDNS_gmysql_password=secret \
  -e PDNS_gmysql_dbname=pdns \
  docker pull ghcr.io/alexanderslaa/powerdns-auth:latest
```

## ⚙️ Configuration

All PowerDNS settings can be configured via environment variables prefixed with `PDNS_`.

### Core Variables

| Variable | Default | Description |
|--------|--------|------------|
| `PDNS_launch` | `gsqlite3` | Comma-separated list of backends (e.g., `gpgsql,gsqlite3`) |
| `PDNS_guardian` | `yes` | Enable guardian process |
| `PDNS_setuid` / `PDNS_setgid` | `pdns` | User/group to run as |
| `PDNS_local_address` | `0.0.0.0` | Listen IPv4 address |
| `PDNS_local_ipv6` | `::` | Listen IPv6 address |
| `PDNS_local_port` | `53` | DNS port |
| `PDNS_master` / `PDNS_slave` | `no` | Enable master/slave mode |
| `PDNS_loglevel` | `3` | Logging verbosity (0–9) |

### Backend-Specific Examples

- **SQLite3**: `PDNS_gsqlite3_database=/var/lib/powerdns/pdns.sqlite3`
- **PostgreSQL**: `PDNS_gpgsql_host`, `PDNS_gpgsql_user`, `PDNS_gpgsql_password`, etc.
- **BIND**: `PDNS_bind_config=/etc/powerdns/bindbackend.conf`

> 💡 The full list of supported settings matches [PowerDNS’s official documentation](https://doc.powerdns.com/authoritative/). Just prefix with `PDNS_` and use lowercase/underscore (e.g., `allow-axfr-ips` → `PDNS_allow_axfr_ips`).


## 🛑 Skipping Database Initialization

To prevent automatic DB creation/schema setup (e.g., when reusing an existing DB):

```sh
-e SKIP_DB_INIT=true
```

To skip only **database creation** but still run schema init:

```sh
-e SKIP_DB_CREATE=true
```


## 📁 Volumes (Optional)

For persistent SQLite3 or LMDB data:

```sh
-v ./data:/var/lib/powerdns
```

For custom configs or zone files (when using `bind` backend):

```sh
-v ./bind:/etc/powerdns/bind
```

> ⚠️ The container ensures correct ownership (`pdns:pdns`) on `/var/lib/powerdns`.

---

## 🔒 Security

- Runs as non-root user (`pdns`).
- Uses official PowerDNS APT repository with GPG signature verification.
- Minimal base image (`debian:trixie-slim`).
- No unnecessary packages installed.


## 🛠 Building

```sh
docker build -t pdns-authoritative .
```

For multi-arch (requires `buildx`):

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t <your-registry>/pdns-authoritative:latest --push .
```


## 📜 License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
