#!/bin/ash
# Sets the system timezone based on the TZ environment variable
log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] set-timezone.sh:",$0}'
}

if [ "$TZ" ]
then
	#ln -snf /usr/share/zoneinfo/$"TZ" /etc/localtime
	echo "$TZ" > /etc/timezone
	log "Timezone set to $TZ"
else
	log "No timezone defined! Use host system time"
fi
