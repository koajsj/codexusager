#!/usr/bin/env python3
"""Generate the native app, WidgetKit extension and Claude bridge targets.

Only the Python standard library is used. The Swift package remains the
source of truth for UsageCore and its tests.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "CodexUsager.xcodeproj"
objects: dict[str, dict] = {}


class Ref(str):
    pass


def ref(name: str) -> Ref:
    return Ref(hashlib.sha1(name.encode()).hexdigest()[:24].upper())


def obj(key: str, kind: str, **values) -> Ref:
    identifier = ref(key)
    objects[identifier] = {"isa": kind, **values}
    return identifier


def file(path: str, file_type: str = "sourcecode.swift") -> Ref:
    return obj("file:" + path, "PBXFileReference", lastKnownFileType=file_type,
               path=path, sourceTree="<group>")


def build_file(name: str, file_ref: Ref | None = None, product_ref: Ref | None = None) -> Ref:
    values = {"fileRef": file_ref} if file_ref else {"productRef": product_ref}
    return obj("build:" + name, "PBXBuildFile", **values)


def phase(key: str, kind: str, files: list[Ref], **extra) -> Ref:
    return obj("phase:" + key, kind, buildActionMask=2147483647,
               files=files, runOnlyForDeploymentPostprocessing=0, **extra)


def configuration(name: str, target: str, settings: dict) -> Ref:
    return obj("config:" + target + ":" + name, "XCBuildConfiguration",
               buildSettings=settings, name=name)


def config_list(name: str, debug: Ref, release: Ref) -> Ref:
    return obj("configs:" + name, "XCConfigurationList",
               buildConfigurations=[debug, release], defaultConfigurationIsVisible=0,
               defaultConfigurationName="Release")


def render(value, depth=0) -> str:
    indent = "\t" * depth
    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "".join("\t" * (depth + 1) + render(v, depth + 1) + ",\n" for v in value) + indent + ")"
    if isinstance(value, dict):
        if not value:
            return "{}"
        return "{\n" + "".join("\t" * (depth + 1) + render(k) + " = " + render(v, depth + 1) + ";\n"
                              for k, v in value.items()) + indent + "}"
    return str(value)


app_paths = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Sources/CodexUsager").rglob("*.swift"))
app_refs = [file(p) for p in app_paths]
bridge_ref = file("Sources/ClaudeQuotaBridge/BridgeMain.swift")
widget_ref = file("Sources/CodexUsagerWidget/CodexUsagerWidget.swift")
shared_ref = file("Sources/UsageCore/WidgetShared.swift")
catalog_ref = file("Sources/CodexUsager/Resources/Localizable.xcstrings", "text.json.xcstrings")
config_refs = [file("Config/" + p, "text.plist.xml") for p in
               ("AppInfo.plist", "WidgetInfo.plist", "App.entitlements", "Widget.entitlements")]

app_product = obj("product:app", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex=0, path="CodexUsager.app", sourceTree="BUILT_PRODUCTS_DIR")
widget_product = obj("product:widget", "PBXFileReference", explicitFileType="wrapper.app-extension",
                     includeInIndex=0, path="CodexUsagerWidget.appex", sourceTree="BUILT_PRODUCTS_DIR")
bridge_product = obj("product:bridge", "PBXFileReference", explicitFileType="compiled.mach-o.executable",
                     includeInIndex=0, path="ClaudeQuotaBridge", sourceTree="BUILT_PRODUCTS_DIR")
products = obj("group:products", "PBXGroup", children=[app_product, widget_product, bridge_product],
               name="Products", sourceTree="<group>")
main_group = obj("group:main", "PBXGroup",
                 children=app_refs + [catalog_ref, widget_ref, shared_ref, bridge_ref] + config_refs + [products],
                 sourceTree="<group>")

app_sources = phase("app:sources", "PBXSourcesBuildPhase",
                    [build_file("app:" + p, r) for p, r in zip(app_paths, app_refs)])
widget_sources = phase("widget:sources", "PBXSourcesBuildPhase",
                       [build_file("widget:main", widget_ref), build_file("widget:shared", shared_ref)])
bridge_sources = phase("bridge:sources", "PBXSourcesBuildPhase", [build_file("bridge:main", bridge_ref)])
app_resources = phase("app:resources", "PBXResourcesBuildPhase", [build_file("app:catalog", catalog_ref)])
app_icon = obj("phase:app:icon", "PBXShellScriptBuildPhase",
               buildActionMask=2147483647, files=[], inputPaths=["$(SRCROOT)/Scripts/icon.swift"],
               outputPaths=["$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/AppIcon.icns"],
               runOnlyForDeploymentPostprocessing=0, shellPath="/bin/bash",
               shellScript='"$SRCROOT/Scripts/generate_icon.sh" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/AppIcon.icns"')
widget_resources = phase("widget:resources", "PBXResourcesBuildPhase", [])

package = obj("package:local", "XCLocalSwiftPackageReference", relativePath=".")
core_product = obj("package:core", "XCSwiftPackageProductDependency",
                   package=package, productName="UsageCore")
app_frameworks = phase("app:frameworks", "PBXFrameworksBuildPhase",
                       [build_file("app:core", product_ref=core_product)])
bridge_frameworks = phase("bridge:frameworks", "PBXFrameworksBuildPhase",
                          [build_file("bridge:core", product_ref=core_product)])
widget_frameworks = phase("widget:frameworks", "PBXFrameworksBuildPhase", [])
embed_widget = phase("app:widget", "PBXCopyFilesBuildPhase",
                     [build_file("app:embed-widget", widget_product)], dstPath="", dstSubfolderSpec=13,
                     name="Embed App Extensions")
embed_bridge = phase("app:bridge", "PBXCopyFilesBuildPhase",
                     [build_file("app:embed-bridge", bridge_product)], dstPath="", dstSubfolderSpec=6,
                     name="Embed Claude Bridge")

common = {
    "MACOSX_DEPLOYMENT_TARGET": "14.6",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "CODE_SIGN_STYLE": "Automatic",
    "USAGE_APP_GROUP": "$(DEVELOPMENT_TEAM).dev.codexusager.shared",
}
app_settings = {
    **common, "PRODUCT_BUNDLE_IDENTIFIER": "dev.codexusager.app",
    "PRODUCT_NAME": "CodexUsager", "INFOPLIST_FILE": "Config/AppInfo.plist",
    "CODE_SIGN_ENTITLEMENTS": "Config/App.entitlements",
    "GENERATE_INFOPLIST_FILE": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
widget_settings = {
    **common, "PRODUCT_BUNDLE_IDENTIFIER": "dev.codexusager.app.widget",
    "PRODUCT_NAME": "CodexUsagerWidget", "INFOPLIST_FILE": "Config/WidgetInfo.plist",
    "CODE_SIGN_ENTITLEMENTS": "Config/Widget.entitlements",
    "GENERATE_INFOPLIST_FILE": "NO", "APPLICATION_EXTENSION_API_ONLY": "YES",
    "SKIP_INSTALL": "YES",
}
bridge_settings = {
    **common, "PRODUCT_BUNDLE_IDENTIFIER": "dev.codexusager.app.bridge",
    "PRODUCT_NAME": "ClaudeQuotaBridge", "GENERATE_INFOPLIST_FILE": "YES",
    "SKIP_INSTALL": "YES",
}
project_settings = {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.6",
                    "CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "6.0"}

app_configs = config_list("app",
                          configuration("Debug", "app", {**app_settings, "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}),
                          configuration("Release", "app", {**app_settings, "SWIFT_OPTIMIZATION_LEVEL": "-O"}))
widget_configs = config_list("widget",
                             configuration("Debug", "widget", {**widget_settings, "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}),
                             configuration("Release", "widget", {**widget_settings, "SWIFT_OPTIMIZATION_LEVEL": "-O"}))
bridge_configs = config_list("bridge",
                             configuration("Debug", "bridge", {**bridge_settings, "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}),
                             configuration("Release", "bridge", {**bridge_settings, "SWIFT_OPTIMIZATION_LEVEL": "-O"}))
project_configs = config_list("project",
                              configuration("Debug", "project", {**project_settings, "DEBUG_INFORMATION_FORMAT": "dwarf"}),
                              configuration("Release", "project", {**project_settings, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}))

widget_target_id = ref("target:widget")
bridge_target_id = ref("target:bridge")
project_id = ref("project")
widget_proxy = obj("proxy:widget", "PBXContainerItemProxy", containerPortal=project_id,
                   proxyType=1, remoteGlobalIDString=widget_target_id, remoteInfo="CodexUsagerWidget")
bridge_proxy = obj("proxy:bridge", "PBXContainerItemProxy", containerPortal=project_id,
                   proxyType=1, remoteGlobalIDString=bridge_target_id, remoteInfo="ClaudeQuotaBridge")
widget_dependency = obj("dependency:widget", "PBXTargetDependency",
                        target=widget_target_id, targetProxy=widget_proxy)
bridge_dependency = obj("dependency:bridge", "PBXTargetDependency",
                        target=bridge_target_id, targetProxy=bridge_proxy)

app_target = obj("target:app", "PBXNativeTarget", buildConfigurationList=app_configs,
                 buildPhases=[app_sources, app_frameworks, app_resources, app_icon, embed_widget, embed_bridge],
                 buildRules=[], dependencies=[widget_dependency, bridge_dependency], name="CodexUsager",
                 packageProductDependencies=[core_product], productName="CodexUsager",
                 productReference=app_product, productType="com.apple.product-type.application")
widget_target = obj("target:widget", "PBXNativeTarget", buildConfigurationList=widget_configs,
                    buildPhases=[widget_sources, widget_frameworks, widget_resources],
                    buildRules=[], dependencies=[], name="CodexUsagerWidget",
                    productName="CodexUsagerWidget", productReference=widget_product,
                    productType="com.apple.product-type.app-extension")
bridge_target = obj("target:bridge", "PBXNativeTarget", buildConfigurationList=bridge_configs,
                    buildPhases=[bridge_sources, bridge_frameworks],
                    buildRules=[], dependencies=[], name="ClaudeQuotaBridge",
                    packageProductDependencies=[core_product], productName="ClaudeQuotaBridge",
                    productReference=bridge_product, productType="com.apple.product-type.tool")
project = obj("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES",
              "LastUpgradeCheck": "1530", "TargetAttributes": {
                  app_target: {"ProvisioningStyle": "Automatic"},
                  widget_target: {"ProvisioningStyle": "Automatic"},
                  bridge_target: {"ProvisioningStyle": "Automatic"}}},
              buildConfigurationList=project_configs, compatibilityVersion="Xcode 15.3",
              developmentRegion="zh-Hans", hasScannedForEncodings=0,
              knownRegions=["zh-Hans", "en"], mainGroup=main_group,
              packageReferences=[package], productRefGroup=products,
              projectDirPath="", projectRoot="", targets=[app_target, widget_target, bridge_target])

PROJECT.mkdir(exist_ok=True)
body = "// !$*UTF8*$!\n" + render({
    "archiveVersion": 1, "classes": {}, "objectVersion": 60,
    "objects": objects, "rootObject": project
}) + "\n"
(PROJECT / "project.pbxproj").write_text(body, encoding="utf-8")
