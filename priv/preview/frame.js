// Injected into every raw theme page the preview serves. Deliberately tiny:
// the theme's own document should stay as close to production as possible.
(function () {
  var path = window.location.pathname + window.location.search;

  // Viewed directly (a link, a bookmark, a refresh of the raw URL) → hand over
  // to the editor shell so you always get the sidebar with it.
  if (window.top === window.self) {
    window.location.replace("/__preview?path=" + encodeURIComponent(path));
    return;
  }

  // Inside the shell's frame: tell it where we are, so the sidebar can switch
  // to this page's settings when you click through the theme's own nav.
  try {
    window.parent.postMessage({ mh: "path", path: path }, window.location.origin);
  } catch (e) {}

  // A settings change re-renders by reloading this frame. Carry the scroll
  // position across so editing a footer token doesn't throw you back to the top.
  var KEY = "__mh_scroll:" + path;

  try {
    var saved = sessionStorage.getItem(KEY);
    if (saved) {
      sessionStorage.removeItem(KEY);
      window.scrollTo(0, parseInt(saved, 10) || 0);
    }
  } catch (e) {}

  window.addEventListener("beforeunload", function () {
    try {
      sessionStorage.setItem(KEY, String(window.scrollY));
    } catch (e) {}
  });
})();
