#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/PuneetGOTO/Acadhelp.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-/opt/academico}"
APP_PORT="${APP_PORT:-8080}"
APP_HTTPS_PORT="${APP_HTTPS_PORT:-8443}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
SEED_DATABASE="${SEED_DATABASE:-auto}"
CREATE_ADMIN="${CREATE_ADMIN:-auto}"
ADMIN_EMAIL="${ADMIN_EMAIL:-academico@thomasdebay.com}"
ADMIN_CREDENTIALS_FILE="${ADMIN_CREDENTIALS_FILE:-/root/academico-admin.txt}"

log() {
    printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "Run this script as root, or with sudo."
    fi
}

random_secret() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-32
}

install_docker() {
    log "Installing prerequisites"
    apt-get update
    apt-get install -y ca-certificates curl gnupg git openssl

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        log "Docker and Docker Compose are already installed"
        systemctl enable --now docker >/dev/null 2>&1 || true
        return
    fi

    log "Installing Docker Engine and Compose plugin"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    . /etc/os-release
    local codename="${VERSION_CODENAME:-}"
    [ -n "$codename" ] || fail "Could not detect Ubuntu release codename."

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$(dpkg --print-architecture)" "$codename" > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
}

checkout_code() {
    log "Preparing application directory at ${APP_DIR}"
    mkdir -p "$(dirname "$APP_DIR")"

    if [ -d "$APP_DIR/.git" ]; then
        git -C "$APP_DIR" remote set-url origin "$REPO_URL"
        git -C "$APP_DIR" fetch origin "$BRANCH"
        git -C "$APP_DIR" checkout "$BRANCH"
        git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
        return
    fi

    if [ -e "$APP_DIR" ] && [ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        fail "${APP_DIR} exists but is not a Git checkout. Move it away or set APP_DIR to another path."
    fi

    git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
}

env_value() {
    local key="$1"
    local file="$APP_DIR/.env"
    [ -f "$file" ] || return 1
    grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

set_env() {
    local key="$1"
    local value="$2"
    local file="$APP_DIR/.env"
    local escaped
    escaped="$(printf '%s' "$value" | sed -e 's/[\/&]/\\&/g')"

    if grep -qE "^${key}=" "$file"; then
        sed -i "s/^${key}=.*/${key}=${escaped}/" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

prepare_env() {
    cd "$APP_DIR"

    local created_env=false
    if [ ! -f .env ]; then
        log "Creating .env from .env.example"
        cp .env.example .env
        created_env=true
    fi

    local detected_ip
    detected_ip="$(hostname -I | awk '{print $1}')"
    detected_ip="${detected_ip:-127.0.0.1}"

    local app_url="${APP_URL:-}"
    if [ -z "$app_url" ] && [ "$created_env" = "false" ]; then
        app_url="$(env_value APP_URL || true)"
    fi
    app_url="${app_url:-http://${detected_ip}:${APP_PORT}}"

    local db_password="${DB_PASSWORD:-}"
    db_password="${db_password:-$(env_value DB_PASSWORD || true)}"
    db_password="${db_password:-$(random_secret)}"

    local db_root_password="${DB_ROOT_PASSWORD:-}"
    db_root_password="${db_root_password:-$(env_value DB_ROOT_PASSWORD || true)}"
    db_root_password="${db_root_password:-$(random_secret)}"

    set_env APP_NAME "Academico"
    set_env APP_ENV "${APP_ENV:-production}"
    set_env APP_DEBUG "${APP_DEBUG:-false}"
    set_env APP_URL "$app_url"
    set_env APP_PORT "$APP_PORT"
    set_env APP_HTTPS_PORT "$APP_HTTPS_PORT"
    set_env DB_CONNECTION "${DB_CONNECTION:-mariadb}"
    set_env DB_HOST "${DB_HOST:-mariadb}"
    set_env DB_PORT "${DB_PORT:-3306}"
    set_env DB_DATABASE "${DB_DATABASE:-academico_filament}"
    set_env DB_USERNAME "${DB_USERNAME:-academico}"
    set_env DB_PASSWORD "$db_password"
    set_env DB_ROOT_PASSWORD "$db_root_password"
    set_env SESSION_DRIVER "${SESSION_DRIVER:-database}"
    set_env QUEUE_CONNECTION "${QUEUE_CONNECTION:-database}"
    set_env CACHE_STORE "${CACHE_STORE:-database}"

    mkdir -p storage/app storage/app/public storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
}

compose() {
    docker compose --env-file "$APP_DIR/.env" -f "$APP_DIR/docker-compose.yml" "$@"
}

initial_user_count() {
    compose exec -T app php artisan tinker --execute='echo \App\Models\User::query()->count();' \
        | tr -dc '0-9'
}

reference_data_count() {
    compose exec -T app php artisan tinker --execute='echo \App\Models\Campus::query()->count();' \
        | tr -dc '0-9'
}

write_admin_credentials() {
    install -m 600 /dev/null "$ADMIN_CREDENTIALS_FILE"
    {
        printf 'Academico admin login\n'
        printf 'URL=%s/admin\n' "$(env_value APP_URL)"
        printf 'Email=%s\n' "$ADMIN_EMAIL"
        printf 'Password=%s\n' "$ADMIN_PASSWORD"
        printf 'Generated=%s\n' "$(date -Is)"
    } > "$ADMIN_CREDENTIALS_FILE"
    chmod 600 "$ADMIN_CREDENTIALS_FILE"
}

ensure_admin_user() {
    local should_create="$1"
    if [ "$should_create" != "true" ]; then
        return
    fi

    ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(random_secret)}"

    log "Ensuring admin user exists"
    compose exec -T \
        -e ACADEMICO_ADMIN_EMAIL="$ADMIN_EMAIL" \
        -e ACADEMICO_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        app php artisan tinker --execute='
$email = getenv("ACADEMICO_ADMIN_EMAIL");
$password = getenv("ACADEMICO_ADMIN_PASSWORD");
$username = explode("@", $email)[0] ?: "admin";
$existingUsername = \App\Models\User::query()
    ->where("username", $username)
    ->where("email", "!=", $email)
    ->exists();

if ($existingUsername) {
    $username = "admin_".substr(md5($email), 0, 8);
}

$user = \App\Models\User::query()->updateOrCreate(
    ["email" => $email],
    [
        "username" => $username,
        "firstname" => "System",
        "lastname" => "Admin",
        "password" => \Illuminate\Support\Facades\Hash::make($password),
        "locale" => "en",
    ],
);

$role = \Spatie\Permission\Models\Role::query()->firstOrCreate(["name" => "admin"]);
$user->assignRole($role);
echo $email;
'

    write_admin_credentials
    log "Admin credentials saved to ${ADMIN_CREDENTIALS_FILE}"
}

open_firewall_port() {
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi '^Status: active'; then
        log "Opening TCP port ${APP_PORT} in UFW"
        ufw allow "${APP_PORT}/tcp"
    fi
}

wait_for_http() {
    local url="http://127.0.0.1:${APP_PORT}"
    log "Waiting for ${url}"

    for _ in $(seq 1 45); do
        if curl -fsSL --max-time 5 "$url" >/dev/null 2>&1; then
            return
        fi
        sleep 2
    done

    log "Application did not answer HTTP health check yet; showing recent app logs"
    compose logs --tail=80 app || true
    fail "HTTP health check failed at ${url}."
}

deploy() {
    require_root
    install_docker
    checkout_code
    prepare_env
    open_firewall_port

    log "Building and starting containers"
    compose up -d --build

    log "Generating Laravel APP_KEY if needed"
    if [ -z "$(env_value APP_KEY || true)" ]; then
        compose exec -T app php artisan key:generate --force
    fi

    if [ "$RUN_MIGRATIONS" = "true" ]; then
        log "Running database migrations"
        compose exec -T app php artisan migrate --force
    fi

    local users_before_seed
    users_before_seed="$(initial_user_count || printf '0')"

    local reference_rows
    reference_rows="$(reference_data_count || printf '0')"

    if [ "$SEED_DATABASE" = "true" ] || { [ "$SEED_DATABASE" = "auto" ] && [ "$users_before_seed" = "0" ] && [ "$reference_rows" = "0" ]; }; then
        log "Seeding reference data"
        compose exec -T app php artisan db:seed --class=ProdSeeder --force
    elif [ "$SEED_DATABASE" = "auto" ]; then
        log "Skipping automatic seed; existing reference data detected"
    fi

    if [ "$CREATE_ADMIN" = "true" ] || { [ "$CREATE_ADMIN" = "auto" ] && [ "$users_before_seed" = "0" ]; }; then
        ensure_admin_user true
    fi

    log "Refreshing Laravel caches"
    compose exec -T app php artisan storage:link || true
    compose exec -T app php artisan optimize:clear
    compose exec -T app php artisan config:cache
    compose exec -T app php artisan route:cache || true
    compose exec -T app php artisan view:cache

    wait_for_http

    log "Deployment complete"
    printf 'Application: %s/admin\n' "$(env_value APP_URL)"
    printf 'Compose status:\n'
    compose ps
}

deploy "$@"
