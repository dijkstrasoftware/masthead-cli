// The settings sidebar: a schema-driven editor for a theme's tokens and the
// current page's metadata. It is a port of the platform's own settings form
// (AdminLive.SettingsFields), so what you edit here is what a site owner will
// edit there — the same field types, the same containers, the same defaults.
//
// Every change goes to the server, which writes preview.local.json and re-renders
// the frame. Nothing is faked client-side: a `list` token that a template loops
// over produces exactly the HTML the platform would produce.
(function () {
  var view = document.getElementById("mh-view");
  var body = document.getElementById("mh-body");
  var pathLabel = document.getElementById("mh-path");
  var status = document.getElementById("mh-status");
  var fileLabel = document.getElementById("mh-file");
  var resetBtn = document.getElementById("mh-reset");

  var path = document.body.dataset.path || "/";
  var state = null; // the last /__preview/state payload
  var tokens = {}; // token values being edited
  var metadata = null; // current page's metadata values, or null
  var saveTimer = null;
  var itemSeq = 0;
  var openGroups = {}; // category accordion open-state, kept across rerenders

  // ---- server round-trip -------------------------------------------------

  function loadState() {
    return fetch("/__preview/state?path=" + encodeURIComponent(path))
      .then(function (res) {
        return res.json();
      })
      .then(function (data) {
        state = data;
        tokens = clone(data.tokens.values);
        metadata = data.page ? hydrate(clone(data.page.values), data.page.fields) : null;
        if (fileLabel) fileLabel.textContent = data.settings_file;
        render();
      })
      .catch(function () {
        body.innerHTML = '<p class="mh-note">The theme failed to load. Fix the error shown in the frame.</p>';
      });
  }

  // Debounced so typing a title is one save per pause, not one per keystroke.
  function save(immediate) {
    clearTimeout(saveTimer);
    var delay = immediate ? 0 : 180;

    saveTimer = setTimeout(function () {
      var payload = { tokens: tokens };

      if (state && state.page) {
        payload.page = { slug: state.page.slug, metadata: strip(metadata) };
      }

      note("Saving…");

      fetch("/__preview/settings", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload)
      })
        .then(function () {
          reloadFrame();
          note(null);
        })
        .catch(function () {
          note("Could not write the settings file.");
        });
    }, delay);
  }

  function reloadFrame() {
    try {
      view.contentWindow.location.reload();
    } catch (e) {
      view.src = view.src;
    }
  }

  function note(message) {
    if (!status) return;
    if (message) {
      status.textContent = message;
    } else {
      status.innerHTML =
        "Preview only &middot; saved to <code>" + (state ? state.settings_file : "") + "</code>";
    }
  }

  // ---- value helpers -----------------------------------------------------

  function clone(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value));
  }

  // Give each list item a client-side id so it survives add / remove / reorder.
  // The server strips these before writing (they are editor bookkeeping, not
  // theme data) — mirrors the `_id` the platform's form uses.
  function hydrate(values, fields) {
    (fields || []).forEach(function (field) {
      if (field.type !== "list") return;
      var items = Array.isArray(values[field.key]) ? values[field.key] : [];
      items.forEach(function (item) {
        item._id = ++itemSeq;
      });
      values[field.key] = items;
    });
    return values;
  }

  function strip(values) {
    return values === null ? {} : clone(values);
  }

  function blankItem(field) {
    var item = { _id: ++itemSeq };
    (field.fields || []).forEach(function (sub) {
      item[sub.key] = "";
    });
    return item;
  }

  // ---- rendering ---------------------------------------------------------

  function render() {
    body.innerHTML = "";
    body.appendChild(routeSection());

    if (state.tokens.fields.length) {
      body.appendChild(
        section("Theme tokens", fieldsNode(state.tokens.fields, tokens, function () {
          save();
        }, "tokens"))
      );
    }

    body.appendChild(pageSection());
    pathLabel.textContent = path;
  }

  function section(title, node) {
    var wrap = el("section", "mh-section");
    var h = el("h2");
    h.textContent = title;
    wrap.appendChild(h);
    wrap.appendChild(node);
    return wrap;
  }

  function routeSection() {
    var select = el("select");

    state.routes.forEach(function (route) {
      var option = el("option");
      option.value = route.path;
      option.textContent = route.label + " — " + route.kind;
      if (route.path === path) option.selected = true;
      select.appendChild(option);
    });

    select.addEventListener("change", function () {
      navigate(select.value);
    });

    return section("Page", select);
  }

  function pageSection() {
    if (!state.page) {
      return section(
        "Page settings",
        note_("This route has no page settings — it's the post list or a post.")
      );
    }

    if (!state.page.fields.length) {
      return section(
        "Page settings — " + state.page.label,
        note_("This page's template declares no settings.")
      );
    }

    var wrap = el("div");

    if (state.page.description) {
      wrap.appendChild(note_(state.page.description));
    }

    wrap.appendChild(
      fieldsNode(state.page.fields, metadata, function () {
        save();
      }, "page")
    );

    return section("Page settings — " + state.page.label, wrap);
  }

  // A field list, grouped into accordions when any field declares a category
  // (exactly how the platform's settings form groups them).
  function fieldsNode(fields, values, onChange, scope) {
    var wrap = el("div");
    var categorized = fields.some(function (f) {
      return f.category && f.category.trim() !== "";
    });

    if (!categorized) {
      fields.forEach(function (field) {
        wrap.appendChild(fieldNode(field, values, onChange));
      });
      return wrap;
    }

    var order = [];
    var groups = {};

    fields.forEach(function (field) {
      var cat = field.category && field.category.trim() !== "" ? field.category.trim() : "General";
      if (!groups[cat]) {
        groups[cat] = [];
        order.push(cat);
      }
      groups[cat].push(field);
    });

    order.forEach(function (cat, index) {
      var details = el("details", "mh-group");

      // Keep each group's open state across rerenders (adding a list item
      // rebuilds the DOM), so editing a list doesn't collapse its category
      // and throw you back to the first one. First group opens by default.
      var groupKey = scope + ":" + cat;
      var open = openGroups.hasOwnProperty(groupKey) ? openGroups[groupKey] : index === 0;
      details.open = open;
      openGroups[groupKey] = open;
      details.addEventListener("toggle", function () {
        openGroups[groupKey] = details.open;
      });

      var summary = el("summary");
      summary.textContent = cat;
      details.appendChild(summary);

      var inner = el("div");
      groups[cat].forEach(function (field) {
        inner.appendChild(fieldNode(field, values, onChange));
      });
      details.appendChild(inner);
      wrap.appendChild(details);
    });

    return wrap;
  }

  function fieldNode(field, values, onChange) {
    if (field.type === "object") return objectNode(field, values, onChange);
    if (field.type === "list") return listNode(field, values, onChange);

    return scalarNode(field, {
      get: function () {
        return values[field.key];
      },
      set: function (value) {
        values[field.key] = value;
        onChange();
      }
    });
  }

  // An `object`: one group of scalar subfields under a single key.
  function objectNode(field, values, onChange) {
    var wrap = el("fieldset", "mh-container");
    wrap.appendChild(legend(field));

    if (!values[field.key] || typeof values[field.key] !== "object") values[field.key] = {};
    var obj = values[field.key];

    (field.fields || []).forEach(function (sub) {
      wrap.appendChild(
        scalarNode(sub, {
          get: function () {
            return obj[sub.key];
          },
          set: function (value) {
            obj[sub.key] = value;
            onChange();
          }
        })
      );
    });

    return wrap;
  }

  // A `list`: a repeatable group with add / remove / drag-to-reorder.
  function listNode(field, values, onChange) {
    var wrap = el("fieldset", "mh-container");
    wrap.appendChild(legend(field));

    if (!Array.isArray(values[field.key])) values[field.key] = [];
    var items = values[field.key];

    var list = el("ul", "mh-items");
    var dragging = null;

    items.forEach(function (item, index) {
      var li = el("li", "mh-item");
      li.draggable = true;

      var head = el("div", "mh-item-head");
      var handle = el("span", "mh-drag");
      handle.textContent = "⠿ " + (field.item_label || field.label) + " " + (index + 1);
      var remove = el("button", "mh-remove");
      remove.type = "button";
      remove.textContent = "Remove";
      remove.addEventListener("click", function () {
        items.splice(items.indexOf(item), 1);
        onChange();
        rerender();
      });
      head.appendChild(handle);
      head.appendChild(remove);
      li.appendChild(head);

      (field.fields || []).forEach(function (sub) {
        li.appendChild(
          scalarNode(sub, {
            get: function () {
              return item[sub.key];
            },
            set: function (value) {
              item[sub.key] = value;
              onChange();
            }
          })
        );
      });

      li.addEventListener("dragstart", function () {
        dragging = item;
        li.classList.add("mh-dragging");
      });

      li.addEventListener("dragend", function () {
        dragging = null;
        li.classList.remove("mh-dragging");
      });

      li.addEventListener("dragover", function (event) {
        event.preventDefault();
      });

      li.addEventListener("drop", function (event) {
        event.preventDefault();
        if (!dragging || dragging === item) return;
        items.splice(items.indexOf(dragging), 1);
        items.splice(items.indexOf(item), 0, dragging);
        onChange();
        rerender();
      });

      list.appendChild(li);
    });

    wrap.appendChild(list);

    var add = el("button", "mh-btn");
    add.type = "button";
    add.textContent = "+ Add " + (field.item_label || field.label);
    add.addEventListener("click", function () {
      items.push(blankItem(field));
      onChange();
      rerender();
    });
    wrap.appendChild(add);

    return wrap;
  }

  // Adding, removing or reordering changes the shape of the form, so rebuild it
  // (scalar edits never do — they keep their input, and their focus).
  function rerender() {
    var scroll = body.scrollTop;
    render();
    body.scrollTop = scroll;
  }

  function legend(field) {
    var node = el("legend", "mh-legend");
    node.appendChild(document.createTextNode(field.label || field.key));
    if (field.description) {
      var small = el("small");
      small.textContent = field.description;
      node.appendChild(small);
    }
    return node;
  }

  // ---- scalar controls ---------------------------------------------------

  function scalarNode(field, bind) {
    var wrap = el("div", "mh-field");
    var value = bind.get();
    if (value === undefined || value === null) value = "";

    if (field.type === "boolean") {
      var row = el("label", "mh-check");
      var text = el("span");
      text.textContent = field.label || field.key;
      var box = el("input");
      box.type = "checkbox";
      box.checked = value === true || value === "true" || value === "on" || value === "1";
      box.addEventListener("change", function () {
        bind.set(box.checked);
      });
      row.appendChild(text);
      row.appendChild(box);
      wrap.appendChild(row);
      return describe(wrap, field);
    }

    wrap.appendChild(labelFor(field));

    if (field.type === "color") {
      var group = el("div", "mh-color");
      var swatch = el("input");
      swatch.type = "color";
      var hex = el("input");
      hex.type = "text";
      hex.value = value;
      if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(value)) swatch.value = value;

      swatch.addEventListener("input", function () {
        hex.value = swatch.value;
        bind.set(swatch.value);
      });

      hex.addEventListener("input", function () {
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(hex.value)) swatch.value = hex.value;
        bind.set(hex.value);
      });

      group.appendChild(swatch);
      group.appendChild(hex);
      wrap.appendChild(group);
      return describe(wrap, field);
    }

    if (field.type === "select") {
      var select = el("select");
      (field.options || []).forEach(function (option) {
        var node = el("option");
        node.value = option;
        node.textContent = option;
        if (String(option) === String(value)) node.selected = true;
        select.appendChild(node);
      });
      select.addEventListener("change", function () {
        bind.set(select.value);
      });
      wrap.appendChild(select);
      return describe(wrap, field);
    }

    if (field.type === "text") {
      var area = el("textarea");
      area.value = value;
      area.addEventListener("input", function () {
        bind.set(area.value);
      });
      wrap.appendChild(area);
      return describe(wrap, field);
    }

    if (field.type === "file") {
      wrap.appendChild(fileControl(field, bind, value));
      return describe(wrap, field);
    }

    var input = el("input");
    input.type = field.type === "number" ? "number" : field.type === "url" ? "url" : "text";
    input.value = value;
    if (field.default !== null && field.default !== undefined && field.default !== "") {
      input.placeholder = String(field.default);
    }
    input.addEventListener("input", function () {
      bind.set(input.value);
    });
    wrap.appendChild(input);
    return describe(wrap, field);
  }

  // On the platform a `file` field holds an upload id. There are no uploads
  // locally, so the value is the URL/path used verbatim: pick one of the theme's
  // own assets, or type any URL.
  function fileControl(field, bind, value) {
    var group = el("div", "mh-file");

    var select = el("select");
    var none = el("option");
    none.value = "";
    none.textContent = "— no file —";
    select.appendChild(none);

    (state.assets || []).forEach(function (asset) {
      var option = el("option");
      option.value = asset;
      option.textContent = asset;
      if (asset === value) option.selected = true;
      select.appendChild(option);
    });

    var custom = el("option");
    custom.value = "__custom";
    custom.textContent = "— custom URL —";
    if (value && (state.assets || []).indexOf(value) === -1) custom.selected = true;
    select.appendChild(custom);

    var text = el("input");
    text.type = "text";
    text.placeholder = "https://… or /assets/…";
    text.value = value;
    text.hidden = select.value !== "__custom";

    var preview = el("img");
    preview.alt = "";
    preview.hidden = !isImage(value);
    if (value) preview.src = value;

    function commit(next) {
      preview.hidden = !isImage(next);
      if (next) preview.src = next;
      bind.set(next);
    }

    select.addEventListener("change", function () {
      if (select.value === "__custom") {
        text.hidden = false;
        text.focus();
        commit(text.value);
      } else {
        text.hidden = true;
        text.value = select.value;
        commit(select.value);
      }
    });

    text.addEventListener("input", function () {
      commit(text.value);
    });

    group.appendChild(select);
    group.appendChild(text);
    group.appendChild(preview);
    return group;
  }

  function isImage(value) {
    return typeof value === "string" && /\.(png|jpe?g|gif|webp|svg|ico)$/i.test(value);
  }

  function labelFor(field) {
    var label = el("label");
    label.appendChild(document.createTextNode(field.label || field.key));
    var code = el("code");
    code.textContent = field.key;
    label.appendChild(code);
    return label;
  }

  function describe(wrap, field) {
    if (field.description && field.type !== "object" && field.type !== "list") {
      var small = el("small");
      small.textContent = field.description;
      wrap.appendChild(small);
    }
    return wrap;
  }

  function note_(message) {
    var node = el("p", "mh-note");
    node.textContent = message;
    return node;
  }

  function el(tag, className) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    return node;
  }

  // ---- navigation + live reload ------------------------------------------

  function navigate(next) {
    path = next;
    view.src = next;
    loadState();
  }

  // The frame reports its own path, so clicking a link in the theme's nav swaps
  // the sidebar to that page's settings.
  window.addEventListener("message", function (event) {
    if (event.origin !== window.location.origin) return;
    if (!event.data || event.data.mh !== "path") return;
    if (event.data.path === path) return;

    path = event.data.path;
    loadState();
  });

  // A saved .liquid / .css / manifest edit reloads the frame by itself, and
  // re-reads the schema (the manifest may have grown a token).
  var events = new EventSource("/__preview/events");
  events.addEventListener("reload", function () {
    reloadFrame();
    loadState();
  });

  resetBtn.addEventListener("click", function () {
    fetch("/__preview/reset", { method: "POST" }).then(function () {
      loadState().then(reloadFrame);
    });
  });

  loadState();
})();
