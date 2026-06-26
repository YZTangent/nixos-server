"""Helpers for manipulating secrets/.sops.yaml programmatically."""
from __future__ import annotations

import pathlib
import re

import yaml


def find_role_key_group(sops_file: pathlib.Path, role: str) -> int:
    """Return the index into creation_rules for the rule matching `secrets/<role>-.*\\.yaml$`.

    Raises ValueError if no rule matches.
    """
    data = yaml.safe_load(sops_file.read_text())
    rules = data.get("creation_rules", [])
    expected_pattern = f"secrets/{role}-.*\\.yaml$"
    for i, rule in enumerate(rules):
        if rule.get("path_regex") == expected_pattern:
            return i
    raise ValueError(f"no creation_rule matched role {role!r}")


def add_age_key(
    sops_file: pathlib.Path,
    role: str,
    anchor_name: str,
    public_key: str,
) -> None:
    """Add an age public key to the key_group for `role` in .sops.yaml.

    - Adds `- &<anchor_name> <public_key>` to the top-level `keys` list (if not already present).
    - Appends `*<anchor_name>` to the `age` list under the role's key_group (if not already present).
    - Writes the file back, preserving existing YAML anchors and aliases via text manipulation.
    """
    lines = sops_file.read_text().rstrip("\n").split("\n")

    anchor = f"&{anchor_name}"
    alias = f"*{anchor_name}"

    # 1. Add anchor to top-level keys list if not already present
    if not any(anchor in line for line in lines):
        lines = _insert_anchor(lines, anchor_name, public_key)

    # 2. Add alias to role's age list if not already present
    rule_idx = _find_role_rule_line(lines, role)
    if not _alias_in_role_age(lines, rule_idx, alias):
        lines = _insert_alias(lines, rule_idx, alias)

    sops_file.write_text("\n".join(lines) + "\n")


# --- Internal helpers (text-based, preserve anchors) ---


def _find_role_rule_line(lines: list[str], role: str) -> int:
    """Return the line index of the creation_rule for the given role."""
    expected_pattern = f"secrets/{role}-.*\\.yaml$"
    for i, line in enumerate(lines):
        if expected_pattern in line and "path_regex" in line:
            return i
    raise ValueError(f"no creation_rule matched role {role!r}")


def _insert_anchor(
    lines: list[str], anchor_name: str, public_key: str
) -> list[str]:
    """Insert '- &<anchor_name> <public_key>' into the keys: section."""
    keys_line_idx = None
    for i, line in enumerate(lines):
        if re.match(r"^keys:\s*$", line) or re.match(r"^keys:\s+\S", line):
            keys_line_idx = i
            break

    if keys_line_idx is None:
        return ["keys:", f"  - &{anchor_name} {public_key}", ""] + lines

    # Find insertion point: after last entry/comment in keys list,
    # before the next top-level key or blank-line-separated section.
    insert_idx = keys_line_idx + 1
    last_entry_idx = keys_line_idx

    while insert_idx < len(lines):
        line = lines[insert_idx]
        if line.strip() == "":
            break
        if not line[0].isspace():
            break
        if line.strip().startswith("-") or line.strip().startswith("#"):
            last_entry_idx = insert_idx
        insert_idx += 1

    insert_at = last_entry_idx + 1
    new_line = f"  - &{anchor_name} {public_key}"
    return lines[:insert_at] + [new_line] + lines[insert_at:]


def _alias_in_role_age(
    lines: list[str], rule_line_idx: int, alias: str
) -> bool:
    """Check if alias already exists in the age list under the given creation_rule."""
    rule_indent = len(lines[rule_line_idx]) - len(lines[rule_line_idx].lstrip())

    i = rule_line_idx + 1
    while i < len(lines):
        line = lines[i]
        if line.strip() == "":
            i += 1
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= rule_indent:
            break
        if alias in line:
            return True
        i += 1

    return False


def _insert_alias(
    lines: list[str], rule_line_idx: int, alias: str
) -> list[str]:
    """Insert '- *<alias>' into the age list under the given creation_rule."""
    rule_indent = len(lines[rule_line_idx]) - len(lines[rule_line_idx].lstrip())

    age_line_idx = None
    age_indent = 0

    i = rule_line_idx + 1
    while i < len(lines):
        line = lines[i]
        if line.strip() == "":
            i += 1
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= rule_indent:
            break
        if re.match(r"^\s*-\s*age:", line):
            age_line_idx = i
            age_indent = indent
            break
        i += 1

    if age_line_idx is None:
        raise ValueError("no age key found under role's creation_rule")

    age_line = lines[age_line_idx]

    # Case 1: age: [] (empty flow list) → convert to block style
    if "[]" in age_line:
        new_age_line = age_line.replace("[]", "").rstrip()
        # Items indent: age_indent + 4 (for '- ' prefix + one nesting level)
        item_indent = " " * (age_indent + 4)
        new_item = f"{item_indent}- {alias}"
        return lines[:age_line_idx] + [new_age_line, new_item] + lines[age_line_idx + 1 :]

    # Case 2: age: with existing block items → append after last item
    item_indent = " " * (age_indent + 4)
    last_item_idx = age_line_idx

    j = age_line_idx + 1
    while j < len(lines):
        line = lines[j]
        if line.strip() == "":
            break
        indent = len(line) - len(line.lstrip())
        if indent <= age_indent:
            break
        if line.strip().startswith("-"):
            last_item_idx = j
        j += 1

    insert_at = last_item_idx + 1
    new_item = f"{item_indent}- {alias}"
    return lines[:insert_at] + [new_item] + lines[insert_at:]
