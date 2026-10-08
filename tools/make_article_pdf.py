# Builds a text PDF so the article can be selected and copied.
import pathlib

ARTICLE = pathlib.Path(__file__).resolve().parents[1].joinpath("article.txt").read_text(encoding="utf-8")
if False:
    """Vire, a post-mortem

This is the record of making Vire, a new programming language, in one working session. It is written so a reader can copy it. The language is open source under the MIT license.

What we set out to build

The request was for one language, not a dialect of Java, Python, or JavaScript. Programs should be written in that language only. The same language should cover the everyday jobs people spread across several languages: calculation, files, packages, a desktop window, and a small website. It also had to stay on the machine where it was started, and it had to refuse to behave like a virus.

What Vire is

A Vire program is a text file ending in .vire. A run starts at define main and ends at end. Names are created with let and be. Output uses say. Comments start with a tilde. Definitions are called with the word with, as in area with 3, 4. Lists use brackets. Maps use braces. Loops are while and for. Errors are caught with try and miss.

The runner is vire.exe. You pass it one program file. The folder that contains that file is the only folder the program may read and write. Packages live in deps, and a program pulls one in with need. Another file in the same folder is pulled in with use.

What we tried, in order

The first sketch was a language whose programs were grains washed away by a rising flood. That was a new execution idea, and it was set aside because it did not look or work like a language someone could use for ordinary programs.

The next runner was an interpreter written in Python. It implemented definitions, arithmetic, loops, lists, and maps. The objection was correct: if Python is required, Vire is not running as itself. That interpreter was removed. The runner became vire.exe, a Windows program. People run vire.exe hello.vire. They do not run it through Python.

We then widened the language until a single program could hold real work. Files, JSON, time, HTTP fetch, local packages, and a page server were added. The page server listens only on 127.0.0.1. A sample built a notes page. That sample still emitted HTML, CSS, and JavaScript, which broke the rule that a Vire program should not depend on another programming language to be an application.

The application path was rebuilt. work.vire now uses open, line, field, button, value, and show. Those words are Vire. vire.exe draws the window. Save calls a Vire definition, which writes data/note.txt. No HTML file is required for that program.

Safety decisions

Several limits exist because the language had to be usable without being reckless.

Paths may not be absolute and may not contain .. . use may open only .vire files, at most 32 of them, and may not form a circle. write refuses extensions used for programs, including exe, dll, bat, cmd, and ps1. A while loop stops after 100,000 passes. A program stops after 1,000,000 steps. Calls stop after 64 nested calls. Lists, maps, and files are capped. fetch accepts only http and https, waits at most five seconds, and keeps at most one million bytes. The site server, if you use it, accepts GET and HEAD and will not serve those program extensions.

These limits are not a claim that the runner is unhackable. They are the boundaries we could actually enforce.

What a developer can do today

Follow GUIDE.md in the repository. The short path is: write define main, say something, run vire.exe on that file. The window path is work.vire. The package path is need and a lib.vire under deps. The data path is json, parse, read, and write. The browser path remains available through serve, and it writes files a browser can read. The window path is the one that stays inside Vire.

What we did not finish

Vire does not have a public package index, a phone build, a hosted cloud, or a way to write device drivers. The runner is a Windows program built from the C# source in Vire.cs, because a file of Vire source cannot execute on a bare processor with no runner at all. After that build, programs are Vire. There is no installer and no editor plugin yet. Division of whole numbers is whole-number division. A call binds the whole following expression, so parentheses are required before you add text onto a call result. Those are sharp edges a second version should sand down.

How to judge the result

Vire is real enough to run. count.vire prints 1 through 5. greet.vire calls another definition and branches. work.vire opens a window and saves a note. The guide is written so a person, or an agent, can start from a blank file without reading the runner source.

The honest summary is smaller than the original wish. One language can cover the everyday jobs we wired up. It cannot, by itself, become every other language. The repository is the place that work continues: more definitions, more packages, and a tighter runner. The license is MIT, so that continuation is allowed.
"""

def wrap(text, width):
    lines = []
    for para in text.split("\n"):
        if para.strip() == "":
            lines.append("")
            continue
        words = para.split(" ")
        cur = ""
        for word in words:
            trial = word if cur == "" else cur + " " + word
            if len(trial) <= width:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        if cur:
            lines.append(cur)
    return lines

def pdf_escape(s):
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

def build(lines):
    page_h = 792
    top = 742
    bottom = 54
    leading = 14
    per = (top - bottom) // leading
    pages = [lines[i:i + per] for i in range(0, len(lines), per)]
    objects = []
    def add(data):
        objects.append(data)
        return len(objects)

    font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    contents = []
    page_ids = []
    for chunk in pages:
        y = top
        parts = ["BT /F1 11 Tf"]
        for line in chunk:
            parts.append("1 0 0 1 54 %d Tm (%s) Tj" % (y, pdf_escape(line)))
            y -= leading
        parts.append("ET")
        stream = "\n".join(parts).encode("latin-1", "replace")
        cid = add("<< /Length %d >>\nstream\n" % len(stream) + stream.decode("latin-1") + "\nendstream")
        contents.append(cid)
    kids = []
    for cid in contents:
        pid = add("<< /Type /Page /Parent 0 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >> >>" % (cid, font))
        kids.append(pid)
        page_ids.append(pid)
    kids_ref = " ".join("%d 0 R" % k for k in kids)
    pages_id = add("<< /Type /Pages /Count %d /Kids [%s] >>" % (len(kids), kids_ref))
    for pid in page_ids:
        objects[pid - 1] = objects[pid - 1].replace("/Parent 0 0 R", "/Parent %d 0 R" % pages_id)
    catalog = add("<< /Type /Catalog /Pages %d 0 R >>" % pages_id)
    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(out))
        out.extend(("%d 0 obj\n" % i).encode("ascii"))
        if isinstance(obj, str):
            out.extend(obj.encode("latin-1"))
        out.extend(b"\nendobj\n")
    xref = len(out)
    out.extend(("xref\n0 %d\n" % (len(objects) + 1)).encode("ascii"))
    out.extend(b"0000000000 65535 f \n")
    for off in offsets[1:]:
        out.extend(("%010d 00000 n \n" % off).encode("ascii"))
    out.extend(("trailer << /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog, xref)).encode("ascii"))
    return out

def main():
    if len(ARTICLE) > 25000:
        raise SystemExit("article is %d characters" % len(ARTICLE))
    lines = wrap(ARTICLE, 85)
    path = pathlib.Path(__file__).resolve().parents[1] / "Vire-post-mortem.pdf"
    path.write_bytes(build(lines))
    print("wrote %s (%d characters, %d lines)" % (path, len(ARTICLE), len(lines)))

if __name__ == "__main__":
    main()
