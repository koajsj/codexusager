#!/usr/bin/env python3
"""Validate release settings or a built bundle without launching or signing the App."""
import argparse
import json
import plistlib
import re
import sys
import subprocess
from pathlib import Path


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def validate_tag(tag, version, mode):
    if tag is None:
        return
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)(-preview)?", tag)
    require(match is not None, "Tag 必须为 vMAJOR.MINOR.PATCH 或带 -preview 后缀。")
    require(match.group(1) == version, "Tag 与 App Marketing Version 不一致。")
    require(mode != "unsigned-preview" or match.group(2) is not None,
            "未签名构建只能发布 -preview；正式版本需要开发团队、签名和独立的公证验证。")


def validate_group(app_group, widget_group, mode, team=""):
    require(isinstance(app_group, str) and app_group == widget_group, "App / Widget 的 App Group 必须相同。")
    require("$(" not in app_group, "App Group 含有未展开的 Build Setting。")
    if mode == "signed":
        require(re.fullmatch(r"[A-Z0-9]{10}", team) is not None, "正式签名需要有效的 10 位 DEVELOPMENT_TEAM。")
        require(app_group == f"group.{team}.dev.codexusager.shared", "正式 App Group 与开发团队不匹配。")
    else:
        require(re.fullmatch(r"group\.(?:[A-Z0-9]{10})?\.dev\.codexusager\.shared", app_group) is not None,
                "Preview App Group 格式不符合工程配置。")


def validate_settings(entries, mode, tag=None):
    by_target = {entry["target"]: entry["buildSettings"] for entry in entries}
    require("CodexUsager" in by_target and "CodexUsagerWidget" in by_target, "缺少 App 或 Widget Target。")
    app, widget = by_target["CodexUsager"], by_target["CodexUsagerWidget"]
    for settings, bundle_id, wrapper in [(app, "dev.codexusager.app", "app"),
                                          (widget, "dev.codexusager.app.widget", "appex")]:
        require(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == bundle_id, "Bundle Identifier 不正确。")
        require(settings.get("WRAPPER_EXTENSION") == wrapper, "发布入口必须为 Application / Widget Bundle。")
        require(settings.get("CODE_SIGN_ENTITLEMENTS"), "不得删除 App Group Entitlements 配置。")
        if mode == "signed":
            require(settings.get("CODE_SIGNING_ALLOWED") != "NO", "正式发布不得关闭签名。")
            require(settings.get("DEVELOPMENT_TEAM") == app.get("DEVELOPMENT_TEAM"), "App / Widget 开发团队不同。")
    require(app.get("MARKETING_VERSION") == widget.get("MARKETING_VERSION"), "App / Widget 版本不同。")
    require(app.get("CURRENT_PROJECT_VERSION") == widget.get("CURRENT_PROJECT_VERSION"), "App / Widget 构建号不同。")
    validate_group(app.get("USAGE_APP_GROUP"), widget.get("USAGE_APP_GROUP"), mode, app.get("DEVELOPMENT_TEAM", ""))
    validate_tag(tag, app.get("MARKETING_VERSION"), mode)


def validate_bundle(path, mode, tag=None, team=""):
    app = Path(path)
    widget = app / "Contents/PlugIns/CodexUsagerWidget.appex"
    require(app.name == "CodexUsager.app", "App 名称必须为 CodexUsager.app。")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    with (widget / "Contents/Info.plist").open("rb") as handle:
        widget_info = plistlib.load(handle)
    require(info.get("CFBundlePackageType") == "APPL", "产物必须为 macOS Application。")
    require(info.get("CFBundleIdentifier") == "dev.codexusager.app", "App Bundle Identifier 不正确。")
    require(widget_info.get("CFBundleIdentifier") == "dev.codexusager.app.widget", "Widget Bundle Identifier 不正确。")
    for key in ["CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion"]:
        require(info.get(key) is not None and info[key] == widget_info.get(key), f"App / Widget {key} 不同或缺失。")
    validate_group(info.get("UsageAppGroup"), widget_info.get("UsageAppGroup"), mode, team)
    validate_tag(tag, info.get("CFBundleShortVersionString"), mode)
    for binary in [app / "Contents/MacOS/CodexUsager", app / "Contents/MacOS/ClaudeQuotaBridge",
                   widget / "Contents/MacOS/CodexUsagerWidget"]:
        require(binary.is_file(), "App 缺少主程序、Claude Bridge 或 Widget 可执行文件。")
    if mode == "signed":
        for bundle in [app, widget]:
            signature = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(bundle)],
                                       capture_output=True, check=False)
            require(signature.returncode == 0 and f"TeamIdentifier={team}" in signature.stderr.decode("utf-8", errors="replace").splitlines(),
                    "App / Widget 的实际签名团队与配置不一致。")
            result = subprocess.run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", str(bundle)],
                                    capture_output=True, check=False)
            require(result.returncode == 0, "无法读取 App / Widget 的实际签名 Entitlements。")
            try:
                entitlements = plistlib.loads(result.stdout)
            except (plistlib.InvalidFileException, ValueError) as error:
                raise ValidationError("App / Widget 的实际签名 Entitlements 不可读。") from error
            require(entitlements.get("com.apple.security.application-groups") == [info["UsageAppGroup"]],
                    "实际签名缺少正确的 App Group Entitlement。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--settings", type=Path, help="xcodebuild -showBuildSettings -json 输出")
    source.add_argument("--app", type=Path)
    parser.add_argument("--mode", choices=["unsigned-preview", "signed"], required=True)
    parser.add_argument("--tag")
    parser.add_argument("--team", default="")
    args = parser.parse_args()
    try:
        if args.settings:
            validate_settings(json.loads(args.settings.read_text()), args.mode, args.tag)
        else:
            validate_bundle(args.app, args.mode, args.tag, args.team)
    except (ValidationError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"发布配置检查失败：{error}", file=sys.stderr)
        return 1
    if args.mode == "unsigned-preview":
        print("未签名 Preview：Widget / App Group、Gatekeeper 与安装启动尚未验证。", file=sys.stderr)
    else:
        print("签名配置检查完成；实际签名、共享容器与公证仍须独立验证。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
