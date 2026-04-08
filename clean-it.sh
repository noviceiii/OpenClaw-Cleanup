#!/usr/bin/env bash
# clean-it.sh
# Combined pre-backup cleanup for Ubuntu Server + OpenClaw (headless VM)
# Run as root/sudo before every backup

set -o pipefail

# ================== CONFIG ==================
OPENCLAW_USER="user_name"                 # adjust to your main OpenClaw user (e.g. cleotine)
OPENCLAW_HOME="/home/${OPENCLAW_USER}/.openclaw"
LOGFILE="/var/log/clean-it.log"
DRY_RUN=false                             # set to true for testing only
DAYS_SESSION=0                            # delete old sessions after X days
DAYS_LOG=0                                # delete old logs after X days
DAYS_TMP=0                                # delete temp files after X days
# ===========================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

if [ "$DRY_RUN" = true ]; then
    log "DRY-RUN MODE enabled - no destructive actions"
    DRY_OPT="--dry-run"
else
    DRY_OPT=""
fi

log "=== Starting clean-it.sh (pre-backup cleanup) ==="

# 1. System cleanup
log "System: APT cache cleanup"
apt-get clean
apt-get autoclean
apt-get autoremove --purge -y

log "System: Vacuum systemd journal"
journalctl --vacuum-time=14d --vacuum-size=400M >/dev/null 2>&1

log "System: Clean /tmp"
rm -rf /tmp/* /tmp/.[!.]* /tmp/..?* 2>/dev/null || true

log "System: Old files in /var/tmp"
find /var/tmp -type f -mtime +14 -delete 2>/dev/null || true

# 2. OpenClaw specific cleanup
if [ -d "$OPENCLAW_HOME" ] && id "$OPENCLAW_USER" >/dev/null 2>&1; then
    log "OpenClaw: Built-in cleanup commands (as ${OPENCLAW_USER})"
    su - "$OPENCLAW_USER" -c "openclaw sessions cleanup ${DRY_OPT} || true" >>"$LOGFILE" 2>&1
    su - "$OPENCLAW_USER" -c "openclaw logs rotate ${DRY_OPT} || true" >>"$LOGFILE" 2>&1

    log "OpenClaw: Old session files (> ${DAYS_SESSION} days)"
    find "${OPENCLAW_HOME}/sessions" -type f -mtime +${DAYS_SESSION} -delete 2>/dev/null || true

    log "OpenClaw: Old log files (> ${DAYS_LOG} days)"
    find "${OPENCLAW_HOME}/logs" -type f -name "*.log*" -mtime +${DAYS_LOG} -delete 2>/dev/null || true

    log "OpenClaw: Stale lock files"
    find "${OPENCLAW_HOME}" -name "*.lock" -delete 2>/dev/null || true

    log "OpenClaw: Temporary and cache files"
    rm -rf "${OPENCLAW_HOME}"/tmp/* "${OPENCLAW_HOME}"/cache/* 2>/dev/null || true

    # Optional: Browser renderer cleanup (uncomment only if needed and no active tasks)
    # log "OpenClaw: Killing stale browser renderers"
    # su - "$OPENCLAW_USER" -c "pkill -f 'chrome.*--user-data-dir=.*openclaw' || true"
else
    log "WARNING: OpenClaw home directory or user not found - skipping OpenClaw cleanup"
fi

# 3. Final status
log "Cleanup finished. Current disk usage:"
df -h / | tee -a "$LOGFILE"

log "=== clean-it.sh completed ==="

echo "Cleanup log: $LOGFILE"
