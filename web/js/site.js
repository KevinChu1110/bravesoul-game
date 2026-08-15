/* 共用導覽與頁尾 */
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
})();
