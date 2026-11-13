"""Validate project references, test registration and required iOS privacy keys."""
import re
import struct
import xml.etree.ElementTree as ET
from pathlib import Path

project_path = Path(__file__).resolve().parents[1]
source = (project_path / "FinFlow.xcodeproj/project.pbxproj").read_text()
tokens = re.findall(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', source, flags=re.S)
tokens = [token for token in tokens if not token.startswith(("/*", "//"))]
index = 0


def parse_value():
    global index
    token = tokens[index]
    index += 1
    if token == "{":
        result = {}
        while tokens[index] != "}":
            key = tokens[index]
            index += 1
            assert tokens[index] == "="
            index += 1
            assert key not in result, f"Duplicate project key: {key}"
            result[key] = parse_value()
            assert tokens[index] == ";"
            index += 1
        index += 1
        return result
    if token == "(":
        result = []
        while tokens[index] != ")":
            result.append(parse_value())
            if tokens[index] == ",":
                index += 1
        index += 1
        return result
    return token.strip('"')


project = parse_value()
assert index == len(tokens)
objects = project["objects"]
for key, obj in objects.items():
    for field in ["children", "files", "buildPhases", "buildConfigurations", "targets", "dependencies"]:
        refs = obj.get(field, [])
        assert len(refs) == len(set(refs)), (key, field, "duplicate references")
        for ref in refs:
            assert ref in objects, (key, field, ref)
    for field in ["fileRef", "productReference", "buildConfigurationList", "target", "targetProxy"]:
        if field in obj:
            assert obj[field] in objects, (key, field, obj[field])

scheme = ET.parse(project_path / "FinFlow.xcodeproj/xcshareddata/xcschemes/FinFlow.xcscheme")
assert len(scheme.findall(".//TestableReference")) == 2
registered_targets = set(objects[project["rootObject"]]["targets"])
for test in scheme.findall(".//TestableReference/BuildableReference"):
    assert test.attrib["BlueprintIdentifier"] in registered_targets, "Test target not registered in project"
source_paths = {}


def walk_group(identifier, base):
    obj = objects[identifier]
    if obj.get("isa") == "PBXGroup":
        directory = base / obj.get("path", "")
        for child in obj.get("children", []):
            walk_group(child, directory)
    elif obj.get("isa") == "PBXFileReference" and obj.get("sourceTree") == "<group>":
        source_paths[identifier] = base / obj["path"]


walk_group(objects[project["rootObject"]]["mainGroup"], project_path)
for target in registered_targets:
    for phase in objects[target]["buildPhases"]:
        if objects[phase]["isa"] == "PBXSourcesBuildPhase":
            for build in objects[phase]["files"]:
                ref = objects[build]["fileRef"]
                assert ref in source_paths, f"Unreachable source group: {ref}"
                assert source_paths[ref].is_file(), source_paths[ref]
icon = (project_path / "FinFlow/Assets.xcassets/AppIcon.appiconset/FinFlowIcon.png").read_bytes()
assert icon[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", icon[16:24]) == (1024, 1024)
for obj in objects.values():
    settings = obj.get("buildSettings", {})
    if settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "com.finflow.ios":
        assert settings["INFOPLIST_KEY_NSFaceIDUsageDescription"]
        if obj.get("name") == "Debug":
            assert settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] == "DEBUG"

print(f"Project valid: {len(objects)} objects, unit/UI tests, Face ID usage string, 1024px icon.")
