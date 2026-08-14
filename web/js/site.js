/* 共用導覽與版本 */
(function () {
  var cfg = window.BRAVESOUL || {};
  var path = location.pathname.replace(/\\/g, "/");
  var depth = (path.match(/\/pages\//) ? ".." : ".");
  var links = [
    { href: depth + "/index.html", id: "home", label: "首頁" },
    { href: depth + "/pages/weapons.html", id: "weapons", label: "武器流派" },
    { href: depth + "/pages/systems.html", id: "systems", label: "養成系統" },
    { href: depth + "/pages/guide.html", id: "guide", label: "遊戲指南" },
    { href: depth + "/pages/gallery.html", id: "gallery", label: "畫面" },
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
      '<a class="logo" href="' + depth + '/index.html"><span class="logo-mark" aria-hidden="true">🐇</span><span>翠嶺·兔勇者</span></a>' +
      '<div class="gnb-menu" id="gnb-menu"></div>' +
      '<div class="gnb-actions"><span class="ver-pill" id="ver">v0.13</span>' +
      '<a class="btn btn-primary" href="' + depth + '/pages/account.html">開始／帳號</a></div>' +
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

  var ver = document.getElementById("ver");
  if (ver && cfg.version) ver.textContent = "v" + cfg.version;

  var foot = el(
    '<footer><div class="container footer-inner">' +
      "<div>翠嶺大陸 · 黑焰未熄 · bravesoul-game</div>" +
      '<div><a href="' + depth + '/index.html">首頁</a> · <a href="' + depth + '/pages/account.html">帳號</a></div>' +
      "</div></footer>"
  );
  document.body.appendChild(foot);
})();
