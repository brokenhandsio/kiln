// Highlights the current page in the DocC symbol sidebar and opens its ancestor
// disclosures. The sidebar tree is rendered once per module (server-side) with
// no current-page state — so this runs per page instead of re-rendering the
// whole tree N times during the build (O(N) instead of O(N²)).
(function () {
  var nav = document.querySelector(".docc-nav-list");
  if (!nav) return;

  var here = location.pathname;
  var hereAlt = here.charAt(here.length - 1) === "/" ? here.slice(0, -1) : here + "/";

  var links = nav.querySelectorAll("a.docc-nav-link");
  var current = null;
  for (var i = 0; i < links.length; i++) {
    var href = links[i].getAttribute("href");
    if (href === here || href === hereAlt) { current = links[i]; break; }
  }
  if (!current) return;

  current.classList.add("docc-current");
  current.setAttribute("aria-current", "page");

  // Open every <details> ancestor so the current symbol is visible.
  var el = current.parentElement;
  while (el && el !== nav) {
    if (el.tagName === "DETAILS") el.open = true;
    el = el.parentElement;
  }

  if (current.scrollIntoView) current.scrollIntoView({ block: "center" });
})();
