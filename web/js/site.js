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
  var vp = document.querySelector('meta[name="viewport"]');
  if (vp) {
    vp.setAttribute("content", "width=device-width, initial-scale=1, viewport-fit=cover");
  }

  var active = document.body.getAttribute("data-page") || "home";
  var reduceMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var fineHover = window.matchMedia && window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  function el(html) {
    var t = document.createElement("template");
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  /* 確保 sections.css / motion.css 有載入 */
  (function ensureCss() {
    ["sections.css", "motion.css", "rwd.css"].forEach(function (name) {
      var found = false;
      Array.prototype.forEach.call(document.querySelectorAll('link[rel="stylesheet"]'), function (l) {
        if ((l.getAttribute("href") || "").indexOf(name) >= 0) found = true;
      });
      if (!found) {
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = depth + "/css/" + name;
        document.head.appendChild(link);
      }
    });
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
      '<button type="button" class="gnb-toggle" id="gnb-toggle" aria-label="打開選單" aria-expanded="false" aria-controls="gnb-menu">' +
      "<span></span><span></span><span></span></button>" +
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

  (function setupMobileNav() {
    var toggle = document.getElementById("gnb-toggle");
    if (!toggle) return;
    function close() {
      nav.classList.remove("is-open");
      document.body.classList.remove("is-nav-lock");
      toggle.setAttribute("aria-expanded", "false");
      toggle.setAttribute("aria-label", "打開選單");
    }
    function open() {
      nav.classList.add("is-open");
      document.body.classList.add("is-nav-lock");
      toggle.setAttribute("aria-expanded", "true");
      toggle.setAttribute("aria-label", "關閉選單");
    }
    toggle.addEventListener("click", function () {
      if (nav.classList.contains("is-open")) close();
      else open();
    });
    menu.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", close);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") close();
    });
    window.addEventListener(
      "resize",
      function () {
        if (window.innerWidth > 1080) close();
      },
      { passive: true }
    );
  })();

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

  function setupAtmosphere() {
    if (reduceMotion) return;
    var emberSrc = depth + "/media/fx/ember_field.jpg";
    var wispSrc = depth + "/media/fx/flame_wisp.jpg";
    var dustSrc = depth + "/media/fx/soul_dust.jpg";
    document.querySelectorAll(".hero, .page-hero").forEach(function (host) {
      if (host.querySelector(".fx-layer")) return;
      var layer = document.createElement("div");
      layer.className = "fx-layer";
      layer.setAttribute("aria-hidden", "true");
      layer.innerHTML =
        '<img class="fx-ember" src="' + emberSrc + '" alt="" />' +
        '<img class="fx-wisp fx-wisp--l" src="' + wispSrc + '" alt="" />' +
        '<img class="fx-wisp fx-wisp--r" src="' + wispSrc + '" alt="" />' +
        '<canvas class="fx-embers"></canvas>';
      host.appendChild(layer);
      setupEmberCanvas(layer.querySelector("canvas"));
    });
    document.querySelectorAll(".band--ink").forEach(function (band) {
      if (band.querySelector(".fx-dust-bg")) return;
      var img = document.createElement("img");
      img.className = "fx-dust-bg";
      img.src = dustSrc;
      img.alt = "";
      img.setAttribute("aria-hidden", "true");
      band.insertBefore(img, band.firstChild);
      var w = document.createElement("img");
      w.className = "fx-wisp fx-wisp--l";
      w.src = wispSrc;
      w.alt = "";
      band.appendChild(w);
    });
  }

  function setupEmberCanvas(canvas) {
    if (!canvas || reduceMotion) return;
    var ctx = canvas.getContext("2d");
    if (!ctx) return;
    var dots = [];
    var running = true;
    function size() {
      var r = canvas.getBoundingClientRect();
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.max(1, Math.floor(r.width * dpr));
      canvas.height = Math.max(1, Math.floor(r.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var n = Math.max(18, Math.min(42, Math.floor(r.width / 28)));
      dots = [];
      for (var i = 0; i < n; i++) {
        dots.push({
          x: Math.random() * r.width,
          y: Math.random() * r.height,
          r: 0.6 + Math.random() * 1.8,
          s: 0.18 + Math.random() * 0.55,
          a: 0.25 + Math.random() * 0.55,
          hue: Math.random() < 0.35 ? "255,196,210" : "228,132,156",
        });
      }
    }
    size();
    window.addEventListener("resize", size, { passive: true });
    var vis = new IntersectionObserver(function (entries) {
      running = entries[0] && entries[0].isIntersecting;
    });
    vis.observe(canvas);
    function tick() {
      if (running) {
        var w = canvas.clientWidth;
        var h = canvas.clientHeight;
        ctx.clearRect(0, 0, w, h);
        dots.forEach(function (d) {
          d.y -= d.s;
          d.x += Math.sin(d.y * 0.02) * 0.25;
          if (d.y < -4) {
            d.y = h + 4;
            d.x = Math.random() * w;
          }
          ctx.beginPath();
          ctx.fillStyle = "rgba(" + d.hue + "," + d.a.toFixed(2) + ")";
          ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
          ctx.fill();
        });
      }
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  function setupMarquee() {
    if (reduceMotion) return;
    if (window.matchMedia && window.matchMedia("(max-width: 1080px)").matches) return;
    document.querySelectorAll(".rail").forEach(function (rail) {
      if (rail.dataset.marquee === "1") return;
      var kids = Array.prototype.slice.call(rail.children);
      if (kids.length < 3) return;
      kids.forEach(function (n) {
        rail.appendChild(n.cloneNode(true));
      });
      rail.classList.add("is-marquee");
      rail.dataset.marquee = "1";
    });
  }

  function setupCountUp() {
    if (reduceMotion || !("IntersectionObserver" in window)) return;
    document.querySelectorAll(".stat__n").forEach(function (el) {
      var raw = (el.textContent || "").trim();
      if (!/^\d+$/.test(raw)) return;
      var target = parseInt(raw, 10);
      el.textContent = "0";
      var io = new IntersectionObserver(function (entries) {
        if (!entries[0] || !entries[0].isIntersecting) return;
        io.disconnect();
        var start = performance.now();
        function step(now) {
          var t = Math.min(1, (now - start) / 900);
          var ease = 1 - Math.pow(1 - t, 3);
          el.textContent = String(Math.round(target * ease));
          if (t < 1) requestAnimationFrame(step);
        }
        requestAnimationFrame(step);
      }, { threshold: 0.4 });
      io.observe(el);
    });
  }

  function boot() {
    setupReveal();
    setupParallax();
    setupHeroVideo();
    setupAtmosphere();
    setupMarquee();
    setupTilt();
    setupCountUp();
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
