/* 共用導覽、頁尾、進場動效 */
(function () {
  var cfg = window.BRAVESOUL || {};
  var brand = cfg.name || "勇者之魂";
  var path = location.pathname.replace(/\\/g, "/");
  var depth = path.match(/\/pages\//) ? ".." : ".";
  var links = [
    { href: depth + "/index.html", id: "home", label: "首頁" },
    { href: depth + "/pages/weapons.html", id: "weapons", label: "流派" },
    { href: depth + "/pages/equipment.html", id: "equipment", label: "裝備" },
    { href: depth + "/pages/systems.html", id: "systems", label: "養成" },
    { href: depth + "/pages/walkthrough.html", id: "walkthrough", label: "攻略" },
    { href: depth + "/pages/guide.html", id: "guide", label: "指南" },
    { href: depth + "/pages/gallery.html", id: "gallery", label: "畫面" },
    { href: depth + "/pages/download.html", id: "download", label: "下載" },
    { href: depth + "/pages/account.html", id: "account", label: "帳號" },
  ];
  var active = document.body.getAttribute("data-page") || "home";
  var reduceMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function el(html) {
    var t = document.createElement("template");
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  var nav = el(
    '<nav class="gnb" aria-label="主選單"><div class="container gnb-inner">' +
      '<a class="logo" href="' +
      depth +
      '/index.html"><span class="logo-mark" aria-hidden="true">🐇</span><span>' +
      brand +
      "</span></a>" +
      '<div class="gnb-menu" id="gnb-menu"></div>' +
      '<div class="gnb-actions">' +
      '<a class="btn btn-primary" href="' +
      depth +
      '/pages/account.html">開始旅程</a></div>' +
      "</div></nav>"
  );
  document.body.insertBefore(nav, document.body.firstChild);

  var menu = document.getElementById("gnb-menu");
  links.forEach(function (L) {
    var a = document.createElement("a");
    a.href = L.href;
    a.textContent = L.label;
    if (L.id === active) a.className = "active";
    menu.appendChild(a);
  });

  var social = cfg.facebook
    ? ' · <a href="' + cfg.facebook + '" target="_blank" rel="noopener">Facebook</a>'
    : "";
  var foot = el(
    '<footer><div class="container footer-inner">' +
      "<div>" +
      brand +
      " · 一隻不慕強權的兔子</div>" +
      '<div><a href="' +
      depth +
      '/index.html">首頁</a> · <a href="' +
      depth +
      '/pages/account.html">帳號</a>' +
      social +
      "</div>" +
      "</div></footer>"
  );
  document.body.appendChild(foot);

  /* ── 導覽列滾動陰影 ── */
  function onScroll() {
    if (window.scrollY > 8) nav.classList.add("is-scrolled");
    else nav.classList.remove("is-scrolled");
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ── 進場揭示：卡片／區塊淡入上浮 ── */
  function setupReveal() {
    var candidates = document.querySelectorAll(
      "main.page .section-h2, main.page .section-sub, main.page .card-grid > *, " +
        "main.page .weapon-grid > *, main.page .sys-grid > *, main.page .equip-grid > *, " +
        "main.page .gallery-grid > *, main.page .panel, main.page .wt-layout, " +
        "main.page .card-grid, main.page .weapon-grid"
    );
    candidates.forEach(function (node) {
      if (!node.classList.contains("reveal")) node.classList.add("reveal");
    });

    /* 網格子項錯開 */
    document.querySelectorAll(".card-grid, .weapon-grid, .sys-grid, .equip-grid, .gallery-grid").forEach(function (grid) {
      grid.classList.add("reveal-stagger");
      Array.prototype.forEach.call(grid.children, function (child) {
        if (!child.classList.contains("reveal")) child.classList.add("reveal");
      });
    });

    if (reduceMotion || !("IntersectionObserver" in window)) {
      document.querySelectorAll(".reveal").forEach(function (n) {
        n.classList.add("is-in");
      });
      return;
    }

    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    document.querySelectorAll(".reveal").forEach(function (n) {
      io.observe(n);
    });
  }

  /* ── 滑鼠微傾（桌面卡片，很克制）── */
  function setupTilt() {
    if (reduceMotion || window.matchMedia("(hover: none)").matches) return;
    var cards = document.querySelectorAll("a.card, .weapon-card, .sys-card, .equip-card");
    cards.forEach(function (card) {
      card.addEventListener("pointermove", function (e) {
        var r = card.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width - 0.5;
        var y = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform =
          "translateY(-6px) rotateX(" + (-y * 4).toFixed(2) + "deg) rotateY(" + (x * 5).toFixed(2) + "deg)";
        card.classList.add("is-hover");
      });
      card.addEventListener("pointerleave", function () {
        card.style.transform = "";
        card.classList.remove("is-hover");
      });
    });
    /* 透視父層 */
    document.querySelectorAll(".card-grid, .weapon-grid, .sys-grid, .equip-grid").forEach(function (g) {
      g.style.perspective = "900px";
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      setupReveal();
      setupTilt();
    });
  } else {
    setupReveal();
    setupTilt();
  }
})();
