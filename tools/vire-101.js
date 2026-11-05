const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.defineLayout({ name: "WIDE", width: 13.333, height: 7.5 });
pres.layout = "WIDE";
pres.title = "Vire, a 101";
pres.author = "Vire";
pres.subject = "What Vire is, how a program runs, where it is heading, and how the surface was kept small";

const bg = "10140F";
const card = "1A2418";
const green = "9DFFB0";
const cream = "F4F1E8";
const mute = "A8B5A4";
const line = "2C3A28";

function base(slide, kicker, title) {
  slide.background = { color: bg };
  slide.addShape(pres.shapes.RECTANGLE, {
    x: 0, y: 0, w: 0.12, h: 7.5, fill: { color: green }
  });
  if (kicker) {
    slide.addText(kicker, {
      x: 0.55, y: 0.32, w: 10, h: 0.32,
      fontFace: "Consolas", fontSize: 12, color: green, margin: 0
    });
  }
  if (title) {
    slide.addText(title, {
      x: 0.55, y: 0.68, w: 12.2, h: 0.7,
      fontFace: "Calibri", fontSize: 32, bold: true, color: cream, margin: 0
    });
  }
}

function cardBox(slide, x, y, w, h) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h,
    fill: { color: card },
    rectRadius: 0.08
  });
}

const s1 = pres.addSlide();
s1.background = { color: bg };
s1.addText("VIRE", {
  x: 0.7, y: 1.7, w: 12, h: 1.1,
  fontFace: "Consolas", fontSize: 60, color: green, margin: 0
});
s1.addText("A small language you can read, fork, and run.", {
  x: 0.7, y: 3.0, w: 11, h: 0.5,
  fontFace: "Calibri", fontSize: 24, color: cream, margin: 0
});
s1.addText("101  ·  how a program runs  ·  where it is heading  ·  a smaller attack surface by design", {
  x: 0.7, y: 3.7, w: 11, h: 0.4,
  fontFace: "Calibri", fontSize: 16, color: mute, margin: 0
});
s1.addText("github.com/CannaMuffinMan/vire", {
  x: 0.7, y: 6.6, w: 8, h: 0.3,
  fontFace: "Consolas", fontSize: 14, color: green, margin: 0
});

const s2 = pres.addSlide();
base(s2, "01  /  what it is", "One language. One file type.");
const facts = [
  ["Programs", ".vire files. A run starts at define main and stops at end."],
  ["Runner", "A C# program today. Docker or the .NET 10 SDK is enough to run it."],
  ["Windows", "A desktop build can open a window. The terminal runner does not."],
  ["License", "MIT. master keeps the original tree. native-compiler is the current default."]
];
facts.forEach((row, i) => {
  const y = 1.7 + i * 1.2;
  cardBox(s2, 0.55, y, 12.2, 1.05);
  s2.addText(row[0], {
    x: 0.8, y: y + 0.16, w: 2.2, h: 0.7,
    fontFace: "Consolas", fontSize: 16, color: green, margin: 0, valign: "middle"
  });
  s2.addText(row[1], {
    x: 3.2, y: y + 0.16, w: 9.2, h: 0.7,
    fontFace: "Calibri", fontSize: 18, color: cream, margin: 0, valign: "middle"
  });
});

const s3 = pres.addSlide();
base(s3, "02  /  a program", "The whole language fits on one slide.");
cardBox(s3, 0.55, 1.7, 6.3, 4.8);
s3.addText("define main\n  let n be 1\n  while n <= 5\n    say n\n    let n be n + 1\n  end\nend", {
  x: 0.85, y: 2.0, w: 5.7, h: 4.2,
  fontFace: "Consolas", fontSize: 22, color: green, margin: 0
});
const bits = [
  ["define / end", "A named block. main is where a run starts."],
  ["let / be", "A name gets a value. The next line can replace it."],
  ["while", "Repeats while the test is true."],
  ["say", "Prints a value and a new line."]
];
bits.forEach((b, i) => {
  const y = 1.7 + i * 1.2;
  cardBox(s3, 7.1, y, 5.6, 1.05);
  s3.addText(b[0], { x: 7.35, y: y + 0.1, w: 5.1, h: 0.35, fontFace: "Consolas", fontSize: 14, color: green, margin: 0 });
  s3.addText(b[1], { x: 7.35, y: y + 0.46, w: 5.1, h: 0.4, fontFace: "Calibri", fontSize: 15, color: cream, margin: 0 });
});

const s4 = pres.addSlide();
base(s4, "03  /  how a run works", "Read the file. Walk the words. Stop at end.");
const steps = [
  ["1", "Open", "The file you pass is the program. Its folder is the sandbox root."],
  ["2", "Load", "use pulls other .vire files in that folder. Loops and .. are refused."],
  ["3", "Run", "main runs top to bottom. Names, lists, and maps live in the program."],
  ["4", "Stop", "A step budget ends a runaway loop. A Vire error is a message, not a crash."]
];
steps.forEach((st, i) => {
  const x = 0.55 + i * 3.15;
  cardBox(s4, x, 2.0, 2.95, 4.2);
  s4.addText(st[0], { x: x + 0.2, y: 2.25, w: 2.5, h: 0.7, fontFace: "Consolas", fontSize: 32, color: green, margin: 0 });
  s4.addText(st[1], { x: x + 0.2, y: 3.1, w: 2.5, h: 0.45, fontFace: "Calibri", fontSize: 22, bold: true, color: cream, margin: 0 });
  s4.addText(st[2], { x: x + 0.2, y: 3.7, w: 2.55, h: 2.0, fontFace: "Calibri", fontSize: 15, color: mute, margin: 0 });
});

const s5 = pres.addSlide();
base(s5, "04  /  values", "Few kinds of value. You can see all of them.");
const kinds = [
  ["number", "Whole numbers. Math is the ordinary operators."],
  ["text", "Quotes. + joins text, and also joins two lists."],
  ["list", "Ordered values. push adds to the same list."],
  ["map", "Names to values. Missing keys are an error you can catch."],
  ["true / false / none", "The three small values. A definition with no return yields none."]
];
kinds.forEach((k, i) => {
  const y = 1.65 + i * 1.05;
  s5.addText(k[0], { x: 0.7, y: y, w: 3.4, h: 0.8, fontFace: "Consolas", fontSize: 18, color: green, margin: 0, valign: "middle" });
  s5.addText(k[1], { x: 4.2, y: y, w: 8.4, h: 0.8, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0, valign: "middle" });
});

const s6 = pres.addSlide();
base(s6, "05  /  files", "The program folder is the world.");
cardBox(s6, 0.55, 1.7, 6.0, 5.0);
s6.addText("Allowed", { x: 0.8, y: 1.9, w: 5.4, h: 0.4, fontFace: "Consolas", fontSize: 16, color: green, margin: 0 });
s6.addText("read, write, and list files under data/ and site/.\n\nuse loads a sibling .vire file.\n\nA missing file is an error you can catch with try / miss.", {
  x: 0.8, y: 2.5, w: 5.4, h: 3.6, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});
cardBox(s6, 6.8, 1.7, 6.0, 5.0);
s6.addText("Refused", { x: 7.05, y: 1.9, w: 5.4, h: 0.4, fontFace: "Consolas", fontSize: 16, color: green, margin: 0 });
s6.addText("Absolute paths and ..\n\nLinks and junctions\n\nWriting .exe, .dll, .bat, .ps1, and the other run-me extensions\n\nA file over 1,000,000 characters\n\nA use cycle, or more than 32 files", {
  x: 7.05, y: 2.5, w: 5.4, h: 3.8, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});

const s7 = pres.addSlide();
base(s7, "06  /  two ways to run", "Today the C# runner is the one you can trust.");
cardBox(s7, 0.55, 1.7, 6.0, 5.0);
s7.addText("C# runner", { x: 0.8, y: 1.95, w: 5.4, h: 0.4, fontFace: "Consolas", fontSize: 18, color: green, margin: 0 });
s7.addText("dotnet run, or a Docker image.\n\nThis is the language people can use now.\n\nIt is still the host that builds the native compiler.\n\nDo not delete it until a second native rebuild is proven.", {
  x: 0.8, y: 2.6, w: 5.4, h: 3.5, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});
cardBox(s7, 6.8, 1.7, 6.0, 5.0);
s7.addText("Native compiler", { x: 7.05, y: 1.95, w: 5.4, h: 0.4, fontFace: "Consolas", fontSize: 18, color: green, margin: 0 });
s7.addText("A Windows x64 program written in Vire.\n\nIt compiles a small program. That program prints hello from stage and exits 0.\n\nIt does not yet compile itself inside the 32MB heap.", {
  x: 7.05, y: 2.6, w: 5.4, h: 3.5, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});

const s8 = pres.addSlide();
base(s8, "07  /  the native path", "Standing up means the compiler produces itself.");
const path = [
  ["Done", "Compile hello. The result prints hello from stage."],
  ["Close", "The same exe can compile the compiler when the heap mapping is 96MB."],
  ["Not done", "Inside the 32MB heap that compile access-violates. The bytes do not match yet."]
];
path.forEach((p, i) => {
  const y = 1.9 + i * 1.55;
  cardBox(s8, 0.55, y, 12.2, 1.35);
  s8.addText(p[0], { x: 0.8, y: y + 0.3, w: 2.2, h: 0.7, fontFace: "Consolas", fontSize: 18, color: green, margin: 0, valign: "middle" });
  s8.addText(p[1], { x: 3.2, y: y + 0.25, w: 9.2, h: 0.85, fontFace: "Calibri", fontSize: 20, color: cream, margin: 0, valign: "middle" });
});

const s9 = pres.addSlide();
base(s9, "08  /  where it is heading", "A language that can build its own compiler.");
const heads = [
  ["Self-host", "One exe compiles the compiler, and the second hex matches the first."],
  ["Same language", "Programs, packages, and windows stay in .vire. No second syntax."],
  ["Forks", "master stays. native-compiler is the new default. People can start from either."],
  ["Not a product launch", "Payments stay off. A driver is not loaded. Phone packaging is not the goal."]
];
heads.forEach((h, i) => {
  const col = i % 2;
  const row = Math.floor(i / 2);
  const x = 0.55 + col * 6.35;
  const y = 1.8 + row * 2.4;
  cardBox(s9, x, y, 6.1, 2.15);
  s9.addText(h[0], { x: x + 0.3, y: y + 0.25, w: 5.5, h: 0.45, fontFace: "Consolas", fontSize: 18, color: green, margin: 0 });
  s9.addText(h[1], { x: x + 0.3, y: y + 0.85, w: 5.5, h: 1.0, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0 });
});

const s10 = pres.addSlide();
base(s10, "09  /  why forkable", "The source is the product.");
s10.addText("Vire is meant to be copied. The original tree stays on master so someone can write their own language on that base. The compiler tree is the default because that is the current source of truth. Neither branch is a sealed binary you have to trust. You can read define main and see the whole program.", {
  x: 0.7, y: 1.9, w: 12, h: 2.2, fontFace: "Calibri", fontSize: 22, color: cream, margin: 0
});
cardBox(s10, 0.55, 4.4, 12.2, 2.2);
s10.addText("MIT  ·  github.com/CannaMuffinMan/vire  ·  default branch native-compiler", {
  x: 0.85, y: 5.05, w: 11.6, h: 0.9,
  fontFace: "Consolas", fontSize: 18, color: green, margin: 0, align: "center", valign: "middle"
});

const s11 = pres.addSlide();
base(s11, "10  /  CVE resistance", "Fewer places a bug can hide. Not a promise of zero bugs.");
s11.addText("A CVE is a published vulnerability. Vire was shaped so common bug classes have no door: path escape, open listeners, unbounded input, and secret prints. That is resistance by a small surface. It is not a claim that a CVE can never be filed, and it is not a claim that the language is finished.", {
  x: 0.7, y: 1.8, w: 12, h: 1.8, fontFace: "Calibri", fontSize: 20, color: cream, margin: 0
});
const three = [
  ["Small", "One syntax. A short list of builtins. Less code that can be wrong."],
  ["Closed", "The program cannot leave its folder, or bind the public internet, by accident."],
  ["Bounded", "Sizes, depths, and step counts stop a hostile file from running forever."]
];
three.forEach((t, i) => {
  const x = 0.55 + i * 4.2;
  cardBox(s11, x, 4.0, 3.95, 2.6);
  s11.addText(t[0], { x: x + 0.25, y: 4.2, w: 3.45, h: 0.45, fontFace: "Consolas", fontSize: 18, color: green, margin: 0 });
  s11.addText(t[1], { x: x + 0.25, y: 4.8, w: 3.45, h: 1.4, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0 });
});

const s12 = pres.addSlide();
base(s12, "11  /  the folder", "Path bugs are a usual CVE. The path is not free.");
const rules = [
  ["Sandbox root", "The folder of the program you ran."],
  ["data/ and site/", "The only trees read and write may touch."],
  [".. and links", "Refused, including junctions."],
  ["Run-me extensions", "write will not create .exe, .dll, .bat, .ps1, and the rest of that list."]
];
rules.forEach((r, i) => {
  const y = 1.7 + i * 1.25;
  s12.addText(r[0], { x: 0.7, y: y, w: 4.2, h: 0.9, fontFace: "Consolas", fontSize: 18, color: green, margin: 0, valign: "middle" });
  s12.addText(r[1], { x: 5.1, y: y, w: 7.5, h: 0.9, fontFace: "Calibri", fontSize: 20, color: cream, margin: 0, valign: "middle" });
});

const s13 = pres.addSlide();
base(s13, "12  /  the network", "A listener is local unless you opt in, out loud.");
const nets = [
  ["127.0.0.1", "listen binds the loopback address. It does not open the public internet by default."],
  ["Public bind", "All interfaces only if VIRE_BIND is public and a token is at least 16 characters."],
  ["The token", "Header only. Never printed. The compare does not stop at the first mismatch."],
  ["Outbound", "fetch and post refuse localhost and private network addresses."]
];
nets.forEach((n, i) => {
  const y = 1.7 + i * 1.25;
  cardBox(s13, 0.55, y, 12.2, 1.1);
  s13.addText(n[0], { x: 0.8, y: y + 0.2, w: 2.6, h: 0.7, fontFace: "Consolas", fontSize: 16, color: green, margin: 0, valign: "middle" });
  s13.addText(n[1], { x: 3.6, y: y + 0.15, w: 8.8, h: 0.8, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0, valign: "middle" });
});

const s13b = pres.addSlide();
base(s13b, "13  /  outside access", "Three doors. Each one is shut unless you open it.");
const doors = [
  ["Disk", "A program cannot read the rest of the machine. Paths stay in data/ and site/. .., links, and device names are refused."],
  ["Inbound", "listen binds 127.0.0.1. Another computer cannot connect. A public bind needs VIRE_BIND=public and a token of 16 or more characters."],
  ["Outbound", "fetch and post refuse this machine and private networks, so a program cannot pivot into the LAN."]
];
doors.forEach((d, i) => {
  const y = 1.75 + i * 1.7;
  cardBox(s13b, 0.55, y, 12.2, 1.5);
  s13b.addText(d[0], { x: 0.85, y: y + 0.25, w: 2.2, h: 1.0, fontFace: "Consolas", fontSize: 20, color: green, margin: 0, valign: "middle" });
  s13b.addText(d[1], { x: 3.2, y: y + 0.22, w: 9.2, h: 1.05, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0, valign: "middle" });
});

const s13c = pres.addSlide();
base(s13c, "14  /  nothing walks in", "The listener was built. Tests already hit it.");
const inbound = [
  ["Loopback", "Default bind is 127.0.0.1. The process prints that address. It does not open 0.0.0.0 unless the public flag and token are both set."],
  ["No quiet token", "The token is a header, X-FCG-Token. It is never printed. A token in the URL or the body does not count. Two copies of the header are refused."],
  ["No path escape", "Encoded .., a slash trick, and a request for a file outside site/ return a refusal. Source .vire files are not served. There is no directory listing and no /inbox write."],
  ["Already tested", "ListenSecurityTests and ListenTests cover the token, the path tricks, slow headers, and too many connections."]
];
inbound.forEach((n, i) => {
  const y = 1.6 + i * 1.35;
  s13c.addText(n[0], { x: 0.6, y: y, w: 2.8, h: 1.1, fontFace: "Consolas", fontSize: 15, color: green, margin: 0, valign: "middle" });
  s13c.addText(n[1], { x: 3.5, y: y, w: 9.2, h: 1.1, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0, valign: "middle" });
});

const s13d = pres.addSlide();
base(s13d, "15  /  nothing walks out", "A program cannot use Vire as a tunnel.");
const outbound = [
  ["http and https only", "No other scheme. No userinfo in the URL."],
  ["This machine is refused", "Localhost, private ranges, link-local, carrier-grade NAT, and IPv4 hidden inside IPv6."],
  ["Redirects are checked again", "At most three hops. Each hop is checked. The connect uses the address that just passed."],
  ["Body cap", "The response is capped at 1 MB while it streams."]
];
outbound.forEach((n, i) => {
  const y = 1.65 + i * 1.3;
  cardBox(s13d, 0.55, y, 12.2, 1.15);
  s13d.addText(n[0], { x: 0.8, y: y + 0.2, w: 3.6, h: 0.75, fontFace: "Consolas", fontSize: 15, color: green, margin: 0, valign: "middle" });
  s13d.addText(n[1], { x: 4.5, y: y + 0.18, w: 7.9, h: 0.8, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0, valign: "middle" });
});

const s14 = pres.addSlide();
base(s14, "16  /  bounds", "Hostile input should stop, not grow.");
const bounds = [
  ["Parser", "Blocks nested past 256 are an error, not a stack overflow."],
  ["JSON and files", "Inputs over 1,000,000 characters are refused."],
  ["HTTP", "16 KB headers, 8 KB request line, 1 MB body, no chunked encoding."],
  ["Steps", "A program has a step cap. The compiler has its own higher cap. Caps are not raised to hide a bug."],
  ["Serve", "No directory listing. A .vire file, a symlink, or .. returns 404. Responses send nosniff and a self-only content policy."]
];
bounds.forEach((b, i) => {
  const y = 1.6 + i * 1.05;
  s14.addText(b[0], { x: 0.6, y: y, w: 2.6, h: 0.85, fontFace: "Consolas", fontSize: 15, color: green, margin: 0, valign: "middle" });
  s14.addText(b[1], { x: 3.4, y: y, w: 9.3, h: 0.85, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0, valign: "middle" });
});

const s15 = pres.addSlide();
base(s15, "17  /  secrets", "A trace must not become the leak.");
s15.addText("Names that look like keys, tokens, or passwords are not printed in full. A paused debugger shows a length and a short hash. The empty-string hash is a known test value. Real secrets are not written into logs, slides, or the public repo.", {
  x: 0.7, y: 1.85, w: 12, h: 1.6, fontFace: "Calibri", fontSize: 20, color: cream, margin: 0
});
cardBox(s15, 0.55, 3.8, 12.2, 2.6);
s15.addText("What this buys\n\nA CVE that is “the log file contained the key” has fewer ways to happen. The program still has to be written carefully. The runner refuses the easy leak. It does not invent a new place to hide one.", {
  x: 0.85, y: 4.05, w: 11.6, h: 2.1, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});

const s16 = pres.addSlide();
base(s16, "18  /  honest limits", "Resistance is a design. A CVE can still exist.");
const limits = [
  ["The C# runner is real software", "It can have bugs. Tests cover path, listen, and seal cases. Tests are not a certificate."],
  ["The native compiler is unfinished", "Hello runs. Self-compile inside 32MB does not. An unfinished compiler is not a security proof."],
  ["Opt-in public bind exists", "If you set the public flag and a token, you chose a network service. The token is then the lock."],
  ["Forks can remove the fences", "That is the point of a fork. The default tree keeps the fences."]
];
limits.forEach((L, i) => {
  const y = 1.65 + i * 1.3;
  s16.addText(L[0], { x: 0.6, y: y, w: 12.1, h: 0.4, fontFace: "Calibri", fontSize: 18, bold: true, color: green, margin: 0 });
  s16.addText(L[1], { x: 0.6, y: y + 0.4, w: 12.1, h: 0.55, fontFace: "Calibri", fontSize: 16, color: cream, margin: 0 });
});

const s17 = pres.addSlide();
base(s17, "19  /  try it", "Three commands. No account.");
cardBox(s17, 0.55, 1.7, 12.2, 4.9);
s17.addText("docker build -t vire .\ndocker run --rm vire tests.vire\n\ndotnet run -c Release -- tests.vire", {
  x: 0.9, y: 2.05, w: 11.5, h: 2.6,
  fontFace: "Consolas", fontSize: 22, color: green, margin: 0
});
s17.addText("tests.vire should print pass. Your own file runs if you mount its folder, or pass its path.", {
  x: 0.9, y: 5.0, w: 11.5, h: 1.0, fontFace: "Calibri", fontSize: 18, color: cream, margin: 0
});

const s18 = pres.addSlide();
s18.background = { color: bg };
s18.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.12, h: 7.5, fill: { color: green } });
s18.addText("Read it. Fork it. Run it.", {
  x: 0.7, y: 2.2, w: 12, h: 0.9,
  fontFace: "Calibri", fontSize: 36, bold: true, color: cream, margin: 0
});
s18.addText("Vire is small on purpose. The fences are in the language so a program does not have to remember them. The compiler is close to standing on its own. It is not there until the second hex matches.", {
  x: 0.7, y: 3.3, w: 11.5, h: 1.4,
  fontFace: "Calibri", fontSize: 18, color: mute, margin: 0
});
s18.addText("github.com/CannaMuffinMan/vire", {
  x: 0.7, y: 5.6, w: 10, h: 0.4,
  fontFace: "Consolas", fontSize: 16, color: green, margin: 0
});

pres.writeFile({ fileName: "D:/_scratch/worktrees/vire-e-len/Vire-101.pptx" })
  .then(() => console.log("wrote"))
  .catch((e) => { console.error(e); process.exit(1); });
