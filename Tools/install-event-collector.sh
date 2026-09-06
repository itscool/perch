#!/bin/sh
# User invokes this from Perch's setup UI with macOS administrator authorization.
# No Perch code runs persistently as root: launchd execs Apple's eslogger.
set -eu
perch_uid="$1"
case "$perch_uid" in ''|*[!0-9]*) exit 2;; esac
[ "$perch_uid" -ge 501 ] || exit 2
perch_dir="/Library/Application Support/Perch Events"
perch_job="/Library/LaunchDaemons/local.scott.perch.events.plist"
[ ! -L "$perch_dir" ] && [ ! -L "$perch_job" ] || exit 2
/bin/mkdir -p "$perch_dir"
/usr/sbin/chown root:wheel "$perch_dir"
/bin/chmod 755 "$perch_dir"
/bin/launchctl bootout system/local.scott.perch.events 2>/dev/null || true
[ ! -L "$perch_dir/events.pipe" ] || exit 2
if [ -e "$perch_dir/events.pipe" ]; then
    [ -p "$perch_dir/events.pipe" ] || exit 2
else
    /usr/bin/mkfifo -m 600 "$perch_dir/events.pipe"
fi
/bin/chmod 600 "$perch_dir/events.pipe"
/usr/sbin/chown "$perch_uid" "$perch_dir/events.pipe"
/bin/cat > "$perch_job" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.scott.perch.events</string>
<key>ProgramArguments</key><array><string>/usr/bin/eslogger</string><string>fork</string><string>exec</string><string>exit</string></array>
<key>StandardOutPath</key><string>/Library/Application Support/Perch Events/events.pipe</string>
<key>ProcessType</key><string>Interactive</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$perch_job"
/bin/chmod 644 "$perch_job"
/bin/launchctl bootstrap system "$perch_job"
