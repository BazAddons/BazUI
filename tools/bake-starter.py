#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Bakes the layout /baz export left in the saved variables into
Core/StarterProfile.lua.

In game: arrange everything, type /baz export, then /reload so the client
writes the saved variables to disk. Then:

    tools/bake-starter.py              the Forever client's saved variables
    tools/bake-starter.py <BazUI.lua>  a particular SavedVariables/BazUI.lua

The export is already Lua. Only the running client can turn positions into
screen anchors, so it does that part; this lifts the text out of the saved
variables and puts the file's header back on, keeping whatever the header
says except the line naming the screen it was arranged on.

Starter values only ever reach a profile section that does not exist yet,
so baking a new layout never changes anybody's own settings.
"""

import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "Core", "StarterProfile.lua")
DEFAULT_GLOB = ("/Applications/World of Warcraft/_classic_beta_/WTF/Account/"
                "*/SavedVariables/BazUI.lua")
ARRANGED = "-- Arranged on a "


class LuaReader:
    """Reads the subset of Lua the client writes saved variables in:
    `name = value` statements, tables of `[key] = value` and array entries
    (each followed by a `-- [n]` comment), strings, numbers and booleans."""

    ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "a": "\a", "b": "\b",
               "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'",
               "\n": "\n"}

    def __init__(self, text):
        self.s, self.i = text, 0

    def fail(self, why):
        line = self.s.count("\n", 0, self.i) + 1
        raise ValueError(f"line {line}: {why}")

    def skip(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("--[[", self.i):
                end = s.find("]]", self.i)
                self.i = len(s) if end < 0 else end + 2
            elif s.startswith("--", self.i):
                end = s.find("\n", self.i)
                self.i = len(s) if end < 0 else end + 1
            else:
                return

    def expect(self, ch):
        self.skip()
        if not self.s.startswith(ch, self.i):
            self.fail(f"expected {ch!r}")
        self.i += len(ch)

    def string(self):
        quote = self.s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= len(self.s):
                self.fail("unfinished string")
            c = self.s[self.i]
            if c == quote:
                self.i += 1
                return "".join(out)
            if c == "\\":
                nxt = self.s[self.i + 1]
                if nxt.isdigit():
                    j = self.i + 1
                    while j < self.i + 4 and self.s[j].isdigit():
                        j += 1
                    out.append(chr(int(self.s[self.i + 1:j])))
                    self.i = j
                    continue
                if nxt not in self.ESCAPES:
                    self.fail(f"unknown escape \\{nxt}")
                out.append(self.ESCAPES[nxt])
                self.i += 2
                continue
            out.append(c)
            self.i += 1

    def name(self):
        j = self.i
        while j < len(self.s) and (self.s[j].isalnum() or self.s[j] == "_"):
            j += 1
        if j == self.i:
            self.fail("expected a name")
        token, self.i = self.s[self.i:j], j
        return token

    def word(self):
        j = self.i
        while j < len(self.s) and (self.s[j].isalnum() or self.s[j] in "_.-+"):
            j += 1
        token, self.i = self.s[self.i:j], j
        if token == "true":
            return True
        if token == "false":
            return False
        if token == "nil":
            return None
        try:
            return int(token)
        except ValueError:
            pass
        try:
            return float(token)
        except ValueError:
            self.fail(f"unexpected {token!r}")

    def value(self):
        self.skip()
        c = self.s[self.i:self.i + 1]
        if c == "{":
            return self.table()
        if c in ('"', "'"):
            return self.string()
        return self.word()

    def table(self):
        self.expect("{")
        result, index = {}, 1
        while True:
            self.skip()
            if self.s.startswith("}", self.i):
                self.i += 1
                return result
            if self.s.startswith("[", self.i):
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                result[key] = self.value()
            else:
                result[index] = self.value()
                index += 1
            self.skip()
            if self.s[self.i:self.i + 1] in (",", ";"):
                self.i += 1

    def statements(self):
        found = {}
        while True:
            self.skip()
            if self.i >= len(self.s):
                return found
            name = self.name()
            self.expect("=")
            found[name] = self.value()


def find_saved_variables(argv):
    if len(argv) > 1:
        return argv[1]
    candidates = glob.glob(DEFAULT_GLOB)
    if not candidates:
        sys.exit(f"bake-starter: no saved variables at {DEFAULT_GLOB}")
    # The most recently written, which is the one /reload just put there.
    return max(candidates, key=os.path.getmtime)


def main(argv):
    path = find_saved_variables(argv)
    with open(path, encoding="utf-8") as f:
        db = LuaReader(f.read()).statements().get("BazUIDB") or {}

    text = db.get("starterExport")
    if not isinstance(text, str) or not text.startswith("BazUI.StarterProfile = {"):
        sys.exit(f"bake-starter: {path} holds no export. In game: /baz export, "
                 "then /reload, then run this again.")

    screen = db.get("starterExportScreen") or {}
    width, height = screen.get("width"), screen.get("height")
    when = screen.get("when") or "an unknown date"
    size = (f"{round(width)} x {round(height)}"
            if isinstance(width, (int, float)) and isinstance(height, (int, float))
            else "an unknown")
    arranged = f"{ARRANGED}{size} screen, {when}."

    # Everything above the table is the header. It is kept as it stands,
    # hand edits and all, with only the arranged-on line brought up to date.
    with open(TARGET, encoding="utf-8") as f:
        current = f.read()
    start = current.find("BazUI.StarterProfile = {")
    if start < 0:
        sys.exit(f"bake-starter: {TARGET} has no BazUI.StarterProfile table")
    header = current[:start].splitlines()
    replaced = False
    for n, line in enumerate(header):
        if line.startswith(ARRANGED):
            header[n], replaced = arranged, True
    if not replaced:
        rule = max(n for n, line in enumerate(header) if line.startswith("-----"))
        header.insert(rule, arranged)

    baked = "\n".join(header) + "\n" + text.rstrip("\n") + "\n"
    with open(TARGET, "w", encoding="utf-8") as f:
        f.write(baked)

    print(f"baked {os.path.relpath(TARGET, ROOT)} from {path}")
    print(f"  {arranged[3:]}")


if __name__ == "__main__":
    main(sys.argv)
