/* 勇者之魂 · 完整攻略互動 */
(function () {
  "use strict";

  var STORAGE_KEY = "bravesoul_walkthrough_v1";
  var chapters = Array.prototype.slice.call(
    document.querySelectorAll(".wt-chapter[data-ch]")
  );
  var tocLinks = Array.prototype.slice.call(
    document.querySelectorAll(".wt-toc a[data-ch]")
  );
  var progressBar = document.querySelector(".wt-progress > i");
  var progressLabel = document.querySelector(".wt-progress-label");
  var total = chapters.length || 12;

  function loadState() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") || {};
    } catch (e) {
      return {};
    }
  }
  function saveState(s) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    } catch (e) {}
  }

  var state = loadState();
  if (!state.done) state.done = {};
  if (!state.checklist) state.checklist = {};
  if (!state.current) state.current = "1";

  function showChapter(id, pushHash) {
    id = String(id);
    var found = false;
    chapters.forEach(function (ch) {
      var on = ch.getAttribute("data-ch") === id;
      ch.classList.toggle("active", on);
      if (on) found = true;
    });
    if (!found && chapters[0]) {
      id = chapters[0].getAttribute("data-ch");
      chapters[0].classList.add("active");
    }
    tocLinks.forEach(function (a) {
      var cid = a.getAttribute("data-ch");
      a.classList.toggle("active", cid === id);
      a.classList.toggle("done", !!state.done[cid]);
    });
    state.current = id;
    state.done[id] = true;
    saveState(state);
    updateProgress();
    if (pushHash !== false) {
      try {
        history.replaceState(null, "", "#ch" + id);
      } catch (e) {}
    }
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function updateProgress() {
    var n = 0;
    for (var i = 1; i <= total; i++) {
      if (state.done[String(i)]) n++;
    }
    var pct = Math.round((n / total) * 100);
    if (progressBar) progressBar.style.width = pct + "%";
    if (progressLabel) {
      progressLabel.textContent = "已讀 " + n + " / " + total + " 章（" + pct + "%）";
    }
  }

  tocLinks.forEach(function (a) {
    a.addEventListener("click", function (e) {
      e.preventDefault();
      showChapter(a.getAttribute("data-ch"));
    });
  });

  document.querySelectorAll("[data-goto]").forEach(function (btn) {
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      showChapter(btn.getAttribute("data-goto"));
    });
  });

  /* hash 直達 */
  var hash = (location.hash || "").replace(/^#ch?/, "");
  if (hash && document.querySelector('.wt-chapter[data-ch="' + hash + '"]')) {
    showChapter(hash, false);
  } else {
    showChapter(state.current || "1", false);
  }

  /* 鍵盤左右翻章 */
  document.addEventListener("keydown", function (e) {
    if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
    var cur = parseInt(state.current, 10) || 1;
    if (e.key === "ArrowRight" || e.key === "PageDown") {
      if (cur < total) showChapter(String(cur + 1));
    } else if (e.key === "ArrowLeft" || e.key === "PageUp") {
      if (cur > 1) showChapter(String(cur - 1));
    }
  });

  /* 快捷鍵表 hover 高亮 */
  document.querySelectorAll(".wt-keys tbody tr").forEach(function (tr) {
    tr.addEventListener("mouseenter", function () {
      tr.classList.add("hl");
    });
    tr.addEventListener("mouseleave", function () {
      tr.classList.remove("hl");
    });
  });

  /* Lightbox */
  var lb = document.createElement("div");
  lb.className = "wt-lb";
  lb.setAttribute("role", "dialog");
  lb.setAttribute("aria-label", "放大圖片");
  lb.innerHTML = "<img alt='' />";
  document.body.appendChild(lb);
  var lbImg = lb.querySelector("img");
  document.querySelectorAll(".wt-figure img, .wt-realm img, .wt-shot img").forEach(function (img) {
    img.style.cursor = "zoom-in";
    img.addEventListener("click", function () {
      lbImg.src = img.getAttribute("src");
      lbImg.alt = img.getAttribute("alt") || "";
      lb.classList.add("show");
    });
  });
  lb.addEventListener("click", function () {
    lb.classList.remove("show");
    lbImg.src = "";
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") lb.classList.remove("show");
  });

  /* 起步 checklist 持久化 */
  document.querySelectorAll(".wt-checklist input[type=checkbox]").forEach(function (cb) {
    var id = cb.getAttribute("data-id") || cb.id;
    if (!id) return;
    if (state.checklist[id]) cb.checked = true;
    cb.addEventListener("change", function () {
      state.checklist[id] = !!cb.checked;
      saveState(state);
    });
  });

  /* 流派測驗 */
  var CLASS_META = {
    sword: { name: "劍 · 劍士", tag: "平衡的刃", tip: "上手最穩，裝備線完整，適合第一次通關。" },
    bow: { name: "弓 · 遊俠", tag: "等風的人", tip: "遠距安全；森林疾影域節奏特別合拍。" },
    magic: { name: "法 · 星法", tag: "把星屑當墨", tip: "技能倍率高，與抽魂戰魂疊加最好。" },
    fist: { name: "拳 · 拳師", tag: "破勢在勤", tip: "攻速破防快，打道場阿波很有感。" },
    axe: { name: "斧 · 斧衛", tag: "一擊要有重量", tip: "高單下，對重甲與石拳友善。" },
    hammer: { name: "鎚 · 鎚守", tag: "站到最後", tip: "血防最高向，鍛造也較穩；慢熱但耐打。" },
    spear: { name: "長槍 · 槍騎", tag: "比劍更長的一步", tip: "中距離卡位，對衝迎擊有加成。" },
    gun: { name: "火槍 · 火銃", tag: "一響定生死", tip: "爆發極高、容錯最低；適合同學熟機制後玩。" },
    dart: { name: "鏢 · 影鏢", tag: "真假同色的一手", tip: "高速連擊，看破白霧節奏很順。" },
    crystal: { name: "水晶 · 晶使", tag: "把護盾織成刃", tip: "生存續航向，魂槽親和，穩紮穩打。" },
  };

  var quiz = document.getElementById("wt-quiz");
  if (quiz) {
    var resultEl = quiz.querySelector(".wt-result");
    var resultTitle = quiz.querySelector(".wt-result h4");
    var resultBody = quiz.querySelector(".wt-result p");
    var submitBtn = quiz.querySelector("[data-quiz-submit]");
    var resetBtn = quiz.querySelector("[data-quiz-reset]");

    quiz.querySelectorAll(".wt-opts label").forEach(function (lab) {
      lab.addEventListener("click", function () {
        var name = lab.querySelector("input").name;
        quiz.querySelectorAll('input[name="' + name + '"]').forEach(function (inp) {
          inp.closest("label").classList.remove("picked");
        });
        lab.classList.add("picked");
      });
    });

    if (submitBtn) {
      submitBtn.addEventListener("click", function () {
        var scores = {};
        Object.keys(CLASS_META).forEach(function (k) {
          scores[k] = 0;
        });
        var qs = quiz.querySelectorAll(".wt-q");
        var answered = 0;
        qs.forEach(function (q) {
          var checked = q.querySelector("input:checked");
          if (!checked) return;
          answered++;
          var weights = (checked.getAttribute("data-w") || "").split(",");
          weights.forEach(function (w) {
            var parts = w.trim().split(":");
            var cls = parts[0];
            var pts = parseInt(parts[1], 10) || 1;
            if (scores[cls] !== undefined) scores[cls] += pts;
          });
        });
        if (answered < qs.length) {
          if (resultEl) {
            resultEl.classList.add("show");
            if (resultTitle) resultTitle.textContent = "還有題沒選完";
            if (resultBody) resultBody.textContent = "請把 " + qs.length + " 題都勾完再看推薦。";
          }
          return;
        }
        var best = "sword";
        var bestScore = -1;
        Object.keys(scores).forEach(function (k) {
          if (scores[k] > bestScore) {
            bestScore = scores[k];
            best = k;
          }
        });
        var meta = CLASS_META[best];
        if (resultEl) {
          resultEl.classList.add("show");
          if (resultTitle) resultTitle.textContent = "推薦你：" + meta.name;
          if (resultBody) {
            resultBody.innerHTML =
              "<em>「" +
              meta.tag +
              "」</em> — " +
              meta.tip +
              '　<a href="weapons.html">看完整流派對照</a>';
          }
        }
        state.quiz = best;
        saveState(state);
      });
    }
    if (resetBtn) {
      resetBtn.addEventListener("click", function () {
        quiz.querySelectorAll("input[type=radio]").forEach(function (r) {
          r.checked = false;
        });
        quiz.querySelectorAll(".wt-opts label").forEach(function (l) {
          l.classList.remove("picked");
        });
        if (resultEl) resultEl.classList.remove("show");
      });
    }
  }

  /* Boss 摺疊：記住展開 */
  document.querySelectorAll(".wt-boss").forEach(function (d) {
    var id = d.getAttribute("data-boss");
    if (id && state["boss_" + id]) d.open = true;
    d.addEventListener("toggle", function () {
      if (!id) return;
      state["boss_" + id] = d.open;
      saveState(state);
    });
  });

  /* 域卡片篩選 */
  var realmFilter = document.getElementById("wt-realm-filter");
  if (realmFilter) {
    realmFilter.addEventListener("change", function () {
      var v = realmFilter.value;
      document.querySelectorAll(".wt-realm").forEach(function (card) {
        var tag = card.getAttribute("data-realm") || "";
        card.style.display = !v || v === "all" || tag === v ? "" : "none";
      });
    });
  }

  updateProgress();
})();
