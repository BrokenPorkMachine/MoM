"""Exercise project generation and reject malformed/conflicted project fixtures."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="VB-Project-") as scratch:
    fixture = Path(scratch)
    for directory in ("App", "Core", "Helpers", "Privileged", "Resources"):
        shutil.copytree(root / directory, fixture / directory)
    (fixture / "Scripts").mkdir()
    (fixture / "MacOnMac.xcodeproj").mkdir()
    for name in ("regenerate-pbx-linux.py", "check-project-sources.py"):
        shutil.copyfile(root / "Scripts" / name, fixture / "Scripts" / name)
    shutil.copyfile(root / "project.yml", fixture / "project.yml")
    subprocess.run([sys.executable, str(fixture / "Scripts/regenerate-pbx-linux.py")], check=True, capture_output=True)
    checker = [sys.executable, str(fixture / "Scripts/check-project-sources.py")]
    subprocess.run(checker, check=True, capture_output=True)
    project = fixture / "MacOnMac.xcodeproj/project.pbxproj"
    valid = project.read_text()
    def reject(content, reason):
        project.write_text(content)
        result = subprocess.run(checker, capture_output=True, text=True)
        assert result.returncode != 0 and reason in result.stderr, (reason, result.stdout, result.stderr)
    reject(valid.replace("dependencies = ();", "dependencies = ( , );", 1), "invalid empty array")
    reject(valid + "\n<<<<<<< ours\n=======\n>>>>>>> theirs\n", "conflict markers")
    if sys.platform == "darwin":
        reject(valid.replace("rootObject = ", "rootObject = missing", 1), "missing")
    project.write_text(valid)
    generator = shutil.which("xcodegen")
    if generator:
        info_paths = [fixture / "Resources/Info.plist", fixture / "Helpers/VolumeBootDiskBroker/Info.plist"]
        info_before = [path.read_bytes() for path in info_paths]
        subprocess.run([generator, "generate", "--spec", str(fixture / "project.yml")], cwd=fixture, check=True, capture_output=True)
        assert info_before == [path.read_bytes() for path in info_paths], "XcodeGen modified maintained Info.plist files"
        subprocess.run(checker, check=True, capture_output=True)
        print("PASS: portable/XcodeGen project generation, preserved Info.plists, invalid arrays, and conflict rejection")
    else:
        print("PASS: portable project generation, invalid arrays, and conflict rejection (XcodeGen unavailable)")
