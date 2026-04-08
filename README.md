# clean-it.sh - Cleanup for OpenClaw

Combined safe cleanup script for Ubuntu Server (headless VM) + OpenClaw.

Runs before every backup to remove unnecessary files, old sessions, temporary data, logs and caches while keeping the system and OpenClaw installation clean and maintainable.

- Run daily or before each backup
- Integrate into your backup job (cron, Proxmox backup, rsync, etc.)
- Keep DRY_RUN=false in production
- Review log regularly during first weeks

Script is designed to be OpenClaw-standard compliant and easy to extend. Add new cleanup paths or commands directly in the respective sections.

## Purpose

- System-level cleanup (APT, journald, /tmp, /var/tmp)
- OpenClaw-specific cleanup (sessions, logs, locks, tmp/cache)
- Reduces backup size and keeps disk usage low
- Designed for Cleotine Claw multi-user environment

## Installation

```bash
sudo cp clean-it.sh /usr/local/bin/clean-it.sh
sudo chmod +x /usr/local/bin/clean-it.sh
```

## Configuration
Edit the top of the script:
```bash
OPENCLAW_USER="user_name"        # ← Change to your system user (e.g. robert)
OPENCLAW_HOME="/home/${OPENCLAW_USER}/.openclaw"
LOGFILE="/var/log/clean-it.log"
DRY_RUN=false                    # Set to true for testing
DAYS_SESSION=30
DAYS_LOG=14
DAYS_TMP=7
```

## Usage
Run as root before every backup:
```bash
sudo clean-it.sh
```

Example in backup script:
```bash
#!/bin/bash
sudo clean-it.sh && \
rsync -aAXv / /backup/location/ --delete --exclude=/dev --exclude=/proc ...
```

## Dry-Run Mode
For testing without deleting anything:
```bash
sudo DRY_RUN=true clean-it.sh
```

## Logging
All actions are logged to:
```
text/var/log/clean-it.log
```

## What gets cleaned
System:
- APT cache + autoclean + autoremove
- Systemd journal (14 days / max 400 MB)
- /tmp contents
- Old files in /var/tmp (>14 days)

OpenClaw:
- openclaw sessions cleanup
- openclaw logs rotate
- Old session files (e.g. >30 days), as set in parameter
- Old log files (e.g. >14 days), as set in parameter
- Stale .lock files
- Temporary files and cache directories

## License
This integration is licensed under the PolyForm Noncommercial License 1.0.0 (with additional terms).
- Use and modifications allowed **only for your own personal Eigengebrauch**.
- Redistribution of the software or any modified versions is prohibited.
- Commercial use requires prior written permission from the licensor.
