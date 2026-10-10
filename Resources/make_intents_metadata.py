#!/usr/bin/env python3
"""Writes Metadata.appintents for the widget extension.

Xcode generates this with appintentsmetadataprocessor, which the Command Line Tools
don't include. Without it the system doesn't know the widget's App Intents, so buttons
on the widget do nothing. The format below mirrors what Xcode emits for intents with
String parameters (checked against Xcode 17-built widgets).

Usage: make_intents_metadata.py <path/to/Widget.appex>
"""
import json
import os
import re
import subprocess
import sys

MODULE = "PlannerWidget"

# Keep in sync with Widget/WidgetIntents.swift.
INTENTS = {
    "ToggleTaskIntent": {"title": "完成任务", "params": [("taskID", "任务")]},
    "ToggleSubtaskIntent": {"title": "完成子任务", "params": [("taskID", "任务"), ("subtaskID", "子任务")]},
}

STRING_TYPE = {"primitive": {"wrapper": {"typeIdentifier": 0}}}
TOOLS_VERSION = "17E202"


def mangled_names(binary):
    """Swift mangled type names, read from the nominal type descriptors (…VMn)."""
    out = subprocess.run(["nm", binary], capture_output=True, text=True, check=True).stdout
    names = {}
    for sym in re.findall(r"\$s(\S+)VMn\b", out):
        for intent in INTENTS:
            if sym.endswith(intent) and sym.startswith(f"{len(MODULE)}{MODULE}"):
                names[intent] = sym + "V"
    missing = set(INTENTS) - set(names)
    if missing:
        sys.exit(f"make_intents_metadata: no type descriptor for {sorted(missing)} in {binary}")
    return names


def parameter(name, title):
    return {
        "capabilities": 0,
        "dynamicOptionsSupport": 0,
        "inputConnectionBehavior": 0,
        "isInput": False,
        "isOptional": False,
        "name": name,
        "resolvableInputTypes": [{"kindValue": 0, "valueType": STRING_TYPE}],
        "title": {"alternatives": [], "key": title},
        "typeSpecificMetadata": [],
        "valueType": STRING_TYPE,
    }


def action(identifier, spec, mangled):
    return {
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": f"{MODULE}.{identifier}",
        "identifier": identifier,
        "isAuthPolExplicit": False,
        "isDiscoverable": False,
        "mangledTypeName": mangled,
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": mangled,
        "openAppWhenRun": False,
        "outputFlags": 0,
        "parameters": [parameter(n, t) for n, t in spec["params"]],
        "presentationStyle": 0,
        "requiredCapabilities": [],
        "supportedModes": 1,
        "systemProtocolMetadata": [],
        "systemProtocolMetadataV2": [],
        "systemProtocols": [],
        "title": {"alternatives": [], "key": spec["title"]},
        "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": False},
    }


def main():
    appex = sys.argv[1]
    binary = os.path.join(appex, "Contents", "MacOS", MODULE)
    names = mangled_names(binary)
    data = {
        "actions": {i: action(i, spec, names[i]) for i, spec in INTENTS.items()},
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcuts": [],
        "entities": {},
        "enums": [],
        "generator": {"name": "xcode-tools", "version": TOOLS_VERSION},
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 14,
        "version": 1,
    }
    out = os.path.join(appex, "Contents", "Resources", "Metadata.appintents")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "extract.actionsdata"), "w") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(out, "version.json"), "w") as f:
        json.dump({"toolsVersion": TOOLS_VERSION, "version": "3.0"}, f, indent=2)
    for i in INTENTS:
        print(f"  {i}: {names[i]}")


if __name__ == "__main__":
    main()
