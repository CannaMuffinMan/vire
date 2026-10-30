#!/usr/bin/env python3
"""Emit Track H attack corpus programs and expect.json sidecars."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "tests" / "corpus"


def expect(path, cls, contains, *, exit_code=1, forbids=None, stdout_forbids=None,
           compile_reject=None, kind="source", budget=None, notes=None,
           stdout_contains=None):
    data = {
        "class": cls,
        "kind": kind,
        "exit": exit_code,
        "stderr_contains": contains,
        "stderr_forbids": forbids or ["internal error", "at Vire.", "CryptographicException", "StackOverflow"],
        "stdout_contains": stdout_contains or [],
        "stdout_forbids": stdout_forbids or ["PWNED", "OUTSIDE-SECRET", "root:x:"],
        "compile_reject": compile_reject or [],
    }
    if budget is not None:
        data["budget"] = budget
    if notes:
        data["notes"] = notes
    Path(str(path) + ".expect.json").write_text(json.dumps(data, indent=2) + "\n")


def vire(rel, source, cls, contains, **kw):
    dest = ROOT / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not source.endswith("\n"):
        source += "\n"
    dest.write_text(source)
    expect(dest, cls, contains, **kw)


def main():
    if ROOT.exists():
        for p in ROOT.rglob("*"):
            if p.is_file() and p.name != "README.md":
                p.unlink()
    ROOT.mkdir(parents=True, exist_ok=True)

    taint = ["taint"]
    caps = ["capabilities"]
    types = ["types"]

    # --- SQL injection: payloads used as paths, run targets, writes ---
    vire("sql/quote-union-path.vire", '''define main
  read with "data/' UNION SELECT ../secret.txt"
end''', "sql-injection", ["program folder"], compile_reject=taint)
    vire("sql/or-rooted.vire", '''define main
  read with "' OR 1=1 -- /etc/passwd"
end''', "sql-injection", ["program folder"], compile_reject=taint)
    vire("sql/stacked-abs.vire", '''define main
  write with "/tmp/pwn.sql", "'; DROP TABLE users;--"
end''', "sql-injection", ["program folder"], compile_reject=taint)
    vire("sql/comment-dotdot.vire", '''define main
  read with "data/x'--/../etc/passwd"
end''', "sql-injection", ["program folder"], compile_reject=taint)
    vire("sql/run-injected-name.vire", '''define main
  run with "helper'; DROP TABLE t;--.vire"
end''', "sql-injection", ["could not read"], compile_reject=taint)

    # --- HTML / script injection ---
    vire("html/write-hta.vire", '''define main
  write with "data/page.hta", "<script>alert(1)</script>"
end''', "html-injection", ["will not write a program file"], compile_reject=taint)
    vire("html/js-in-data.vire", '''define main
  write with "data/xss.js", "alert(1)"
end''', "html-injection", ["will not write a program file"], compile_reject=taint)
    vire("html/script-in-filename.vire", '''define main
  write with "data/<script>.txt", "x"
end''', "html-injection", ["program folder"], compile_reject=taint)
    vire("html/javascript-url.vire", '''define main
  fetch with "javascript:alert(1)"
end''', "html-injection", ["http or https"], compile_reject=taint)
    vire("html/data-url-script.vire", '''define main
  fetch with "data:text/html,<script>alert(1)</script>"
end''', "html-injection", ["http or https"], compile_reject=taint)

    # --- Shell injection ---
    vire("shell/write-sh.vire", '''define main
  write with "data/pwn.sh", "rm -rf /"
end''', "shell-injection", ["will not write a program file"], compile_reject=taint)
    vire("shell/write-bat.vire", '''define main
  write with "data/pwn.bat", "del /f /s /q C:"
end''', "shell-injection", ["will not write a program file"], compile_reject=taint)
    vire("shell/write-ps1.vire", '''define main
  write with "data/pwn.ps1", "Invoke-Expression $env:CMD"
end''', "shell-injection", ["will not write a program file"], compile_reject=taint)
    vire("shell/run-binary.vire", '''define main
  run with "ls"
end''', "shell-injection", ["run needs a vire file"], compile_reject=caps)
    vire("shell/pipe-path.vire", '''define main
  read with "data/x|rm -rf /"
end''', "shell-injection", ["program folder"], compile_reject=taint)
    vire("shell/glob-path.vire", '''define main
  read with "data/*.txt"
end''', "shell-injection", ["program folder"], compile_reject=taint)

    # --- Path traversal ---
    vire("path/dotdot.vire", '''define main
  read with "data/../secret.txt"
end''', "path-traversal", ["program folder"], compile_reject=taint)
    vire("path/absolute-unix.vire", '''define main
  read with "/etc/passwd"
end''', "path-traversal", ["program folder"], compile_reject=caps)
    vire("path/windows-drive.vire", '''define main
  read with "C:/Windows/win.ini"
end''', "path-traversal", ["program folder"], compile_reject=caps)
    vire("path/ads.vire", '''define main
  read with "data/note.txt:secret"
end''', "path-traversal", ["program folder"])
    vire("path/nul-device.vire", '''define main
  write with "data/nul.txt", "x"
end''', "path-traversal", ["program folder"])
    vire("path/trailing-dot.vire", '''define main
  read with "data/note.txt."
end''', "path-traversal", ["program folder"])
    vire("path/planted-run.vire", '''define main
  run with "data/evil.vire"
end''', "path-traversal", ["data and site"], compile_reject=caps)
    vire("path/encoded-dotdot.vire", '''define main
  read with "data/..%2fsecret.txt"
end''', "path-traversal", ["could not read"])

    # --- SSRF ---
    vire("ssrf/loopback.vire", '''define main
  fetch with "http://127.0.0.1:9/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/mapped-ipv6.vire", '''define main
  fetch with "http://[::ffff:127.0.0.1]:9/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/decimal-ip.vire", '''define main
  fetch with "http://2130706433/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/hex-ip.vire", '''define main
  fetch with "http://0x7f000001/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/octal-ip.vire", '''define main
  fetch with "http://0177.0.0.1/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/short-ip.vire", '''define main
  fetch with "http://127.1/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/userinfo.vire", '''define main
  fetch with "https://user:pass@example.com/"
end''', "ssrf", ["not allowed"], compile_reject=taint)
    vire("ssrf/file-scheme.vire", '''define main
  fetch with "file:///etc/passwd"
end''', "ssrf", ["http or https"], compile_reject=caps)
    vire("ssrf/gopher.vire", '''define main
  post with "gopher://127.0.0.1:70/_secret", "x"
end''', "ssrf", ["http or https"], compile_reject=caps)
    vire("ssrf/localhost-name.vire", '''define main
  fetch with "http://localhost:9/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/ipv6-loopback.vire", '''define main
  fetch with "http://[::1]:9/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/zero-ip.vire", '''define main
  fetch with "http://0/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/link-local-metadata.vire", '''define main
  fetch with "http://169.254.169.254/"
end''', "ssrf", ["private"], compile_reject=caps)
    vire("ssrf/redirect-target.vire", '''define main
  fetch with "http://127.0.0.1:9/secret"
end''', "ssrf", ["private"], compile_reject=caps,
         notes="Redirect hops are re-checked; a hop to this private target is refused the same way as a direct fetch.")
    vire("ssrf/userinfo-ipv6.vire", '''define main
  fetch with "http://user@[::1]:9/"
end''', "ssrf", ["not allowed"], compile_reject=taint)

    # --- JSON / deserialization ---
    deep = "[" * 300 + "]" * 300
    vire("json/deep-nest.vire", f'''define main
  parse with "{deep}"
end''', "deserialization", ["nested too deeply"])
    vire("json/bad-escape.vire", r'''define main
  parse with "\"\\uZZZZ\""
end''', "deserialization", ["bad escape"])
    vire("json/extra-text.vire", '''define main
  parse with "true true"
end''', "deserialization", ["extra"])
    vire("json/schema-extra.vire", '''define main
  let schema be {"kind": "map", "closed": true, "need": ["title"], "keys": {"title": {"kind": "text"}}}
  parse with (json with {"title": "hi", "nope": 1}), schema
end''', "deserialization", ["extra key"], compile_reject=types)
    vire("json/schema-missing.vire", '''define main
  let schema be {"kind": "map", "closed": true, "need": ["title"], "keys": {"title": {"kind": "text"}}}
  parse with "{}", schema
end''', "deserialization", ["missing a required key"], compile_reject=types)
    vire("json/schema-wrong.vire", '''define main
  let schema be {"kind": "map", "closed": false, "keys": {"title": {"kind": "text"}}}
  parse with (json with {"title": 9}), schema
end''', "deserialization", ["wrong type"], compile_reject=types)
    vire("json/huge-number.vire", '''define main
  parse with "1e400"
end''', "deserialization", ["bad number"])
    vire("json/cycle-write.vire", '''define main
  let box be []
  push with box, box
  json with box
end''', "deserialization", ["contains itself"])
    vire("json/wide-array.vire", '''define main
  let n be 0
  let bits be ["["]
  while n < 500
    push with bits, "1"
    push with bits, ","
    let n be n + 1
  end
  parse with ((join with bits, "") + "1]")
  let huge be []
  let i be 0
  while i < 100001
    push with huge, 1
    let i be i + 1
  end
end''', "deserialization", ["too large"], budget=5000000)

    # --- Secret leakage ---
    vire("secret/read-etc.vire", '''define main
  say (read with "/etc/passwd")
end''', "secret-leakage", ["program folder"], compile_reject=caps,
         stdout_forbids=["PWNED", "OUTSIDE-SECRET", "root:x:", "root:"])
    vire("secret/dotdot-env.vire", '''define main
  say (read with "../.env")
end''', "secret-leakage", ["program folder"], compile_reject=caps)
    vire("secret/userinfo-error.vire", '''define main
  try
    fetch with "https://user:s3cret@example.com/"
  miss problem
    say problem
  end
end''', "secret-leakage", [], exit_code=0, compile_reject=taint,
         stdout_contains=["not allowed"],
         stdout_forbids=["PWNED", "OUTSIDE-SECRET", "s3cret", "user:s3cret"],
         notes="Caught error text must not echo URL userinfo.")
    vire("secret/decrypt-tamper.vire", '''define main
  decrypt with "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "00"
end''', "secret-leakage", ["packed hex"],
         stdout_forbids=["PWNED", "OUTSIDE-SECRET", "00112233445566778899aabbccddeeff"])
    vire("secret/json-self.vire", '''define main
  let box be []
  push with box, box
  say (json with box)
end''', "secret-leakage", ["contains itself"])

    # --- Resource exhaustion ---
    vire("resource/runaway-while.vire", '''define main
  while 1
  end
  say "escaped"
end''', "resource-exhaustion", ["too long"], budget=200,
         stdout_forbids=["escaped", "PWNED"])
    vire("resource/deep-calls.vire", '''define boom with n
  return boom with (n + 1)
end
define main
  boom with 1
end''', "resource-exhaustion", ["too deep"])
    vire("resource/huge-span.vire", '''define main
  span with 1, 200000
end''', "resource-exhaustion", ["too large"])
    vire("resource/deep-expr.vire",
         "define main\n  say " + ("(" * 400) + "1" + (")" * 400) + "\nend\n",
         "resource-exhaustion", ["too deep"])
    vire("resource/nested-run.vire", '''define main
  run with "nested-run.vire"
end''', "resource-exhaustion", ["too deep"], budget=50000)

    # --- Malformed .vc ---
    empty = ROOT / "malformed" / "empty.vc"
    empty.parent.mkdir(parents=True, exist_ok=True)
    empty.write_bytes(b"")
    expect(empty, "malformed-vc", ["damaged"], kind="vc")

    garbage = ROOT / "malformed" / "garbage.vc"
    garbage.write_bytes(b"\x00\xffnot-a-seal\x00" * 8)
    expect(garbage, "malformed-vc", ["damaged"], kind="vc")

    truncated = ROOT / "malformed" / "truncated.vc"
    truncated.write_bytes(b"VIRE-VC2\x00\x02\x00\x01")
    expect(truncated, "malformed-vc", ["damaged"], kind="vc")

    old = ROOT / "malformed" / "old-xor.vc"
    old.write_bytes((ROOT.parents[1] / "tests" / "fixtures" / "old-xor.vc").read_bytes())
    expect(old, "malformed-vc", ["old seal"], kind="vc")

    wrong = ROOT / "malformed" / "wrong-magic.vc"
    wrong.write_bytes(b"VIRE-VC3\x00" + b"\x00" * 40)
    expect(wrong, "malformed-vc", ["damaged"], kind="vc")

    n = len(list(ROOT.rglob("*.expect.json")))
    print("corpus programs:", n)
    if n < 40:
        raise SystemExit("need at least 40")


if __name__ == "__main__":
    main()
