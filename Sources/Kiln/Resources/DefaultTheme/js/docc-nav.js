// Highlights the current page in the DocC symbol sidebar, opens its ancestor
// disclosures, and wires the branch expand/collapse buttons. The tree is
// rendered once per module (server-side) with no current-page state — so this
// runs per page instead of re-rendering the whole tree N times (O(N), not O(N²)).
(function () {
  var nav = document.querySelector(".docc-nav-list");
  if (!nav) return;

  // Reveal a branch's children: un-hide the list and mark its toggle expanded.
  function expand(list) {
    if (!list) return;
    list.hidden = false;
    var toggle = nav.querySelector('.docc-nav-toggle[aria-controls="' + (window.CSS && CSS.escape ? CSS.escape(list.id) : list.id) + '"]');
    if (toggle) toggle.setAttribute("aria-expanded", "true");
  }

  // Expand/collapse buttons. Each controls a sibling list via aria-controls.
  var toggles = nav.querySelectorAll(".docc-nav-toggle");
  for (var t = 0; t < toggles.length; t++) {
    toggles[t].addEventListener("click", function () {
      var id = this.getAttribute("aria-controls");
      var list = id && document.getElementById(id);
      if (!list) return;
      var open = this.getAttribute("aria-expanded") === "true";
      this.setAttribute("aria-expanded", open ? "false" : "true");
      list.hidden = open;
    });
  }

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

  // Open every ancestor disclosure so the current symbol is visible. Symbol
  // branches are a hidden <ul id> controlled by a button; group markers are
  // native <details>.
  var el = current.parentElement;
  while (el && el !== nav) {
    if (el.tagName === "UL" && el.id) expand(el);
    else if (el.tagName === "DETAILS") el.open = true;
    el = el.parentElement;
  }

  // If the current symbol itself has children, open them too.
  var currentItem = current.closest(".docc-nav-item");
  if (currentItem) {
    var ownList = currentItem.querySelector(":scope > ul.docc-nav-list[id]");
    if (ownList) expand(ownList);
  }

  // Centre the current symbol within the sidebar's own scroll area. Note we
  // scroll the nav container directly rather than calling
  // current.scrollIntoView({block:"center"}) — that also scrolls the page to
  // centre the item in the viewport, which pushes a non-sticky navbar off-screen.
  var scroller = current.closest(".kiln-nav");
  if (scroller && scroller.scrollHeight > scroller.clientHeight) {
    var offset = current.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
    scroller.scrollTop += offset - (scroller.clientHeight - current.offsetHeight) / 2;
  } else if (current.scrollIntoView) {
    current.scrollIntoView({ block: "nearest" });
  }
})();
