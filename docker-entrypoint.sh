#!/bin/sh
set -eu

# Enable debug mode
: "${DEBUG:=0}"
if [ "$DEBUG" -eq 1 ]; then
    set -x
fi

# Known backends (from official PDNS docs)
SUPPORTED_BACKENDS="bind gmysql godbc gpgsql gsqlite3 geoip ldap lmdb lua2 pipe random remote tinydns"

# Helper: check if backend is in PDNS_launch (comma-separated, tolerant to spaces)
backend_enabled() {
    case ",$(echo "$PDNS_launch" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',')," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Helper: validate PDNS_launch content
validate_backends() {
    # Normalize list (trim, remove spaces, collapse commas)
    list=$(echo "$PDNS_launch" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*,[[:space:]]*/,/g;s/^,*//;s/,*$//')
    [ -n "$list" ] || { echo "ERROR: PDNS_launch is empty or unset" >&2; exit 1; }

    IFS=','; set -- $list; unset IFS
    for be; do
        [ -z "$be" ] && continue
        case " $SUPPORTED_BACKENDS " in
            *" $be "*) continue ;;
            *) echo "ERROR: Unsupported backend: '$be'" >&2
               echo "Supported: $SUPPORTED_BACKENDS" >&2
               exit 1
               ;;
        esac
    done
}

validate_backends

# ---------------------------
# PostgreSQL: gpgsql
# ---------------------------
if backend_enabled "gpgsql"; then
    echo "→ PostgreSQL (gpgsql) backend enabled."
    if [ "${SKIP_DB_INIT:-false}" = "true" ]; then
        echo "  Skipping PostgreSQL initialization (SKIP_DB_INIT=true)."
    else
        echo "  Waiting for PostgreSQL at ${PDNS_gpgsql_host}:${PDNS_gpgsql_port}..."
        until pg_isready -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" 2>/dev/null; do
            sleep 2
        done

        export PGPASSWORD="$PDNS_gpgsql_password"

        if [ "${SKIP_DB_CREATE:-false}" != "true" ]; then
            if ! psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '${PDNS_gpgsql_dbname}';" 2>/dev/null | grep -q '1'; then
                echo "  Creating database: ${PDNS_gpgsql_dbname}"
                psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d postgres -c "CREATE DATABASE ${PDNS_gpgsql_dbname};"
            else
                echo "  Database already exists."
            fi
        fi

        if psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" -c "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  PostgreSQL schema already present. Skipping init."
        else
            echo "  Initializing PostgreSQL schema..."
            psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" < /usr/share/doc/pdns-backend-pgsql/schema.pgsql.sql
        fi

        unset PGPASSWORD
    fi
fi

# ---------------------------
# MySQL: gmysql
# ---------------------------
if backend_enabled "gmysql"; then
    echo "→ MySQL (gmysql) backend enabled."
    if [ "${SKIP_DB_INIT:-false}" = "true" ]; then
        echo "  Skipping MySQL initialization."
    else
        echo "  Waiting for MySQL at ${PDNS_gmysql_host}:${PDNS_gmysql_port}..."
        until mysqladmin ping -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" >/dev/null 2>&1; do
            sleep 2
        done

        if [ "${SKIP_DB_CREATE:-false}" != "true" ]; then
            mysql -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
                -e "CREATE DATABASE IF NOT EXISTS \`${PDNS_gmysql_dbname}\`;"
        fi

        if mysql -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
            -D "$PDNS_gmysql_dbname" -e "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  MySQL schema already present. Skipping init."
        else
            echo "  Initializing MySQL schema..."
            mysql -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
                "$PDNS_gmysql_dbname" < /usr/share/doc/pdns-backend-mysql/schema.mysql.sql
        fi
    fi
fi

# ---------------------------
# SQLite3: gsqlite3
# ---------------------------
# ---------------------------
# SQLite3: gsqlite3
# ---------------------------
if backend_enabled "gsqlite3"; then
    DB_PATH="$PDNS_gsqlite3_database"
    echo "→ SQLite3 (gpgsql) backend enabled. DB: $DB_PATH"

    if [ "${SKIP_DB_INIT:-false}" = "true" ]; then
        echo "  Skipping SQLite3 initialization."
    else
        DIR="$(dirname "$DB_PATH")"
        mkdir -p "$DIR"

        # Only chown if we're NOT on a mounted volume (i.e., avoid chown on bind mounts)
        # Heuristic: if the parent is NOT under /var/lib, /etc/pdns, etc., skip chown
        case "$DIR" in
            /var/lib/powerdns|/etc/pdns|/run/powerdns)
                chown pdns:pdns "$DIR"
                ;;
            *)
                # Assume it's a user-provided path (e.g., mounted volume) — skip chown
                echo "  ⚠️  Skipping chown on custom path: $DIR (ensure writable by UID 102)"
                ;;
        esac

        if [ -f "$DB_PATH" ] && sqlite3 "$DB_PATH" "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  SQLite3 schema already present."
        else
            echo "  Initializing SQLite3 schema..."
            sqlite3 "$DB_PATH" ".read /usr/share/doc/pdns-backend-sqlite3/schema.sqlite3.sql"
            # Only chown the file if we can (and if it's not on a restricted mount)
            if [ -f "$DB_PATH" ]; then
                chown pdns:pdns "$DB_PATH" 2>/dev/null || echo "  ⚠️  Could not chown DB file (may still work if writable)"
                chmod 600 "$DB_PATH" 2>/dev/null || true
            fi
        fi
    fi
fi

# ---------------------------
# Inform about non-initializing backends
# ---------------------------
for be in bind geoip ldap lmdb lua2 pipe random remote tinydns; do
    if backend_enabled "$be"; then
        echo "→ Non-initializing backend enabled: $be"
    fi
done

# ---------------------------
# Generate config and start
# ---------------------------
echo "→ Generating /etc/powerdns/pdns.conf from template..."
subvars --prefix 'PDNS_' < /pdns.conf.tpl > /etc/powerdns/pdns.conf
chown pdns:pdns /etc/powerdns/pdns.conf

echo "→ Starting PowerDNS..."
exec "$@"