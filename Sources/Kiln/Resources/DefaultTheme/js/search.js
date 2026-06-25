// Kiln client-side search. Loads the per-language search index emitted at build
// time and ranks documents with a small TF-style scorer — no external library.
//
// Tokenisation is Unicode-aware and works across languages:
//   * matching is diacritic-insensitive — text and queries are folded
//     (NFD + combining marks stripped), so "validacion" matches "validación";
//   * Han ideographs and Japanese kana (not space-separated) are segmented into
//     overlapping bigrams so phrase queries match;
//   * everything else (incl. space-separated Hangul, Latin) is matched whole.
// Display always uses the original, accented text.
// (A future iteration may swap in a Wasm-backed index.)
(function () {
    "use strict";

    var input = document.getElementById("kiln-search-input");
    var results = document.getElementById("kiln-search-results");
    if (!input || !results || !window.kilnSearchIndex) return;

    var container = document.getElementById("kiln-search");
    var noResultsText = (container && container.getAttribute("data-no-results")) || "No results found";

    // Han (incl. extension A & compatibility) + hiragana/katakana (incl.
    // halfwidth). Deliberately excludes Hangul, which is space-separated.
    var SEGMENTED = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f]/;

    var docs = [];
    var loaded = false;
    var loading = false;
    // Index of the keyboard-highlighted result (-1 = none). Reset whenever the
    // list is re-rendered or hidden.
    var activeIndex = -1;

    // Lowercase and remove diacritics. Under NFC input each character folds to
    // exactly one character, so folded offsets line up with the original text.
    function fold(value) {
        return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }

    function loadIndex() {
        if (loaded || loading) return;
        loading = true;
        fetch(window.kilnSearchIndex)
            .then(function (response) { return response.json(); })
            .then(function (data) {
                docs = (data && data.docs) || [];
                // Precompute folded title/text once for matching.
                docs.forEach(function (doc) {
                    doc.foldedTitle = fold(doc.title || "");
                    doc.foldedText = fold(doc.text || "");
                });
                loaded = true;
                loading = false;
                if (input.value.trim()) run(input.value);
            })
            .catch(function () { loading = false; });
    }

    // Maximal folded runs of letters/numbers (whole words, incl. CJK runs),
    // used both for matching and for highlighting.
    function units(query) {
        return fold(query).match(/[\p{L}\p{N}_]+/gu) || [];
    }

    // Expand a unit into match terms: segmented scripts become overlapping
    // bigrams (single char if only one), everything else stays whole.
    function expand(unit) {
        var terms = [];
        var word = "";
        var cjk = [];
        function flushWord() { if (word) { terms.push(word); word = ""; } }
        function flushCJK() {
            if (cjk.length === 1) {
                terms.push(cjk[0]);
            } else {
                for (var i = 0; i < cjk.length - 1; i++) { terms.push(cjk[i] + cjk[i + 1]); }
            }
            cjk = [];
        }
        Array.from(unit).forEach(function (ch) {
            if (SEGMENTED.test(ch)) { flushWord(); cjk.push(ch); }
            else { flushCJK(); word += ch; }
        });
        flushWord();
        flushCJK();
        return terms;
    }

    function score(doc, terms) {
        var total = 0;
        for (var i = 0; i < terms.length; i++) {
            var term = terms[i];
            if (!term) continue;
            if (doc.foldedTitle.indexOf(term) !== -1) total += 10;
            var occurrences = doc.foldedText.split(term).length - 1;
            total += occurrences;
            if (occurrences === 0 && doc.foldedTitle.indexOf(term) === -1) {
                return 0; // every term must appear somewhere
            }
        }
        return total;
    }

    function snippet(doc, queryUnits) {
        var folded = doc.foldedText;
        var position = -1;
        for (var i = 0; i < queryUnits.length; i++) {
            position = folded.indexOf(queryUnits[i]);
            if (position !== -1) break;
        }
        if (position === -1) position = 0;
        var start = Math.max(0, position - 50);
        var prefix = start > 0 ? "…" : "";
        return highlightRange(prefix + doc.text.slice(start, start + 180), queryUnits);
    }

    function escapeHTML(value) {
        return value.replace(/[&<>"]/g, function (character) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[character];
        });
    }

    // Diacritic-insensitive highlighting: fold a copy of the text to locate
    // matches, then wrap the corresponding spans of the *original* text in
    // <mark>. Folded/original offsets align for NFC input.
    function highlightRange(text, queryUnits) {
        var folded = fold(text);
        var marked = new Array(text.length).fill(false);
        queryUnits.forEach(function (unit) {
            if (!unit) return;
            var from = 0;
            var index;
            while ((index = folded.indexOf(unit, from)) !== -1) {
                for (var i = index; i < index + unit.length && i < marked.length; i++) { marked[i] = true; }
                from = index + unit.length;
            }
        });
        var out = "";
        var open = false;
        for (var i = 0; i < text.length; i++) {
            if (marked[i] && !open) { out += "<mark>"; open = true; }
            else if (!marked[i] && open) { out += "</mark>"; open = false; }
            out += escapeHTML(text[i]);
        }
        if (open) out += "</mark>";
        return out;
    }

    function run(query) {
        var queryUnits = units(query);
        if (!queryUnits.length) { hide(); return; }

        var terms = [];
        queryUnits.forEach(function (unit) { terms = terms.concat(expand(unit)); });
        if (!terms.length) { hide(); return; }

        var matches = [];
        for (var i = 0; i < docs.length; i++) {
            var value = score(docs[i], terms);
            if (value > 0) matches.push({ doc: docs[i], score: value });
        }
        matches.sort(function (a, b) { return b.score - a.score; });
        render(matches.slice(0, 10), queryUnits);
    }

    function render(matches, queryUnits) {
        if (!matches.length) {
            results.innerHTML = '<div class="kiln-search-empty">' + escapeHTML(noResultsText) + '</div>';
            results.hidden = false;
            return;
        }
        var html = "";
        matches.forEach(function (match) {
            var location = match.doc.location ? "/" + match.doc.location : "/";
            html += '<a class="kiln-search-result" href="' + location + '">' +
                '<span class="kiln-search-result-title">' + highlightRange(match.doc.title, queryUnits) + "</span>" +
                '<span class="kiln-search-result-context">' + snippet(match.doc, queryUnits) + "</span>" +
                "</a>";
        });
        results.innerHTML = html;
        results.hidden = false;
        activeIndex = -1;
    }

    function hide() {
        results.hidden = true;
        results.innerHTML = "";
        activeIndex = -1;
    }

    // Live list of result anchors (empty for the no-results / prompt states).
    function resultLinks() {
        return Array.prototype.slice.call(results.querySelectorAll(".kiln-search-result"));
    }

    // Highlight the result at `index`, wrapping past either end, and keep it in
    // view. Drives the `.kiln-active` style the theme already defines for hover.
    function setActive(index) {
        var links = resultLinks();
        if (!links.length) { activeIndex = -1; return; }
        if (index < 0) index = links.length - 1;
        else if (index >= links.length) index = 0;
        activeIndex = index;
        for (var i = 0; i < links.length; i++) {
            var on = i === activeIndex;
            links[i].classList.toggle("kiln-active", on);
            if (on) links[i].scrollIntoView({ block: "nearest" });
        }
    }

    input.addEventListener("focus", loadIndex);
    input.addEventListener("input", function () {
        var query = input.value.trim();
        if (!query) { hide(); return; }
        if (loaded) run(query); else loadIndex();
    });
    input.addEventListener("keydown", function (event) {
        if (event.key === "Escape") { input.value = ""; hide(); input.blur(); return; }
        if (results.hidden) return;
        if (event.key === "ArrowDown") {
            if (!resultLinks().length) return;
            event.preventDefault();
            setActive(activeIndex + 1);
        } else if (event.key === "ArrowUp") {
            if (!resultLinks().length) return;
            event.preventDefault();
            setActive(activeIndex - 1);
        } else if (event.key === "Enter") {
            var links = resultLinks();
            if (activeIndex >= 0 && links[activeIndex]) {
                event.preventDefault();
                window.location.href = links[activeIndex].getAttribute("href");
            }
        }
    });
    document.addEventListener("click", function (event) {
        if (!event.target.closest(".kiln-search")) hide();
    });
})();
