#!/usr/bin/env python3
"""
Simple Lua syntax checker for GMod addons
Usage: python check_syntax.py
"""

import os
import re
import sys

def check_lua_syntax(content):
    """
    Basic Lua syntax checker.
    This is a simple checker that catches common errors like:
    - Mismatched quotes
    - Mismatched brackets/parentheses
    - Unfinished strings
    """
    errors = []
    lines = content.split('\n')

    # Track brackets, parentheses, and braces
    stack = []
    in_string = None  # None, '"', "'"
    escape_next = False
    in_multiline_comment = False
    in_multiline_string = False

    for i, line in enumerate(lines, 1):
        j = 0
        while j < len(line):
            char = line[j]

            # Handle multiline comments
            if not in_string and not in_multiline_string:
                if in_multiline_comment:
                    if char == ']' and j + 1 < len(line) and line[j+1] == ']':
                        in_multiline_comment = False
                        j += 2
                        continue
                    else:
                        j += 1
                        continue  # Skip all characters in multiline comment
                elif char == '-' and j + 1 < len(line) and line[j+1] == '-':
                    if j + 3 < len(line) and line[j+2] == '[' and line[j+3] == '[':
                        in_multiline_comment = True
                        j += 4
                        continue
                    else:
                        break  # Single line comment

            # Handle multiline strings
            if not in_multiline_comment:
                if in_multiline_string:
                    if char == ']' and j + 1 < len(line) and line[j+1] == ']':
                        in_multiline_string = False
                        j += 2
                        continue
                    else:
                        j += 1
                        continue  # Skip all characters in multiline string
                elif char == '[' and j + 1 < len(line) and line[j+1] == '[':
                    in_multiline_string = True
                    j += 2
                    continue

            # Handle escape sequences in strings
            if escape_next:
                escape_next = False
                j += 1
                continue

            # Handle string literals
            if in_string:
                if char == '\\':
                    escape_next = True
                elif char == in_string:
                    in_string = None
                j += 1
                continue
            elif char == '"' or char == "'":
                in_string = char
                j += 1
                continue

            # Track brackets/parentheses (not square brackets - used for table indexing)
            if char in '({':
                stack.append((char, i, j + 1))
            elif char in ')}':
                if not stack:
                    errors.append(f"Line {i}: Unexpected '{char}'")
                else:
                    expected = {'(': ')', '{': '}'}[stack[-1][0]]
                    if char != expected:
                        errors.append(f"Line {i}: Expected '{expected}' but got '{char}'")
                    else:
                        stack.pop()

            j += 1

    # Check for unclosed structures
    if in_string:
        errors.append("Unclosed string")
    if in_multiline_string:
        errors.append("Unclosed multiline string [[...]]")
    if in_multiline_comment:
        errors.append("Unclosed multiline comment --[[...]]")

    for char, line, col in stack:
        errors.append(f"Unclosed '{char}' (started at line {line})")

    return errors


def main():
    # List of main Lua files to check
    files_to_check = [
        "lua/autorun/nai_npc_passengers.lua",
        "lua/nai_npc_passengers/main.lua",
        "lua/nai_npc_passengers/ui.lua",
        "lua/nai_npc_passengers/settings.lua",
        "lua/nai_npc_passengers/lvs_driver.lua",
        "lua/nai_npc_passengers/lvs_turret.lua",
        "lua/nai_npc_passengers/vj_base.lua",
    ]

    script_dir = os.path.dirname(os.path.abspath(__file__))
    addon_dir = script_dir

    print(f"Checking Lua files in: {addon_dir}")
    print()

    error_count = 0
    file_count = 0

    for relative_path in files_to_check:
        file_path = os.path.join(addon_dir, relative_path.replace('/', os.sep))

        if not os.path.exists(file_path):
            print(f"[FAIL] {relative_path} (file not found)")
            error_count += 1
            continue

        file_count += 1

        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            errors = check_lua_syntax(content)

            if errors:
                print(f"[FAIL] {relative_path}")
                for error in errors:
                    print(f"  {error}")
                error_count += 1
            else:
                print(f"[OK]   {relative_path}")

        except Exception as e:
            print(f"[FAIL] {relative_path}")
            print(f"  Error reading file: {e}")
            error_count += 1

    print()
    print(f"Checked {file_count} files")
    print(f"Errors found: {error_count}")

    if error_count > 0:
        sys.exit(1)
    else:
        print("All files passed syntax check!")
        sys.exit(0)


if __name__ == "__main__":
    main()
