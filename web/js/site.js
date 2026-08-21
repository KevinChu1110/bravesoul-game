/* 共用導覽、頁尾、全站動效（捲動 / 游標 / 進場） */
(function () {
  var cfg = window.BRAVESOUL || {};
  var brand = cfg.name || "勇者之魂";
  var path = location.pathname.replace(/\\/g, "/");
  var depth = path.match(/\/pages\//) ? ".." : ".";
  var links = [
    { href: depth + "/index.html", id: "home", label: "首頁" },
    { href: depth + "/pages/weapons.html", id: "weapons", label: "流派" },
    { href: depth + "/pages/equipment.html", id: "equipment", label: "圖鑑" },
    { href: depth + "/pages/maps.html", id: "maps", label: "地圖" },
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
  var fineHover = window.matchMedia && window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  function el(html) {
    var t = document.createElement("template");
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  /* 確保 sections.css 有載入（舊頁沒手寫 link 時補上） */
  (function ensureSectionsCss() {
    var href = depth + "/css/sections.css";
    var found = false;
    Array.prototype.forEach.call(document.styleSheets, function () {});
    Array.prototype.forEach.call(document.querySelectorAll('link[rel="stylesheet"]'), function (l) {
      if ((l.getAttribute("href") || "").indexOf("sections.css") >= 0) found = true;
    });
    if (!found) {
      var link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = href;
      document.head.appendChild(link);
    }
  })();

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
      '/pages/download.html">下載</a></div>' +
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
      " · 傭兵團最弱的新人</div>" +
      '<div><a href="' +
      depth +
      '/index.html">首頁</a> · <a href="' +
      depth +
      '/pages/download.html">下載</a> · <a href="' +
      depth +
      '/pages/account.html">帳號</a>' +
      social +
      "</div>" +
      "</div></footer>"
  );
  document.body.appendChild(foot);

  /* 頂部捲動進度 */
  var bar = document.createElement("div");
  bar.className = "scroll-progress";
  document.body.appendChild(bar);

  /* 游標光暈 */
  var glow = null;
  if (fineHover && !reduceMotion) {
    glow = document.createElement("div");
    glow.className = "cursor-glow";
    document.body.appendChild(glow);
    var gx = 0,
      gy = 0,
      tx = 0,
      ty = 0;
    document.addEventListener(
      "pointermove",
      function (e) {
        tx = e.clientX;
        ty = e.clientY;
        glow.classList.add("is-on");
      },
      { passive: true }
    );
    document.addEventListener(
      "pointerleave",
      function () {
        glow.classList.remove("is-on");
      },
      { passive: true }
    );
    function tickGlow() {
      gx += (tx - gx) * 0.12;
      gy += (ty - gy) * 0.12;
      glow.style.transform = "translate(" + gx + "px," + gy + "px)";
      requestAnimationFrame(tickGlow);
    }
    requestAnimationFrame(tickGlow);
  }

  function onScroll() {
    if (window.scrollY > 8) nav.classList.add("is-scrolled");
    else nav.classList.remove("is-scrolled");
    var doc = document.documentElement;
    var max = doc.scrollHeight - doc.clientHeight;
    var p = max > 0 ? (window.scrollY / max) * 100 : 0;
    bar.style.width = p + "%";
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* 視差 */
  function setupParallax() {
    if (reduceMotion) return;
    var nodes = document.querySelectorAll(".parallax-media");
    if (!nodes.length) return;
    function update() {
      var vh = window.innerHeight;
      nodes.forEach(function (n) {
        var speed = parseFloat(n.getAttribute("data-parallax") || "0.1");
        var r = n.getBoundingClientRect();
        var mid = r.top + r.height / 2 - vh / 2;
        var y = mid * speed * -0.15;
        n.style.transform = "translate3d(0," + y.toFixed(1) + "px,0) scale(1.05)";
      });
    }
    window.addEventListener("scroll", update, { passive: true });
    update();
  }

  function setupReveal() {
    document.querySelectorAll(".band").forEach(function (b) {
      if (!b.classList.contains("reveal-band")) b.classList.add("reveal-band");
    });
    var candidates = document.querySelectorAll(
      "main.page .section-h2, main.page .section-sub, main.page .card-grid > *, " +
        "main.page .weapon-grid > *, main.page .sys-grid > *, main.page .equip-grid > *, " +
        "main.page .gallery-grid > *, main.page .panel, " +
        ".feature, .pillar, .bento__item, .tl-item, .stat, .keycap, .platform, " +
        ".sec-head, .weapon-spotlight, .gallery-hero, .cta-finale, .rail__card"
    );
    candidates.forEach(function (node) {
      if (!node.classList.contains("reveal")) node.classList.add("reveal");
    });
    document.querySelectorAll(".card-grid, .weapon-grid, .sys-grid, .equip-grid, .gallery-grid, .bento, .stats-row, .keys, .platform-stage").forEach(function (grid) {
      grid.classList.add("reveal-stagger");
      Array.prototype.forEach.call(grid.children, function (child) {
        if (!child.classList.contains("reveal")) child.classList.add("reveal");
      });
    });

    if (reduceMotion || !("IntersectionObserver" in window)) {
      document.querySelectorAll(".reveal, .reveal-band").forEach(function (n) {
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
      { rootMargin: "0px 0px -6% 0px", threshold: 0.06 }
    );
    document.querySelectorAll(".reveal, .reveal-band").forEach(function (n) {
      io.observe(n);
    });
  }

  function setupTilt() {
    if (reduceMotion || !fineHover) return;
    var cards = document.querySelectorAll(
      "a.card, .weapon-card, .sys-card, .equip-card, .platform, .rail__card, .bento__item"
    );
    cards.forEach(function (card) {
      if (card.__tiltBound) return;
      card.__tiltBound = true;
      card.addEventListener("pointermove", function (e) {
        var r = card.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width - 0.5;
        var y = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform =
          "translateY(-6px) rotateX(" +
          (-y * 5).toFixed(2) +
          "deg) rotateY(" +
          (x * 6).toFixed(2) +
          "deg)";
        card.classList.add("is-hover");
      });
      card.addEventListener("pointerleave", function () {
        card.style.transform = "";
        card.classList.remove("is-hover");
      });
    });
    document.querySelectorAll(".card-grid, .weapon-grid, .sys-grid, .equip-grid, .bento, .platform-stage, .rail").forEach(function (g) {
      g.style.perspective = "1000px";
    });
  }

  function setupHeroVideo() {
    var hero = document.querySelector(".hero--video");
    if (!hero) return;
    var v = hero.querySelector("video.bg-video");
    if (!v) return;
    var markReady = function () {
      hero.classList.add("hero-video-ready");
    };
    v.addEventListener("playing", markReady, { once: true });
    v.addEventListener("error", function () {
      /* 影片失敗時維持 poster 靜圖 */
      v.style.display = "none";
    });
    /* 有些瀏覽器 autoplay 延遲，主動 play 一次 */
    var p = v.play();
    if (p && typeof p.catch === "function") {
      p.catch(function () {});
    }
  }

  function boot() {
    setupReveal();
    setupTilt();
    setupParallax();
    setupHeroVideo();
  }

  window.BS_refreshMotion = function () {
    setupReveal();
    setupTilt();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
