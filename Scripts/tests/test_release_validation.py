import importlib.util
from pathlib import Path
import tempfile
import unittest
import plistlib

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).resolve().parents[1] / "validate_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def settings(team="", widget_group=None):
    group = f"group.{team}.dev.codexusager.shared"
    common = dict(MARKETING_VERSION="1.0.1", CURRENT_PROJECT_VERSION="3", DEVELOPMENT_TEAM=team,
                  CODE_SIGNING_ALLOWED="YES", CODE_SIGN_ENTITLEMENTS="Config/App.entitlements", USAGE_APP_GROUP=group)
    return [dict(target="CodexUsager", buildSettings=dict(common, PRODUCT_BUNDLE_IDENTIFIER="dev.codexusager.app", WRAPPER_EXTENSION="app")),
            dict(target="CodexUsagerWidget", buildSettings=dict(common, PRODUCT_BUNDLE_IDENTIFIER="dev.codexusager.app.widget",
                 WRAPPER_EXTENSION="appex", USAGE_APP_GROUP=widget_group or group))]


class ReleaseValidationTests(unittest.TestCase):
    def test_unsigned_preview_never_passes_as_formal_release(self):
        release.validate_settings(settings(), "unsigned-preview", "v1.0.1-preview")
        with self.assertRaises(release.ValidationError):
            release.validate_settings(settings(), "unsigned-preview", "v1.0.1")

    def test_signed_requires_team_and_matching_group(self):
        with self.assertRaises(release.ValidationError):
            release.validate_settings(settings(), "signed", "v1.0.1")
        release.validate_settings(settings("AB123CD456"), "signed", "v1.0.1")
        with self.assertRaises(release.ValidationError):
            release.validate_settings(settings("AB123CD456", "group.ZZ123CD456.dev.codexusager.shared"), "signed")

    def test_disabled_signing_and_mismatched_versions_are_rejected(self):
        entries = settings("AB123CD456")
        entries[1]["buildSettings"]["CODE_SIGNING_ALLOWED"] = "NO"
        with self.assertRaises(release.ValidationError):
            release.validate_settings(entries, "signed")
        with self.assertRaises(release.ValidationError):
            release.validate_settings(settings(), "unsigned-preview", "v2.0.0-preview")

    def test_bundle_requires_embedded_widget_bridge_and_same_group(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "CodexUsager.app"
            widget = app / "Contents/PlugIns/CodexUsagerWidget.appex"
            for root in [app, widget]:
                (root / "Contents/MacOS").mkdir(parents=True)
            info = dict(CFBundleIdentifier="dev.codexusager.app", CFBundlePackageType="APPL", CFBundleShortVersionString="1.0.1",
                        CFBundleVersion="3", LSMinimumSystemVersion="26.0", UsageAppGroup="group..dev.codexusager.shared")
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            widget_info = dict(info, CFBundleIdentifier="dev.codexusager.app.widget", CFBundlePackageType="XPC!")
            (widget / "Contents/Info.plist").write_bytes(plistlib.dumps(widget_info))
            (app / "Contents/MacOS/CodexUsager").touch()
            (widget / "Contents/MacOS/CodexUsagerWidget").touch()
            with self.assertRaises(release.ValidationError):
                release.validate_bundle(app, "unsigned-preview")
            (app / "Contents/MacOS/ClaudeQuotaBridge").touch()
            release.validate_bundle(app, "unsigned-preview", "v1.0.1-preview")
            widget_info["UsageAppGroup"] = "group.OTHER.shared"
            (widget / "Contents/Info.plist").write_bytes(plistlib.dumps(widget_info))
            with self.assertRaises(release.ValidationError):
                release.validate_bundle(app, "unsigned-preview")


if __name__ == "__main__":
    unittest.main()
