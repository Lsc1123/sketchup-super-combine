"""Capture baseline checks and known-issue probes without changing runtime code.

Exit 1 when baseline checks fail OR a diagnostic differs from its expectation.
Native SketchUp checks are run separately; this is not a SketchUp emulator.
"""
import datetime
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'test-results'


def runtime_hashes():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / 'src').rglob('*')) if p.is_file()}


def main():
    OUTPUT.mkdir(exist_ok=True)
    before = runtime_hashes()
    checks = [
        ('syntax', ['ruby', 'tools/check_syntax.rb']),
        ('python_syntax', [sys.executable, '-m', 'py_compile', 'tools/run_audit.py', 'tests/audit_package.py']),
        ('bsp_baseline', ['ruby', 'tests/bsp_test.rb']),
        ('entrypoint_regression', ['ruby', 'tests/entrypoint_test.rb']),
        ('bounds_regression', ['ruby', 'tests/bounds_test.rb']),
        ('package_baseline', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v']),
        ('package_build', [sys.executable, 'tools/package.py']),
        ('bsp_diagnostic', ['ruby', 'tests/audit_bsp.rb']),
        ('ui_guard_diagnostic', ['ruby', 'tests/audit_ui_guard.rb']),
        ('package_diagnostic', [sys.executable, 'tests/audit_package.py']),
    ]
    results = []
    for name, argv in checks:
        try:
            run = subprocess.run(argv, cwd=ROOT, text=True, encoding='utf-8',
                                 errors='replace', capture_output=True, timeout=120)
            result = dict(name=name, argv=argv, exit_code=run.returncode,
                          stdout=run.stdout, stderr=run.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            result = dict(name=name, argv=argv, exit_code=125, stdout='',
                          stderr=f'{type(error).__name__}: {error}')
        results.append(result)
        print(f'{name}: exit {result["exit_code"]}')
    report = dict(
        captured_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        baseline_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        platform=platform.platform(), python=sys.version,
        baseline_pass=all(r['exit_code'] == 0 for r in results if not r['name'].endswith('_diagnostic')),
        runtime_unchanged=before == runtime_hashes(), runtime_sha256=before, results=results)
    (OUTPUT / 'audit-checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return 0 if report['runtime_unchanged'] and all(r['exit_code'] == 0 for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
