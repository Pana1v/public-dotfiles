  // Edit this list. The hotkey fires when the search box is not focused.
  const LINKS = [
    { key: "g", name: "github",   url: "https://github.com" },
    { key: "l", name: "linear",   url: "https://linear.app" },
    { key: "c", name: "claude",   url: "https://claude.ai" },
    { key: "m", name: "mail",     url: "https://mail.google.com" },
    { key: "k", name: "calendar", url: "https://calendar.google.com" },
    { key: "d", name: "drive",    url: "https://drive.google.com" },
    { key: "y", name: "youtube",  url: "https://www.youtube.com" },
    { key: "h", name: "hacker news", url: "https://news.ycombinator.com" },
  ];
  const SEARCH = "https://search.brave.com/search?q=";

  const $ = (id) => document.getElementById(id);
  const pad = (n) => String(n).padStart(2, "0");

  function tick() {
    const d = new Date();
    const h = d.getHours();
    $("clock").textContent = pad(h) + ":" + pad(d.getMinutes());
    $("date").textContent = d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" });
    $("greet").textContent = h < 5 ? "Late night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    const start = new Date(d.getFullYear(), 0, 1);
    $("week").textContent = "day " + (Math.floor((d - start) / 864e5) + 1);
  }
  tick(); setInterval(tick, 10000);

  $("links").innerHTML = LINKS.map(l =>
    `<a href="${l.url}"><span>${l.name}</span><kbd>${l.key}</kbd></a>`).join("");

  $("search").addEventListener("submit", (e) => {
    e.preventDefault();
    const v = $("q").value.trim();
    if (!v) return;
    const looksLikeUrl = /^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(v) || /^https?:\/\//.test(v);
    location.href = looksLikeUrl ? (/^https?:/.test(v) ? v : "https://" + v) : SEARCH + encodeURIComponent(v);
  });

  addEventListener("keydown", (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (document.activeElement === $("q")) return;
    if (e.key === "/") { e.preventDefault(); $("q").focus(); return; }
    const hit = LINKS.find(l => l.key === e.key.toLowerCase());
    if (hit) location.href = hit.url;
    else if (e.key.length === 1) $("q").focus();   // any other letter starts a search
  });
