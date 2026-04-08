#!/usr/bin/env bash
# clean-it.sh
# Combined pre-backup cleanup for Ubuntu Server + OpenClaw (headless VM)
# Run as root/sudo before every backup

set -o pipefail

# ================== CONFIG ==================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.ini"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    echo "       Copy config.example.ini to config.ini and adjust the values."
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"
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

# 3. Time synchronisation
# The @reboot entry delays the restart by 25 seconds to allow network interfaces
# to come up fully before systemd-timesyncd attempts to contact NTP servers.
TIME_SYNC_CMD="@reboot sleep 25 && systemctl restart systemd-timesyncd"

log "Time: Checking systemd-timesyncd installation"
if ! dpkg-query -W -f='${Status}' systemd-timesyncd 2>/dev/null | grep -q "install ok installed"; then
    read -r -p "systemd-timesyncd is not installed. Install it now? [y/N] " install_answer
    if [[ "${install_answer,,}" == "y" ]]; then
        log "Time: Installing systemd-timesyncd"
        apt-get install -y systemd-timesyncd
        systemctl enable --now systemd-timesyncd
        log "Time: systemd-timesyncd installed and enabled"
    else
        log "Time: Skipping systemd-timesyncd installation"
    fi
else
    log "Time: systemd-timesyncd is already installed"
fi

log "Time: Checking root crontab for time-sync entry"
if crontab -l 2>/dev/null | grep -qF "${TIME_SYNC_CMD}"; then
    log "Time: Time-sync crontab entry already present – no changes needed"
else
    log "Time: No time-sync crontab entry found"
    read -r -p "Add '@reboot' time-sync entry to root crontab? [y/N] " cron_answer
    if [[ "${cron_answer,,}" == "y" ]]; then
        if ( crontab -l 2>/dev/null; echo "${TIME_SYNC_CMD}" ) | crontab -; then
            log "Time: Added '${TIME_SYNC_CMD}' to root crontab"
        else
            log "WARNING: Failed to update root crontab – please add the entry manually: ${TIME_SYNC_CMD}"
        fi
    else
        log "Time: Skipping crontab update"
    fi
fi

# 4. Final status
log "Cleanup finished. Current disk usage:"
df -h / | tee -a "$LOGFILE"

log "=== clean-it.sh completed ==="

echo "Cleanup log: $LOGFILE"
