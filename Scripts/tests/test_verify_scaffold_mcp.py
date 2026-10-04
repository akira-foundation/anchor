"""Run the scaffold's mandatory MCP gates with isolated command doubles."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCAFFOLD_SCRIPT = Path(__file__).resolve().parents[1] / "verify-scaffold.sh"
PROJECT_FILE = (
    Path(__file__).resolve().parents[2]
    / "Apps/AnchorMac/AnchorMac.xcodeproj/project.pbxproj"
)
COMMAND_DOUBLE = r'''#!/usr/bin/env python3
import os, pathlib, plistlib, sys
name = pathlib.Path(sys.argv[0]).name
scenario = os.environ['GATE_SCENARIO']
with open(os.environ['GATE_LOG'], 'a') as log:
    log.write(name + ' ' + ' '.join(sys.argv[1:]) + '\n')
if name == 'xcodebuild' and 'AnchorMac' in sys.argv:
    helpers_path = pathlib.Path('.build/xcode-derived-data/Build/Products/Debug/AnchorMac.app/Contents/Helpers')
    helper_bundle = helpers_path / 'AnchorMCPServer.app'
    helper_path = helper_bundle / 'Contents/MacOS/AnchorMCPServer'
    helper_path.parent.mkdir(parents=True, exist_ok=True)
    if scenario != 'missing':
        helper_path.touch()
        helper_path.chmod(0o700)
        (helper_bundle / 'Contents/embedded.provisionprofile').touch()
        link_target = 'AnchorMCPServer.app/Contents/MacOS/AnchorMCPServer'
        if scenario == 'unsafe_link':
            link_target = '/tmp/AnchorMCPServer'
        (helpers_path / 'AnchorMCPServer').symlink_to(link_target)
if name == 'codesign':
    if '--verify' in sys.argv:
        sys.exit(1 if scenario == 'signature' else 0)
    if sys.argv[1:5] != ['-d', '--entitlements', '-', '--xml']:
        sys.exit(2)
    groups = ['ZF76N8225L.com.akira.anchor']
    if scenario == 'group' and sys.argv[-1].endswith('AnchorMCPServer'):
        groups = ['other.group']
    entitlements = {
        'com.apple.application-identifier': 'ZF76N8225L.com.akira.anchor.mcp-server',
        'keychain-access-groups': groups,
    }
    if scenario == 'signed_identifier':
        entitlements['com.apple.application-identifier'] = 'ZF76N8225L.com.akira.other'
    if scenario == 'cloudkit':
        entitlements['com.apple.developer.icloud-services'] = ['CloudKit']
    sys.stdout.buffer.write(plistlib.dumps(entitlements))
if name == 'security':
    if scenario == 'profile':
        sys.exit(1)
    application_identifier = 'ZF76N8225L.*'
    if scenario == 'identifier':
        application_identifier = 'ZF76N8225L.com.akira.other'
    profile_groups = ['ZF76N8225L.com.akira.anchor']
    if scenario == 'profile_group':
        profile_groups = ['ZF76N8225L.com.akira.other']
    sys.stdout.buffer.write(plistlib.dumps({
        'Entitlements': {
            'com.apple.application-identifier': application_identifier,
            'keychain-access-groups': profile_groups,
        }
    }))
if name == 'python3':
    if any(argument.endswith('verify-mcp-stdio.py') for argument in sys.argv):
        sys.exit(1 if scenario == 'probe' and '--self-test' not in sys.argv else 0)
    os.execv(os.environ['REAL_PYTHON'], [os.environ['REAL_PYTHON']] + sys.argv[1:])
if name == 'xcrun':
    if sys.argv[1:] != ['simctl', 'list', '--json', 'devices', 'available']:
        sys.exit(2)
    if scenario == 'simulator':
        sys.stdout.write('{"devices":{}}')
        sys.exit(0)
    sys.stdout.write('{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":['
                     '{"name":"iPhone 18 Pro","udid":"IPHONE-AVAILABLE","isAvailable":true},'
                     '{"name":"iPad Pro 13-inch (M5)","udid":"IPAD-AVAILABLE","isAvailable":true}'
                     ']}}')
'''


class ScaffoldMCPGateTests(unittest.TestCase):
    def run_scaffold(self, scenario):
        with tempfile.TemporaryDirectory(prefix="anchor-scaffold-gate-") as directory:
            root = Path(directory)
            (root / "Scripts").mkdir()
            (root / "Packages" / "Fixture").mkdir(parents=True)
            (root / "Packages" / "AnchorDomain" / "Sources").mkdir(parents=True)
            (root / "bin").mkdir()
            shutil.copyfile(SCAFFOLD_SCRIPT, root / "Scripts" / "verify-scaffold.sh")
            for name in ("swift", "xcodebuild", "codesign", "python3", "security", "xcrun"):
                driver = root / "bin" / name
                driver.write_text(COMMAND_DOUBLE.replace(
                    "#!/usr/bin/env python3", "#!" + sys.executable))
                driver.chmod(0o700)
            completed = subprocess.run(
                ["bash", str(root / "Scripts" / "verify-scaffold.sh")],
                env={**os.environ, "PATH": str(root / "bin") + ":" + os.environ["PATH"],
                     "GATE_SCENARIO": scenario, "GATE_LOG": str(root / "calls"),
                     "REAL_PYTHON": sys.executable},
                capture_output=True, text=True, timeout=15)
            return completed, (root / "calls").read_text()

    def test_preserves_existing_builds_and_runs_mandatory_mcp_gates(self):
        completed, calls = self.run_scaffold("pass")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("codesign --verify --strict", calls)
        self.assertIn("security cms -D -i", calls)
        self.assertIn("codesign -d --entitlements - --xml", calls)
        self.assertIn("verify-mcp-stdio.py", calls)
        self.assertIn("verify-mcp-stdio.py --self-test", calls)
        self.assertEqual(calls.count("verify-mcp-stdio.py"), 2)
        self.assertIn("--filter AnchorMCPStdioFixtureTests", calls)
        self.assertEqual(calls.count("xcodebuild build"), 3)
        self.assertIn("platform=iOS Simulator,id=IPHONE-AVAILABLE", calls)
        self.assertIn("platform=iOS Simulator,id=IPAD-AVAILABLE", calls)

    def test_project_uses_provisioned_app_bundle_and_stable_command_link(self):
        project = PROJECT_FILE.read_text()
        self.assertIn("path = AnchorMCPServer.app;", project)
        self.assertIn(
            "productReference = A9C000000000000000000004 /* AnchorMCPServer.app */;\n"
            '\t\t\tproductType = "com.apple.product-type.application";', project
        )
        self.assertIn("ENABLE_DEBUG_DYLIB = NO;", project)
        self.assertIn("Create MCP Helper Command Link", project)
        self.assertIn(
            "AnchorMCPServer.app/Contents/MacOS/AnchorMCPServer", project
        )

    def test_rejects_missing_helper_signature_group_cloudkit_and_probe_failure(self):
        for scenario in (
            "missing", "signature", "group", "cloudkit", "profile", "identifier",
            "profile_group", "signed_identifier", "unsafe_link", "probe", "simulator"
        ):
            with self.subTest(scenario=scenario):
                completed, _ = self.run_scaffold(scenario)
                self.assertNotEqual(completed.returncode, 0)
                self.assertNotIn("Scaffold verification passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
