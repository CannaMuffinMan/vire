(function () {
  "use strict";

  var keywords = {
    define: 1, with: 1, end: 1, let: 1, be: 1, say: 1, if: 1, else: 1,
    return: 1, while: 1, stop: 1, skip: 1, put: 1, into: 1, at: 1, for: 1,
    in: 1, try: 1, miss: 1, and: 1, or: 1, not: 1, true: 1, false: 1,
    none: 1, use: 1, need: 1
  };

  function escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function highlight(src) {
    var out = "";
    var i = 0;
    while (i < src.length) {
      var ch = src.charAt(i);
      if (ch === "~") {
        var end = src.indexOf("\n", i);
        if (end < 0) end = src.length;
        out += '<span class="tok-cmt">' + escapeHtml(src.slice(i, end)) + "</span>";
        i = end;
        continue;
      }
      if (ch === '"') {
        var j = i + 1;
        while (j < src.length) {
          if (src.charAt(j) === "\\" && j + 1 < src.length) { j += 2; continue; }
          if (src.charAt(j) === '"') { j += 1; break; }
          j += 1;
        }
        out += '<span class="tok-str">' + escapeHtml(src.slice(i, j)) + "</span>";
        i = j;
        continue;
      }
      if (/[0-9]/.test(ch)) {
        var k = i;
        while (k < src.length && /[0-9]/.test(src.charAt(k))) k += 1;
        out += '<span class="tok-num">' + escapeHtml(src.slice(i, k)) + "</span>";
        i = k;
        continue;
      }
      if (/[A-Za-z_]/.test(ch)) {
        var n = i;
        while (n < src.length && /[A-Za-z0-9_]/.test(src.charAt(n))) n += 1;
        var word = src.slice(i, n);
        if (keywords[word]) out += '<span class="tok-kw">' + escapeHtml(word) + "</span>";
        else out += escapeHtml(word);
        i = n;
        continue;
      }
      out += escapeHtml(ch);
      i += 1;
    }
    return out;
  }

  document.querySelectorAll("pre.code[data-src]").forEach(function (pre) {
    var code = pre.querySelector("code") || pre;
    code.innerHTML = highlight(code.textContent.replace(/^\n/, "").replace(/\n$/, ""));
  });

  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var sel = btn.getAttribute("data-copy");
      var node = document.querySelector(sel);
      if (!node) return;
      var text = node.textContent;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          btn.textContent = "Copied";
          setTimeout(function () { btn.textContent = "Copy"; }, 1200);
        });
      }
    });
  });

  var btn = document.querySelector(".menu-btn");
  var links = document.querySelector(".nav-links");
  if (btn && links) {
    btn.addEventListener("click", function () {
      var open = links.classList.toggle("open");
      btn.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }
})();
