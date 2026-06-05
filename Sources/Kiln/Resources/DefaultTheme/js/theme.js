// Kiln default theme behaviour: colour-scheme toggle, mobile navigation,
// language menu, syntax highlighting and table-of-contents scroll spying.
(function () {
    "use strict";

    // ---- Colour scheme toggle (one in the header, one in the mobile drawer) ----
    document.querySelectorAll(".kiln-palette-toggle").forEach(function (toggle) {
        toggle.addEventListener("click", function () {
            var current = document.documentElement.getAttribute("data-palette");
            var next = current === "dark" ? "light" : "dark";
            document.documentElement.setAttribute("data-palette", next);
            localStorage.setItem("kiln-palette", next);
        });
    });

    // ---- Mobile navigation drawer ----
    var menuToggle = document.getElementById("kiln-menu-toggle");
    var backdrop = document.getElementById("kiln-backdrop");
    function closeNav() {
        document.body.classList.remove("kiln-nav-open");
        if (menuToggle) menuToggle.setAttribute("aria-expanded", "false");
    }
    if (menuToggle) {
        menuToggle.addEventListener("click", function () {
            document.body.classList.remove("kiln-search-open"); // mutually exclusive
            var open = document.body.classList.toggle("kiln-nav-open");
            menuToggle.setAttribute("aria-expanded", open ? "true" : "false");
        });
    }
    if (backdrop) backdrop.addEventListener("click", closeNav);

    // ---- Mobile search overlay toggle ----
    var searchToggle = document.getElementById("kiln-search-toggle");
    if (searchToggle) {
        searchToggle.addEventListener("click", function (event) {
            event.stopPropagation();
            closeNav();
            var open = document.body.classList.toggle("kiln-search-open");
            searchToggle.setAttribute("aria-expanded", open ? "true" : "false");
            if (open) {
                var field = document.getElementById("kiln-search-input");
                if (field) field.focus();
            }
        });
    }
    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape") {
            document.body.classList.remove("kiln-search-open");
            if (searchToggle) searchToggle.setAttribute("aria-expanded", "false");
        }
    });

    // ---- Switcher dropdowns (header + drawer instances) ----
    function wireSwitchers(switcherClass, buttonClass) {
        document.querySelectorAll(switcherClass).forEach(function (switcher) {
            var button = switcher.querySelector(buttonClass);
            if (!button) return;
            button.addEventListener("click", function (event) {
                event.stopPropagation();
                switcher.classList.toggle("kiln-open");
            });
        });
        document.addEventListener("click", function () {
            document.querySelectorAll(switcherClass + ".kiln-open").forEach(function (s) {
                s.classList.remove("kiln-open");
            });
        });
    }
    wireSwitchers(".kiln-lang-switcher", ".kiln-lang-button");
    wireSwitchers(".kiln-version-switcher", ".kiln-version-button");

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
