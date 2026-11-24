#!/bin/bash
# Railway start script for Bichon (aalfath/bichon-railway-template).
# - fails fast (non-zero) on a missing or default encryption password
# - sizes threads and upload limits to the Railway service, not the host
# - replaces upstream's well-known first-boot admin password (admin@bichon)
#   with BICHON_ADMIN_PASSWORD on a loopback-only server before the public
#   listener ever starts
# - exits non-zero whenever Bichon stops without being asked to, so Railway's
#   ON_FAILURE restart policy brings it back
set -u

log() { echo "railway-start: $*"; }
die() { echo "railway-start: ERROR: $*" >&2; exit 1; }

SRV=/opt/bichon/bichon-server
SHIM=/opt/railway/freefloor.so

export BICHON_ROOT_DIR="${BICHON_ROOT_DIR:-/data/bichon}"
mkdir -p "$BICHON_ROOT_DIR" || die "cannot create $BICHON_ROOT_DIR (is the volume mounted at /data?)"
[ -w "$BICHON_ROOT_DIR" ] || die "$BICHON_ROOT_DIR is not writable"

# --- secrets ---------------------------------------------------------------
if [ -z "${BICHON_ENCRYPT_PASSWORD:-}" ] && [ -z "${BICHON_ENCRYPT_PASSWORD_FILE:-}" ]; then
  die "BICHON_ENCRYPT_PASSWORD is empty. Set it to a long random value and never change it afterwards."
fi
[ "${BICHON_ENCRYPT_PASSWORD:-}" = "change-this-default-password-now" ] && \
  die "BICHON_ENCRYPT_PASSWORD is upstream's public example value. Use a random value."
ADMIN_PW="${BICHON_ADMIN_PASSWORD:-}"
[ ${#ADMIN_PW} -ge 8 ] && [ ${#ADMIN_PW} -le 256 ] || \
  die "BICHON_ADMIN_PASSWORD must be 8 to 256 characters."
[ "$ADMIN_PW" = "admin@bichon" ] && die "BICHON_ADMIN_PASSWORD must not be upstream's default password."

# --- network ---------------------------------------------------------------
export BICHON_HTTP_PORT="${PORT:-${BICHON_HTTP_PORT:-15630}}"
export BICHON_BIND_IP="${BICHON_BIND_IP:-::}"   # IPv4 + IPv6 (Railway's private network is IPv6)
if [ -z "${BICHON_PUBLIC_URL:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export BICHON_PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
fi
export BICHON_ANSI_LOGS="${BICHON_ANSI_LOGS:-false}"

# --- size to the service, not the host (Railway shows the host's 32+ CPUs) --
cpus=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r q p < /sys/fs/cgroup/cpu.max
  [ "$q" != "max" ] && [ -n "${p:-}" ] && cpus=$(( (q + p - 1) / p ))
fi
[ -z "$cpus" ] && cpus=$(nproc 2>/dev/null || echo 2)
[ "$cpus" -gt 8 ] && cpus=8
[ "$cpus" -lt 1 ] && cpus=1
mem_mb=0
if [ -r /sys/fs/cgroup/memory.max ] && [ "$(cat /sys/fs/cgroup/memory.max)" != "max" ]; then
  mem_mb=$(( $(cat /sys/fs/cgroup/memory.max) / 1048576 ))
fi
workers=$(( cpus < 2 ? 2 : cpus ))
export TOKIO_WORKER_THREADS="${TOKIO_WORKER_THREADS:-$workers}"
sync_default=$(( cpus * 2 )); [ "$sync_default" -gt 8 ] && sync_default=8
[ "$mem_mb" -gt 0 ] && [ "$mem_mb" -lt 1024 ] && [ "$sync_default" -gt 2 ] && sync_default=2
export BICHON_SYNC_CONCURRENCY="${BICHON_SYNC_CONCURRENCY:-$sync_default}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

# Web uploads: upstream refuses an upload unless twice the per-file limit is
# free on the volume (1 GB MBOX / 2 GB PST by default), so cap the limits to
# a quarter of the volume on small volumes.
vol_mb=$(df -Pm "$BICHON_ROOT_DIR" | awk 'NR==2{print $2}')
if [ -n "$vol_mb" ] && [ "$vol_mb" -gt 0 ]; then
  q=$(( vol_mb / 4 )); [ "$q" -lt 16 ] && q=16
  mbox=$(( q < 1024 ? q : 1024 )); pst=$(( q < 2048 ? q : 2048 ))
  export BICHON_WEB_MBOX_UPLOAD_LIMIT_MB="${BICHON_WEB_MBOX_UPLOAD_LIMIT_MB:-$mbox}"
  export BICHON_WEB_PST_UPLOAD_LIMIT_MB="${BICHON_WEB_PST_UPLOAD_LIMIT_MB:-$pst}"
  big=$(( BICHON_WEB_MBOX_UPLOAD_LIMIT_MB > BICHON_WEB_PST_UPLOAD_LIMIT_MB ? BICHON_WEB_MBOX_UPLOAD_LIMIT_MB : BICHON_WEB_PST_UPLOAD_LIMIT_MB ))
  export BICHON_UPLOAD_BODY_LIMIT_MB="${BICHON_UPLOAD_BODY_LIMIT_MB:-$(( big + 76 ))}"
fi
log "cpus=$cpus mem_limit_mb=$mem_mb volume_mb=${vol_mb:-?} tokio_workers=$TOKIO_WORKER_THREADS sync_concurrency=$BICHON_SYNC_CONCURRENCY mbox_upload_mb=${BICHON_WEB_MBOX_UPLOAD_LIMIT_MB:-default}"

# --- first-boot admin password ---------------------------------------------
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
MARK="$BICHON_ROOT_DIR/.railway-admin-password-set"

bootstrap_admin() {
  local port=15699 api tok code i pid
  api="http://127.0.0.1:${port}/api"
  log "first boot: setting the admin password on a loopback-only server"
  BICHON_BIND_IP=127.0.0.1 BICHON_HTTP_PORT=$port BICHON_ENABLE_SMTP=false LD_PRELOAD=$SHIM "$SRV" >/tmp/bootstrap.log 2>&1 &
  pid=$!
  for i in $(seq 1 120); do
    curl -fs -m 3 "$api/status" >/dev/null 2>&1 && break
    kill -0 "$pid" 2>/dev/null || { cat /tmp/bootstrap.log; die "Bichon exited during first-boot setup"; }
    sleep 1
  done
  login() {
    curl -s -m 20 -H 'content-type: application/json' \
      -d "{\"username\":\"admin\",\"password\":\"$(json_str "$1")\"}" "$api/login" \
      | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
  }
  local rc=0
  if [ -n "$(login "$ADMIN_PW")" ]; then
    log "admin password already matches BICHON_ADMIN_PASSWORD"
  else
    tok=$(login "admin@bichon")
    if [ -n "$tok" ]; then
      code=$(curl -s -m 20 -o /tmp/bootstrap.resp -w '%{http_code}' -H "authorization: Bearer $tok" \
        -H 'content-type: application/json' \
        -d "{\"password\":\"$(json_str "$ADMIN_PW")\"}" "$api/v1/users/100000000000000")
      if [ "$code" = 200 ] && [ -n "$(login "$ADMIN_PW")" ] && [ -z "$(login "admin@bichon")" ]; then
        log "admin password set from BICHON_ADMIN_PASSWORD"
      else
        echo "railway-start: ERROR: could not replace the default admin password (HTTP $code): $(head -c 300 /tmp/bootstrap.resp)" >&2
        rc=1
      fi
    else
      log "WARNING: neither BICHON_ADMIN_PASSWORD nor the default password works for 'admin'; leaving the account as it is"
    fi
  fi
  kill -TERM "$pid" 2>/dev/null
  for i in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  [ $rc -eq 0 ] || exit 1
  : > "$MARK"
}
[ -e "$MARK" ] || bootstrap_admin

# --- run Bichon; any stop we didn't ask for exits non-zero -------------------
stopping=0
LD_PRELOAD=$SHIM "$SRV" &
child=$!
on_term() { stopping=1; kill -TERM "$child" 2>/dev/null; }
trap on_term TERM INT
while kill -0 "$child" 2>/dev/null; do
  wait "$child"; rc=$?
  kill -0 "$child" 2>/dev/null || break
done
if [ "$stopping" = 1 ]; then
  log "Bichon stopped on request (exit $rc)"
  exit "$rc"
fi
[ "$rc" -eq 0 ] && rc=1
echo "railway-start: ERROR: Bichon stopped unexpectedly (exit $rc). If the log above says 'below the free-space floor', the volume is full: grow it in Railway's volume settings." >&2
exit "$rc"
