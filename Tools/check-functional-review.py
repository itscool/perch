#!/usr/bin/env python3
"""Build/run isolated functional regressions without launching the installed app.

Uses distinct preferences, config storage and XPC names. Startup, AppleScript,
helper installation and physical monitor requests are blocked in the test copy.
The production sources and installed app are not rewritten by this tool.
"""
from pathlib import Path
import argparse
import plistlib
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='perch-functional-review-'))
src = root / 'Sources'
src.mkdir(parents=True, exist_ok=True)
for path in (repo / 'Sources').iterdir():
    if path.is_file():
        shutil.copy2(path, src / path.name)
images = root / 'renders'
images.mkdir(exist_ok=True)
for path in src.glob('*Tests.swift'):
    path.write_text(path.read_text().replace('/private/tmp/perch-', str(images / 'perch-')))
main = src / 'main.swift'
declarations = main.read_text().split('if CommandLine.arguments.contains("--check-modifier-access")')[0]
declarations = declarations.replace('func script(_ source: String) throws -> NSAppleEventDescriptor {', 'func script(_ source: String) throws -> NSAppleEventDescriptor {\n    throw AppError(message: "AppleScript blocked in isolated tests")\n/*')
declarations = declarations.replace('\nfunc sleepDisabled()', '\n*/}\n\nfunc sleepDisabled()', 1)
# The disabled original script body includes its closing brace inside the comment.
main.write_text(declarations + '''
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
SettingsWindow.shared.testing = true
let suites: [(String, () throws -> Void)] = [
    ("catalog", runCatalogTests), ("CPU logic", runProcessCPUTests),
    ("protection issues", runProtectionIssueTests), ("process events", runProcessEventTests),
    ("helper IPC", runHelperStatusTests), ("housekeeping", runHousekeepingTests),
    ("privacy plan with mock executor", runPanicTests), ("input transforms", runInputTests),
    ("keyboard protocol", runKeyboardModeTests), ("navigation keys", runNavigationKeyTests),
    ("navigation runtime", runNavigationRuntimeTests), ("reset isolation", runSettingsResetTests),
    ("monitor connections", runMonitorConnectionTests), ("monitor logic", runMonitorInputTests),
    ("monitor transactions", runMonitorTransactionTests), ("navigation probe", runNavigationProbeTests),
    ("keyboard registration", runKeyboardRegistrationTests), ("AppKit settings", runSettingsTests),
    ("multi-monitor groups", runMonitorGroupTests), ("lid grace and enforcement", runLidGuardTests)
]
var failures = 0
for (name, run) in suites {
    do { try run(); print("SUITE PASS: \\(name)") }
    catch { failures += 1; print("SUITE FAIL: \\(name): \\(error)") }
}
print("RESULT: \\(suites.count - failures)/\\(suites.count) isolated suites passed")
exit(failures == 0 ? 0 : 1)
''')
model = src / 'AgentSafetyModel.swift'
model.write_text(model.read_text().replace('FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Safety", isDirectory: true)', 'URL(fileURLWithPath: "' + str(root / 'isolated-safety') + '", isDirectory: true)'))
ipc = src / 'HelperStatusIPC.swift'
ipc.write_text(ipc.read_text().replace('local.scott.perch.guardian.status', 'local.perch.functional-review.guardian.status').replace('local.scott.perch.input.status', 'local.perch.functional-review.input.status'))
installer = src / 'GuardianInstall.swift'
installer.write_text(installer.read_text().replace('static func install() throws {', 'static func install() throws {\n        throw AppError(message: "Helper installation blocked in isolated tests")\n/*').replace('    static func writeJob(', '*/}\n    static func writeJob(', 1))
monitor = src / 'MonitorInputs.swift'
monitor.write_text(monitor.read_text().replace('func run(_ arguments: [String]) throws -> Data {', 'func run(_ arguments: [String]) throws -> Data {\n        guard arguments == ["transport-self-test"] else { throw AppError(message: "Physical monitor requests blocked in isolated tests") }', 1))
lid = src / 'LidGuardHardware.swift'
lid_text = lid.read_text()
for signature, message in [('func preventLidSleep(_ enabled: Bool) throws', 'Physical lid control blocked in isolated tests'), ('func requestSleep() throws', 'System sleep requests blocked in isolated tests')]:
    pattern = r'    ' + re.escape(signature) + r' \{.*?\n    \}'
    lid_text, replacements = re.subn(pattern, '    ' + signature + ' {\n        throw AppError(message: "' + message + '")\n    }', lid_text, count=1, flags=re.S)
    assert replacements == 1, 'Could not isolate power method: ' + signature
lid.write_text(lid_text)

lid_service = src / 'LidGuardService.swift'
lid_service.write_text(lid_service.read_text().replace('/var/run/local.scott.perch.lid.active', str(root / 'isolated-lid-ownership')))
app = root / 'Perch Functional Review.app' / 'Contents'
(app / 'MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Resources').mkdir(exist_ok=True)
info = plistlib.loads((repo / 'Info.plist').read_bytes())
info['CFBundleIdentifier'] = 'local.perch.functional-review'
info['CFBundleName'] = 'Perch Functional Review'
(app / 'Info.plist').write_bytes(plistlib.dumps(info))
for path in (repo / 'catalog').glob('*.json'):
    shutil.copy2(path, app / 'Resources' / path.name)
def run(*command, cwd=repo):
    subprocess.run(command, cwd=cwd, check=True)
run('xcrun', 'clang', '-std=c11', '-O3', '-Wall', '-Wextra', '-Werror', '-c', str(src / 'EventParser.c'), '-o', str(root / 'EventParser.o'))
run('xcrun', 'clang', '-std=c11', '-O3', '-Wall', '-Wextra', '-Werror', '-c', str(src / 'DDCWire.c'), '-o', str(root / 'DDCWire.o'))
run('xcrun', 'clang', '-fmodules', '-fmodules-cache-path=' + str(root / 'ClangModuleCache'), '-O2', '-DMAX_DISPLAYS=16', '-I', 'Vendor/m1ddc', '-I', str(src), str(src / 'PerchDisplay.m'), str(src / 'MonitorTransport.m'), 'Vendor/m1ddc/ioregistry.m', str(root / 'DDCWire.o'), '-framework', 'CoreDisplay', '-framework', 'IOKit', '-framework', 'Foundation', '-framework', 'CoreGraphics', '-o', str(app / 'MacOS/PerchDisplay'))
run('xcrun', 'swiftc', '-g', '-module-cache-path', str(root / 'ModuleCache'), '-import-objc-header', str(src / 'EventParser.h'), *map(str, sorted(src.glob('*.swift'))), str(root / 'EventParser.o'), str(root / 'DDCWire.o'), '-o', str(app / 'MacOS/Perch'), '-framework', 'AppKit', '-framework', 'IOKit', '-framework', 'ServiceManagement', '-framework', 'Carbon', '-framework', 'CoreAudio', '-framework', 'Security', '-O', '-whole-module-optimization', cwd=root)
run('codesign', '--force', '--sign', '-', str(app / 'MacOS/PerchDisplay'))
run('codesign', '--force', '--sign', '-', str(app.parent))
print('Isolated review artifacts:', root, flush=True)
run(str(app / 'MacOS/Perch'))
