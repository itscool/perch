# Read-only lid diagnostics

After a user-operated lid/power test, collect evidence without changing power,
permissions, helpers or hardware:

```sh
python3 Tools/collect-lid-diagnostics.py \
  --app /absolute/path/to/Perch.app \
  --output /absolute/task/outputs/lid-diagnostics.json
```

Use a new output filename for each capture. The command refuses to overwrite
an existing report. It needs no administrator prompt, performs no sleep or
enable/disable operation, and does not upload anything. `--hours 1` through
`--hours 24` restrict the history (default 24). Missing/unreadable sources are
reported as unavailable rather than treated as empty evidence.

Record the physical sequence and approximate local time alongside the report:
lid closed/open, cable disconnected/reconnected, whether an external display
was attached, and what the user actually saw. Compare the first macOS sleep
entry with Perch's preceding request/failure/deadline messages. A wake entry
after a helper restart may have no matching observed sleep entry. Do not infer
that no sleep occurred from an empty or incomplete journal.

The cached `AppleClamshellCausesSleep` property does not verify effective lid
prevention. A successful command is acknowledgment, not proof the Mac stayed
awake. Bundle versions are installed-file observations, not running-process
version verification. This report supplements coordinated physical testing;
it does not authorize or perform it.
