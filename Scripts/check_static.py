#!/usr/bin/env python3
"""Read-only static gates. Does not compile Swift, run tests or contact providers."""
import ast
import json
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def check():
    subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
    for path in (ROOT / "Scripts").rglob("*.py"):
        ast.parse(path.read_text(), filename=str(path))
    for path in (ROOT / "Scripts").glob("*.sh"):
        subprocess.run(["bash", "-n", str(path)], check=True)
    for path in (ROOT / "Config").iterdir():
        if path.suffix in {".plist", ".entitlements"}:
            plistlib.loads(path.read_bytes())
    json.loads((ROOT / "Sources/CodexUsager/Resources/Localizable.xcstrings").read_text())
    project = ROOT / "CodexUsager.xcodeproj/project.pbxproj"
    output = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)])
    objects = json.loads(output)["objects"]
    for key, value in objects.items():
        if value.get("isa") == "PBXFileReference" and value.get("sourceTree") == "<group>":
            if not (ROOT / value["path"]).is_file():
                raise ValueError(f"Missing project file: {value['path']}")
        for field in ("fileRef", "productRef", "buildConfigurationList", "mainGroup", "productReference", "target", "targetProxy", "containerPortal"):
            if field in value and value[field] not in objects:
                raise ValueError(f"Invalid project reference: {key}.{field}")
        for field in ("children", "files", "buildPhases", "buildConfigurations", "targets", "dependencies", "packageReferences", "packageProductDependencies"):
            if any(reference not in objects for reference in value.get(field, [])):
                raise ValueError(f"Invalid project reference list: {key}.{field}")
    for path in (ROOT / ".github/workflows").glob("*.yml"):
        subprocess.run(["ruby", "-r", "yaml", "-e", "YAML.safe_load(File.read(ARGV[0])); puts ARGV[0]", str(path)], check=True)
    # Reject concrete secrets/private home paths, not legitimate API field names or synthetic tokens.
    secret = re.compile(r"(?:sk-(?:proj-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|" + "/" + r"Users/(?!Shared/)[^/\s]+/)")
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
    for name in files:
        path = ROOT / name
        if not path.is_file() or path.suffix.lower() in {".png", ".icns"}:
            continue
        data = path.read_bytes()
        if b"\0" not in data and secret.search(data.decode("utf-8", errors="replace")):
            raise ValueError(f"Possible credential/private path: {name} (review required)")
    print("Static configuration, references and sensitive-pattern checks passed. No build or tests executed.")


if __name__ == "__main__":
    check()
