#!/bin/sh
# User invokes this from Perch's setup UI with macOS administrator authorization.
# A signed native launcher records its identity, then execs Apple's eslogger.
# No Perch code runs persistently as root and no shell remains in the launch path.
set -eu
[ "$#" -eq 3 ] || exit 2
perch_uid="$1"
perch_source="$2"
perch_requirement="$3"
case "$perch_uid" in ''|*[!0-9]*) exit 2;; esac
[ "$perch_uid" -ge 501 ] || exit 2
perch_dir="/Library/Application Support/Perch Events"
perch_job="/Library/LaunchDaemons/local.scott.perch.events.plist"
[ ! -L "$perch_dir" ] && [ ! -L "$perch_job" ] || exit 2
for perch_parent in /Library '/Library/Application Support' /Library/LaunchDaemons; do
    [ ! -L "$perch_parent" ] && [ "$(/usr/bin/stat -f %u "$perch_parent")" = 0 ] || exit 2
    [ -z "$(/usr/bin/find "$perch_parent" -prune -perm +022 -print)" ] || exit 2
done
if [ -e "$perch_dir" ]; then
    [ -d "$perch_dir" ] && [ "$(/usr/bin/stat -f %u "$perch_dir")" = 0 ] || exit 2
    [ -z "$(/usr/bin/find "$perch_dir" -prune -perm +022 -print)" ] || exit 2
fi
[ ! -e "$perch_job" ] || [ -f "$perch_job" ] || exit 2
[ ! -L "$perch_dir/PerchEventLauncher" ] || exit 2
[ ! -e "$perch_dir/PerchEventLauncher" ] || [ -f "$perch_dir/PerchEventLauncher" ] || exit 2
/bin/mkdir -p "$perch_dir"
/usr/sbin/chown root:wheel "$perch_dir"
/bin/chmod 755 "$perch_dir"
# Stage and verify before stopping the working collector.
[ ! -L "$perch_source" ] && [ -f "$perch_source" ] || exit 2
perch_staged=$(/usr/bin/mktemp "$perch_dir/.launcher.XXXXXX")
perch_staged_job=$(/usr/bin/mktemp "$perch_dir/.job.XXXXXX")
trap '/bin/rm -f "$perch_staged" "$perch_staged_job"' EXIT
/bin/cp "$perch_source" "$perch_staged"
/usr/sbin/chown root:wheel "$perch_staged"
/bin/chmod 755 "$perch_staged"
/usr/bin/codesign --verify --strict --test-requirement "=$perch_requirement" "$perch_staged"
[ ! -L "$perch_dir/events.pipe" ] || exit 2
if [ -e "$perch_dir/events.pipe" ]; then
    [ -p "$perch_dir/events.pipe" ] || exit 2
else
    /usr/bin/mkfifo -m 600 "$perch_dir/events.pipe"
fi
/bin/chmod 600 "$perch_dir/events.pipe"
/usr/sbin/chown "$perch_uid" "$perch_dir/events.pipe"
/bin/cat > "$perch_staged_job" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.scott.perch.events</string>
<key>ProgramArguments</key><array><string>/Library/Application Support/Perch Events/PerchEventLauncher</string></array>
<key>StandardOutPath</key><string>/Library/Application Support/Perch Events/events.pipe</string>
<key>ProcessType</key><string>Interactive</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$perch_staged_job"
/bin/chmod 644 "$perch_staged_job"
/usr/bin/plutil -lint "$perch_staged_job"
/bin/launchctl bootout system/local.scott.perch.events 2>/dev/null || true
/bin/mv -f "$perch_staged" "$perch_dir/PerchEventLauncher"
/bin/mv -f "$perch_staged_job" "$perch_job"
/bin/launchctl bootstrap system "$perch_job"
