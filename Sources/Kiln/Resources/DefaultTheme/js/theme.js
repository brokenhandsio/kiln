// Kiln default theme behaviour: colour-scheme toggle, mobile navigation,
// language menu, syntax highlighting and table-of-contents scroll spying.
(function () {
    "use strict";

    // ---- Colour scheme toggle ----
    var paletteToggle = document.getElementById("kiln-palette-toggle");
    if (paletteToggle) {
        paletteToggle.addEventListener("click", function () {
            var current = document.documentElement.getAttribute("data-palette");
            var next = current === "dark" ? "light" : "dark";
            document.documentElement.setAttribute("data-palette", next);
            localStorage.setItem("kiln-palette", next);
        });
    }

    // ---- Mobile navigation drawer ----
    var menuToggle = document.getElementById("kiln-menu-toggle");
    var backdrop = document.getElementById("kiln-backdrop");
    function closeNav() {
        document.body.classList.remove("kiln-nav-open");
        if (menuToggle) menuToggle.setAttribute("aria-expanded", "false");
    }
    if (menuToggle) {
        menuToggle.addEventListener("click", function () {
            var open = document.body.classList.toggle("kiln-nav-open");
            menuToggle.setAttribute("aria-expanded", open ? "true" : "false");
        });
    }
    if (backdrop) backdrop.addEventListener("click", closeNav);

    // ---- Language switcher dropdown ----
    var langSwitcher = document.querySelector(".kiln-lang-switcher");
    if (langSwitcher) {
        var langButton = langSwitcher.querySelector(".kiln-lang-button");
        langButton.addEventListener("click", function (event) {
            event.stopPropagation();
            langSwitcher.classList.toggle("kiln-open");
        });
        document.addEventListener("click", function () {
            langSwitcher.classList.remove("kiln-open");
        });
    }

    // ---- Carbon ads (desktop only, where the TOC sidebar is visible) ----
    var carbon = document.getElementById("kiln-carbon");
    if (carbon && carbon.dataset.serve && window.innerWidth > 1200) {
        var ad = document.createElement("script");
        ad.async = true;
        ad.type = "text/javascript";
        ad.id = "_carbonads_js";
        ad.src = "//cdn.carbonads.com/carbon.js?serve=" + encodeURIComponent(carbon.dataset.serve) +
            "&placement=" + encodeURIComponent(carbon.dataset.placement);
        carbon.appendChild(ad);
    }

    // ---- Syntax highlighting ----
    if (window.hljs) {
        document.querySelectorAll("pre code").forEach(function (block) {
            window.hljs.highlightElement(block);
        });
    }

    // ---- Table-of-contents scroll spy ----
    var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".kiln-toc-entry a"));
    if (tocLinks.length && "IntersectionObserver" in window) {
        var byId = {};
        tocLinks.forEach(function (link) {
            var id = decodeURIComponent(link.getAttribute("href").slice(1));
            byId[id] = link;
        });
        var visible = new Set();
        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) visible.add(entry.target.id);
                else visible.delete(entry.target.id);
            });
            tocLinks.forEach(function (link) { link.classList.remove("kiln-toc-active"); });
            for (var id in byId) {
                if (visible.has(id)) { byId[id].classList.add("kiln-toc-active"); break; }
            }
        }, { rootMargin: "-80px 0px -70% 0px" });

        Object.keys(byId).forEach(function (id) {
            var heading = document.getElementById(id);
            if (heading) observer.observe(heading);
        });
    }
})();
