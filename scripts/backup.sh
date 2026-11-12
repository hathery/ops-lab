#!/bin/bash
# 备份 /opt/myweb 到 /opt/backup，保留最近 7 天
#
# 用法：/opt/scripts/backup.sh
# 定时：crontab -e 添加  0 3 * * * /opt/scripts/backup.sh >/dev/null 2>&1

set -uo pipefail

SRC="/opt/myweb"
DST="/opt/backup"
KEEP_DAYS=7
TS=$(date +%Y%m%d_%H%M%S)
LOG="/var/log/myweb-backup.log"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

if [ ! -d "$SRC" ]; then
    log "ERROR 源目录 $SRC 不存在"
    exit 1
fi

mkdir -p "$DST"

if tar -czf "$DST/myweb_${TS}.tar.gz" -C /opt myweb 2>>"$LOG"; then
    SIZE=$(du -h "$DST/myweb_${TS}.tar.gz" | cut -f1)
    log "OK   备份完成 myweb_${TS}.tar.gz (${SIZE})"
else
    log "ERROR 打包失败"
    exit 1
fi

# 清理超过保留期的备份
find "$DST" -name 'myweb_*.tar.gz' -mtime +"$KEEP_DAYS" -delete 2>/dev/null

COUNT=$(find "$DST" -name 'myweb_*.tar.gz' | wc -l | tr -d ' ')
log "INFO 当前保留备份 ${COUNT} 个"
