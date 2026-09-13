// The settings sidebar: a schema-driven editor for a theme's tokens and the
// options of whatever the frame is showing — a page's or a post's. Tokens and
// options live in their own tabs. It is a port of the platform's settings form
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
  // Options are edited on the content item itself, so the Content tab and the
  // options tab are two views of one model — no second copy to drift.
  var tab = "content"; // which tab is open: "content", "tokens" or "options"
  var tokenTimer = null;
  var optionTimer = null;
  var contentTimer = null;
  var content = { posts: [], pages: [], templates: [] };
  var openContent = {}; // which content items are expanded, kept across saves
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
        content = clone(data.content);
        hydrateContent();
        if (tab === "options" && !data.settings) tab = "content";
        if (fileLabel) fileLabel.textContent = data.settings_file;
        render();
      })
      .catch(function () {
        body.innerHTML = '<p class="mh-note">The theme failed to load. Fix the error shown in the frame.</p>';
      });
  }

  // Debounced so typing a value is one save per pause, not one per keystroke.
  function saveTokens() {
    clearTimeout(tokenTimer);

    tokenTimer = setTimeout(function () {
      note("Saving…");

      fetch("/__preview/settings", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ tokens: tokens })
      })
        .then(function () {
          reloadFrame();
          note(null);
        })
        .catch(function () {
          note("Could not write the settings file.");
        });
    }, 180);
  }

  // Content is posted whole: the list the sidebar shows was seeded from
  // whatever was rendering, so sending it back makes the sidebar its owner.
  function saveContent(kind, refresh) {
    clearTimeout(contentTimer);

    contentTimer = setTimeout(function () {
      note("Saving…");

      fetch("/__preview/settings", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ content: { kind: kind, items: content[kind] } })
      })
        .then(function () {
          // Adding or removing changes the route list, so the sidebar has to
          // catch up. A field edit must not: rebuilding it mid-word would take
          // the focus out of the input being typed into.
          return refresh ? loadState() : null;
        })
        .then(function () {
          reloadFrame();
          note(null);
        })
        .catch(function () {
          note("Could not write the settings file.");
        });
    }, 220);
  }

  // List fields need their per-item `_id`s before they can be edited.
  function hydrateContent() {
    ["posts", "pages"].forEach(function (kind) {
      content[kind].forEach(function (item) {
        item.options = hydrate(item.options || {}, optionFields(kind, item));
      });
    });
  }

  // A post's option schema is the manifest's; a page's is its sidecar config
  // when it is a theme page, and the manifest's otherwise.
  function optionFields(kind, item) {
    if (kind === "posts") return content.post_fields || [];
    if (item.format !== "theme") return content.page_fields || [];

    var config = (content.page_configs || {})[item.template];
    return config ? config.fields : [];
  }

  function saveOptions(kind, item) {
    clearTimeout(optionTimer);

    optionTimer = setTimeout(function () {
      note("Saving…");

      fetch("/__preview/settings", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          settings: {
            kind: kind === "posts" ? "post" : "page",
            slug: item.slug,
            options: strip(item.options)
          }
        })
      })
        .then(function () {
          reloadFrame();
          note(null);
        })
        .catch(function () {
          note("Could not write the settings file.");
        });
    }, 180);
  }

  // The item the frame is currently showing, so the options tab and the
  // Content tab edit the same object.
  function framedItem() {
    if (!state.settings) return null;
    var kind = state.settings.kind === "post" ? "posts" : "pages";

    var item = content[kind].filter(function (candidate) {
      return candidate.slug === state.settings.slug;
    })[0];

    return item ? { kind: kind, item: item } : null;
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
    body.appendChild(tabBar());
    body.appendChild(paneFor(tab));
    pathLabel.textContent = path;
  }

  // Theme tokens are always editable; the options tab is whatever the frame is
  // showing — a page or a post — and is absent on the post list and search.
  function tabBar() {
    var nav = el("div", "mh-tabs");

    tabs().forEach(function (entry) {
      var button = el("button", "mh-tab" + (entry.id === tab ? " mh-tab-on" : ""));
      button.type = "button";
      button.textContent = entry.label;
      button.addEventListener("click", function () {
        tab = entry.id;
        render();
      });
      nav.appendChild(button);
    });

    return nav;
  }

  function tabs() {
    var entries = [
      { id: "content", label: "Content" },
      { id: "tokens", label: "Theme" }
    ];

    if (state.settings) {
      entries.push({
        id: "options",
        label: state.settings.kind === "post" ? "Post options" : "Page options"
      });
    }

    return entries;
  }

  function paneFor(which) {
    if (which === "options") return optionsPane();
    if (which === "content") return contentPane();
    return tokensPane();
  }

  function tokensPane() {
    if (!state.tokens.fields.length) {
      return pane(note_("This theme declares no tokens."));
    }

    return pane(
      fieldsNode(state.tokens.fields, tokens, function () {
        saveTokens();
      }, "tokens")
    );
  }

  function optionsPane() {
    var framed = framedItem();
    var label = state.settings.kind === "post" ? "post" : "page";

    if (!framed) {
      return pane(note_("This " + label + " is not in the preview content."));
    }

    var fields = optionFields(framed.kind, framed.item);

    if (!fields.length) {
      return pane(note_("This " + label + " declares no options."));
    }

    var wrap = el("div");
    wrap.appendChild(subtitle(state.settings.label));

    if (state.settings.description) {
      wrap.appendChild(note_(state.settings.description));
    }

    wrap.appendChild(
      fieldsNode(fields, framed.item.options, function () {
        saveOptions(framed.kind, framed.item);
      }, "options")
    );

    return pane(wrap);
  }

  // The preview's own posts and pages, editable in place. What you see here is
  // whatever is rendering — the built-in samples, your preview.json, or your
  // earlier edits — and changing anything makes preview.local.json own it.
  function contentPane() {
    var wrap = el("div");

    wrap.appendChild(contentList("posts", "Posts", "Post", postFields));
    wrap.appendChild(contentList("pages", "Pages", "Page", pageFields));

    return pane(wrap);
  }

  function contentList(kind, heading, itemLabel, fieldsFor) {
    var wrap = el("div", "mh-content");
    var head = el("div", "mh-content-head");
    var title = el("h3");
    title.textContent = heading;

    var add = el("button", "mh-add");
    add.type = "button";
    add.textContent = "+ " + itemLabel;
    add.addEventListener("click", function () {
      var fresh = blankContent(kind);
      fresh.options = hydrate({}, optionFields(kind, fresh));
      content[kind].push(fresh);
      openContent[kind + ":" + (content[kind].length - 1)] = true;
      saveContent(kind, true);
      render();
    });

    head.appendChild(title);
    head.appendChild(add);
    wrap.appendChild(head);

    if (!content[kind].length) {
      wrap.appendChild(note_("No " + heading.toLowerCase() + " yet."));
      return wrap;
    }

    content[kind].forEach(function (item, index) {
      wrap.appendChild(contentItem(kind, itemLabel, item, index, fieldsFor(item)));
    });

    return wrap;
  }

  function contentItem(kind, itemLabel, item, index, fields) {
    var box = el("details", "mh-group");
    var summary = el("summary");
    summary.textContent = item.title || itemLabel + " " + (index + 1);
    box.appendChild(summary);

    var openKey = kind + ":" + index;
    box.open = openContent[openKey] === true;
    box.addEventListener("toggle", function () {
      openContent[openKey] = box.open;
    });

    var inner = el("div");

    fields.forEach(function (field) {
      inner.appendChild(
        scalarNode(field, {
          get: function () {
            return field.read ? field.read(item) : item[field.key];
          },
          set: function (value) {
            if (field.write) field.write(item, value);
            else item[field.key] = value;
            summary.textContent = item.title || itemLabel + " " + (index + 1);
            saveContent(kind, false);
            if (field.rerender) render();
          }
        })
      );
    });

    var optionsFor = optionFields(kind, item);

    if (optionsFor.length) {
      var heading = el("p", "mh-subtitle");
      heading.textContent = itemLabel + " options";
      inner.appendChild(heading);

      inner.appendChild(
        fieldsNode(optionsFor, item.options, function () {
          saveOptions(kind, item);
        }, kind + ":" + index)
      );
    }

    var remove = el("button", "mh-remove");
    remove.type = "button";
    remove.textContent = "Remove " + itemLabel.toLowerCase();
    remove.addEventListener("click", function () {
      content[kind].splice(content[kind].indexOf(item), 1);
      openContent = {};
      saveContent(kind, true);
      render();
    });

    inner.appendChild(remove);
    box.appendChild(inner);
    return box;
  }

  function postFields() {
    return [
      { key: "title", label: "Title", type: "string" },
      { key: "slug", label: "Slug", type: "string", description: "Its URL: /posts/<slug>" },
      { key: "excerpt", label: "Excerpt", type: "text" },
      { key: "published_at", label: "Published", type: "string", description: "YYYY-MM-DD" },
      {
        key: "tags",
        label: "Tags",
        type: "string",
        description: "Comma separated",
        read: function (item) {
          return (item.tags || []).join(", ");
        },
        write: function (item, value) {
          item.tags = String(value)
            .split(",")
            .map(function (t) {
              return t.trim();
            })
            .filter(Boolean);
        }
      },
      { key: "format", label: "Format", type: "select", options: ["markdown", "html"] },
      { key: "body", label: "Body", type: "text" }
    ];
  }

  function pageFields(item) {
    var fields = [
      { key: "title", label: "Title", type: "string" },
      { key: "slug", label: "Slug", type: "string", description: "Its URL: /<slug>" },
      {
        key: "format",
        label: "Format",
        type: "select",
        options: ["markdown", "html", "theme"],
        // A theme page picks a template instead of carrying a body, so the
        // field list below changes with this one.
        rerender: true
      }
    ];

    if (item.format === "theme") {
      fields.push({
        key: "template",
        label: "Template",
        type: "select",
        options: content.templates,
        description: "From templates/pages/"
      });
    } else {
      fields.push({ key: "body", label: "Body", type: "text" });
    }

    fields.push({ key: "show_in_nav", label: "Show in nav", type: "boolean" });
    return fields;
  }

  function blankContent(kind) {
    if (kind === "posts") {
      return {
        title: "New post",
        slug: "new-post-" + (content.posts.length + 1),
        excerpt: "",
        format: "markdown",
        published_at: new Date().toISOString().slice(0, 10),
        tags: [],
        body: "Lorem ipsum dolor sit amet."
      };
    }

    return {
      title: "New page",
      slug: "new-page-" + (content.pages.length + 1),
      format: "markdown",
      template: null,
      show_in_nav: true,
      body: "Lorem ipsum dolor sit amet."
    };
  }

  function pane(node) {
    var wrap = el("section", "mh-section");
    wrap.appendChild(node);
    return wrap;
  }

  function subtitle(text) {
    var node = el("p", "mh-subtitle");
    node.textContent = text;
    return node;
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

    return section("Viewing", select);
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
