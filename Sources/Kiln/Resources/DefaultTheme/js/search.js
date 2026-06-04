// Kiln client-side search. Loads the per-language search index emitted at build
// time and ranks documents with a small TF-style scorer — no external library.
// (A future iteration may swap in a Wasm-backed index.)
(function () {
    "use strict";

    var input = document.getElementById("kiln-search-input");
    var results = document.getElementById("kiln-search-results");
    if (!input || !results || !window.kilnSearchIndex) return;

    var docs = [];
    var loaded = false;
    var loading = false;

    function loadIndex() {
        if (loaded || loading) return;
        loading = true;
        fetch(window.kilnSearchIndex)
            .then(function (response) { return response.json(); })
            .then(function (data) {
                docs = (data && data.docs) || [];
                loaded = true;
                loading = false;
                if (input.value.trim()) run(input.value);
            })
            .catch(function () { loading = false; });
    }

    function tokenize(text) {
        return text.toLowerCase().split(/[^a-z0-9_]+/).filter(Boolean);
    }

    function score(doc, terms) {
        var title = doc.title.toLowerCase();
        var text = doc.text.toLowerCase();
        var total = 0;
        for (var i = 0; i < terms.length; i++) {
            var term = terms[i];
            if (!term) continue;
            if (title.indexOf(term) !== -1) total += 10;
            var occurrences = text.split(term).length - 1;
            total += occurrences;
            if (occurrences === 0 && title.indexOf(term) === -1) {
                return 0; // every term must appear somewhere
            }
        }
        return total;
    }

    function snippet(text, terms) {
        var lower = text.toLowerCase();
        var position = -1;
        for (var i = 0; i < terms.length; i++) {
            position = lower.indexOf(terms[i]);
            if (position !== -1) break;
        }
        if (position === -1) position = 0;
        var start = Math.max(0, position - 50);
        var excerpt = text.slice(start, start + 180);
        if (start > 0) excerpt = "…" + excerpt;
        return highlight(excerpt, terms);
    }

    function escapeHTML(value) {
        return value.replace(/[&<>"]/g, function (character) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[character];
        });
    }

    function highlight(value, terms) {
        var escaped = escapeHTML(value);
        terms.forEach(function (term) {
            if (!term) return;
            var pattern = new RegExp("(" + term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig");
            escaped = escaped.replace(pattern, "<mark>$1</mark>");
        });
        return escaped;
    }

    function run(query) {
        var terms = tokenize(query);
        if (!terms.length) { hide(); return; }

        var matches = [];
        for (var i = 0; i < docs.length; i++) {
            var value = score(docs[i], terms);
            if (value > 0) matches.push({ doc: docs[i], score: value });
        }
        matches.sort(function (a, b) { return b.score - a.score; });
        render(matches.slice(0, 10), terms);
    }

    function render(matches, terms) {
        if (!matches.length) {
            results.innerHTML = '<div class="kiln-search-empty">No results found</div>';
            results.hidden = false;
            return;
        }
        var html = "";
        matches.forEach(function (match) {
            var location = match.doc.location ? "/" + match.doc.location : "/";
            html += '<a class="kiln-search-result" href="' + location + '">' +
                '<span class="kiln-search-result-title">' + highlight(match.doc.title, terms) + "</span>" +
                '<span class="kiln-search-result-context">' + snippet(match.doc.text, terms) + "</span>" +
                "</a>";
        });
        results.innerHTML = html;
        results.hidden = false;
    }

    function hide() {
        results.hidden = true;
        results.innerHTML = "";
    }

    input.addEventListener("focus", loadIndex);
    input.addEventListener("input", function () {
        var query = input.value.trim();
        if (!query) { hide(); return; }
        if (loaded) run(query); else loadIndex();
    });
    input.addEventListener("keydown", function (event) {
        if (event.key === "Escape") { input.value = ""; hide(); input.blur(); }
    });
    document.addEventListener("click", function (event) {
        if (!event.target.closest(".kiln-search")) hide();
    });
})();
