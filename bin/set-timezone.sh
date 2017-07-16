#!/bin/ash
# Sets the system timezone based on the TZ environment variable
log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] set-timezone.sh:",$0}'
}

apk --no-cache add tzdata
cp /usr/share/zoneinfo/$"TZ" /etc/localtime
echo "$TZ" > /etc/timezone
apk del --purge tzdata
log "Timezone set to $TZ"
