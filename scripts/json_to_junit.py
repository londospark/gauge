#!/usr/bin/env python3
"""Convert an Odin test JSON report to JUnit XML.

Odin writes a structured report when `odin test` is given
`-define:ODIN_TEST_JSON_REPORT=<file>`:
    {"total": N, "success": M, "duration": ns,
     "packages": {"lexer": [{"name": "...", "success": true}, ...]}}

The GitHub test-reporting ecosystem consumes JUnit XML, so this bridges the
two. It is a CI helper, not part of the compiler.

Usage: json_to_junit.py <report.json>
"""

import json
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <report.json>", file=sys.stderr)
        return 2

    with open(sys.argv[1]) as f:
        report = json.load(f)

    total = report.get("total", 0)
    success = report.get("success", 0)

    suites = ET.Element("testsuites", {
        "tests": str(total),
        "failures": str(total - success),
    })

    for pkg, tests in report.get("packages", {}).items():
        failed = sum(1 for t in tests if not t["success"])
        suite = ET.SubElement(suites, "testsuite", {
            "name": pkg,
            "tests": str(len(tests)),
            "failures": str(failed),
        })
        for test in tests:
            case = ET.SubElement(suite, "testcase", {
                "name": test["name"],
                "classname": pkg,
            })
            if not test["success"]:
                ET.SubElement(case, "failure", {"message": "test failed"})

    ET.indent(suites)
    ET.ElementTree(suites).write(sys.stdout, encoding="unicode", xml_declaration=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
