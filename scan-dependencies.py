#!/usr/bin/env python3
"""Report OSV matches for the exact upstream lockfile; no third-party packages."""
import concurrent.futures
import json
from pathlib import Path
import sys
import tomllib
import urllib.request


def request(url, data=None):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Content-Type": "application/json", "User-Agent": "build-static-rbw"},
    )
    with urllib.request.urlopen(req, timeout=90) as response:
        return json.load(response)


def main():
    lock = tomllib.loads(Path(sys.argv[1]).read_text())
    packages = [p for p in lock["package"] if p.get("source", "").startswith("registry+")]
    result = request("https://api.osv.dev/v1/querybatch", {"queries": [
        {"package": {"name": p["name"], "ecosystem": "crates.io"}, "version": p["version"]}
        for p in packages
    ]})
    ids = sorted({v["id"] for r in result["results"] for v in r.get("vulns", [])})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        advisories = dict(zip(ids, pool.map(lambda i: request("https://api.osv.dev/v1/vulns/" + i), ids)))
    findings = []
    for p, r in zip(packages, result["results"]):
        active = [v["id"] for v in r.get("vulns", []) if not advisories[v["id"]].get("withdrawn")]
        if active:
            findings.append({"name": p["name"], "version": p["version"], "advisories": active})
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "dependency-report.json").write_text(json.dumps({
        "scope": "Entire upstream Cargo.lock, including optional and platform dependencies; reachability not established",
        "packages_checked": len(packages), "findings": findings, "advisories": advisories,
    }, indent=2) + "\n")
    lines = ["# Dependency advisory report", "",
             "Informational scan of the entire upstream Cargo.lock using OSV. Matches include optional/platform dependencies and do not establish exploitability. This build is not security-certified.", "",
             f"Packages checked: {len(packages)}. Packages with advisory matches: {len(findings)}.", ""]
    for finding in findings:
        lines.append(f"- **{finding['name']} {finding['version']}**")
        for advisory in finding["advisories"]:
            d = advisories[advisory]
            lines.append(f"  - [{advisory}](https://osv.dev/vulnerability/{advisory}): {d.get('summary', 'See advisory')}")
    (out / "dependency-report.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
