!(function ($) {
    var lm = { config: {}, container: {}, controls: {}, errors: {}, items: {}, utils: {} };
    (lm.utils.F = function () {}),
        (lm.utils.extend = function (t, e) {
            (t.prototype = lm.utils.createObject(e.prototype)), (t.prototype.contructor = t);
        }),
        (lm.utils.createObject = function (t) {
            return "function" == typeof Object.create ? Object.create(t) : ((lm.utils.F.prototype = t), new lm.utils.F());
        }),
        (lm.utils.objectKeys = function (t) {
            var e, i;
            if ("function" == typeof Object.keys) return Object.keys(t);
            e = [];
            for (i in t) e.push(i);
            return e;
        }),
        (lm.utils.getHashValue = function (t) {
            var e = location.hash.match(new RegExp(t + "=([^&]*)"));
            return e ? e[1] : null;
        }),
        (lm.utils.getQueryStringParam = function (t) {
            if (window.location.hash) return lm.utils.getHashValue(t);
            if (!window.location.search) return null;
            var e,
                i,
                n = window.location.search.substr(1).split("&"),
                s = {};
            for (i = 0; i < n.length; i++) (e = n[i].split("=")), (s[e[0]] = e[1]);
            return s[t] || null;
        }),
        (lm.utils.copy = function (t, e) {
            for (var i in e) t[i] = e[i];
            return t;
        }),
        (lm.utils.animFrame = function (t) {
            return (
                window.requestAnimationFrame ||
                window.webkitRequestAnimationFrame ||
                window.mozRequestAnimationFrame ||
                function (t) {
                    window.setTimeout(t, 1e3 / 60);
                }
            )(function () {
                t();
            });
        }),
        (lm.utils.indexOf = function (t, e) {
            if (!(e instanceof Array)) throw new Error("Haystack is not an Array");
            if (e.indexOf) return e.indexOf(t);
            for (var i = 0; i < e.length; i++) if (e[i] === t) return i;
            return -1;
        }),
        "function" != typeof /./ && "object" != typeof Int8Array
            ? (lm.utils.isFunction = function (t) {
                  return "function" == typeof t || !1;
              })
            : (lm.utils.isFunction = function (t) {
                  return "[object Function]" === toString.call(t);
              }),
        (lm.utils.fnBind = function (t, e, i) {
            if (void 0 !== Function.prototype.bind) return Function.prototype.bind.apply(t, [e].concat(i || []));
            var n = function () {
                var s = (i || []).concat(Array.prototype.slice.call(arguments, 0));
                return this instanceof n ? void t.apply(this, s) : t.apply(e, s);
            };
            return (n.prototype = t.prototype), n;
        }),
        (lm.utils.removeFromArray = function (t, e) {
            var i = lm.utils.indexOf(t, e);
            if (i === -1) throw new Error("Can't remove item from array. Item is not in the array");
            e.splice(i, 1);
        }),
        (lm.utils.now = function () {
            return "function" == typeof Date.now ? Date.now() : new Date().getTime();
        }),
        (lm.utils.getUniqueId = function () {
            return (1e15 * Math.random()).toString(36).replace(".", "");
        }),
        (lm.utils.filterXss = function (t, e) {
            var i = t
                .replace(/javascript/gi, "j&#97;vascript")
                .replace(/expression/gi, "expr&#101;ssion")
                .replace(/onload/gi, "onlo&#97;d")
                .replace(/script/gi, "&#115;cript")
                .replace(/onerror/gi, "on&#101;rror");
            return e === !0 ? i : i.replace(/>/g, "&gt;").replace(/</g, "&lt;");
        }),
        (lm.utils.stripTags = function (t) {
            return $.trim(t.replace(/(<([^>]+)>)/gi, ""));
        }),
        (lm.utils.EventEmitter = function () {
            (this._mSubscriptions = {}),
                (this._mSubscriptions[lm.utils.EventEmitter.ALL_EVENT] = []),
                (this.on = function (t, e, i) {
                    if (!lm.utils.isFunction(e)) throw new Error("Tried to listen to event " + t + " with non-function callback " + e);
                    this._mSubscriptions[t] || (this._mSubscriptions[t] = []), this._mSubscriptions[t].push({ fn: e, ctx: i });
                }),
                (this.emit = function (t) {
                    var e, i, n;
                    if (((n = Array.prototype.slice.call(arguments, 1)), this._mSubscriptions[t])) for (e = 0; e < this._mSubscriptions[t].length; e++) (i = this._mSubscriptions[t][e].ctx || {}), this._mSubscriptions[t][e].fn.apply(i, n);
                    for (n.unshift(t), e = 0; e < this._mSubscriptions[lm.utils.EventEmitter.ALL_EVENT].length; e++)
                        (i = this._mSubscriptions[lm.utils.EventEmitter.ALL_EVENT][e].ctx || {}), this._mSubscriptions[lm.utils.EventEmitter.ALL_EVENT][e].fn.apply(i, n);
                }),
                (this.unbind = function (t, e, i) {
                    if (!this._mSubscriptions[t]) throw new Error("No subscribtions to unsubscribe for event " + t);
                    var n,
                        s = !1;
                    for (n = 0; n < this._mSubscriptions[t].length; n++) (e && this._mSubscriptions[t][n].fn !== e) || (i && i !== this._mSubscriptions[t][n].ctx) || (this._mSubscriptions[t].splice(n, 1), (s = !0));
                    if (s === !1) throw new Error("Nothing to unbind for " + t);
                }),
                (this.off = this.unbind),
                (this.trigger = this.emit);
        }),
        (lm.utils.EventEmitter.ALL_EVENT = "__all"),
        (lm.utils.DragListener = function (t, e) {
            lm.utils.EventEmitter.call(this),
                (this._eElement = $(t)),
                (this._oDocument = $(document)),
                (this._eBody = $(document.body)),
                (this._nButtonCode = e || 0),
                (this._nDelay = 200),
                (this._nDistance = 10),
                (this._nX = 0),
                (this._nY = 0),
                (this._nOriginalX = 0),
                (this._nOriginalY = 0),
                (this._bDragging = !1),
                (this._fMove = lm.utils.fnBind(this.onMouseMove, this)),
                (this._fUp = lm.utils.fnBind(this.onMouseUp, this)),
                (this._fDown = lm.utils.fnBind(this.onMouseDown, this)),
                this._eElement.on("mousedown touchstart", this._fDown);
        }),
        (lm.utils.DragListener.timeout = null),
        lm.utils.copy(lm.utils.DragListener.prototype, {
            destroy: function () {
                this._eElement.unbind("mousedown touchstart", this._fDown);
            },
            onMouseDown: function (t) {
                if ((t.preventDefault(), 0 == t.button || "touchstart" === t.type)) {
                    var e = this._getCoordinates(t);
                    (this._nOriginalX = e.x),
                        (this._nOriginalY = e.y),
                        this._oDocument.on("mousemove touchmove", this._fMove),
                        this._oDocument.one("mouseup touchend", this._fUp),
                        (this._timeout = setTimeout(lm.utils.fnBind(this._startDrag, this), this._nDelay));
                }
            },
            onMouseMove: function (t) {
                if (null != this._timeout) {
                    t.preventDefault();
                    var e = this._getCoordinates(t);
                    (this._nX = e.x - this._nOriginalX),
                        (this._nY = e.y - this._nOriginalY),
                        this._bDragging === !1 && (Math.abs(this._nX) > this._nDistance || Math.abs(this._nY) > this._nDistance) && (clearTimeout(this._timeout), this._startDrag()),
                        this._bDragging && this.emit("drag", this._nX, this._nY, t);
                }
            },
            onMouseUp: function (t) {
                null != this._timeout &&
                    (clearTimeout(this._timeout),
                    this._eBody.removeClass("lm_dragging"),
                    this._eElement.removeClass("lm_dragging"),
                    this._oDocument.find("iframe").css("pointer-events", ""),
                    this._oDocument.unbind("mousemove touchmove", this._fMove),
                    this._bDragging === !0 && ((this._bDragging = !1), this.emit("dragStop", t, this._nOriginalX + this._nX)));
            },
            _startDrag: function () {
                (this._bDragging = !0), this._eBody.addClass("lm_dragging"), this._eElement.addClass("lm_dragging"), this._oDocument.find("iframe").css("pointer-events", "none"), this.emit("dragStart", this._nOriginalX, this._nOriginalY);
            },
            _getCoordinates: function (t) {
                return (t = t.originalEvent && t.originalEvent.touches ? t.originalEvent.touches[0] : t), { x: t.pageX, y: t.pageY };
            },
        }),
        (lm.LayoutManager = function (t, e) {
            if (!$ || "function" != typeof $.noConflict) {
                var i = "jQuery is missing as dependency for GoldenLayout. ";
                throw ((i += 'Please either expose $ on GoldenLayout\'s scope (e.g. window) or add "jquery" to '), (i += "your paths when using RequireJS/AMD"), new Error(i));
            }
            lm.utils.EventEmitter.call(this),
                (this.isInitialised = !1),
                (this._isFullPage = !1),
                (this._resizeTimeoutId = null),
                (this._components = { "lm-react-component": lm.utils.ReactComponentHandler }),
                (this._itemAreas = []),
                (this._resizeFunction = lm.utils.fnBind(this._onResize, this)),
                (this._unloadFunction = lm.utils.fnBind(this._onUnload, this)),
                (this._maximisedItem = null),
                (this._maximisePlaceholder = $('<div class="lm_maximise_place"></div>')),
                (this._creationTimeoutPassed = !1),
                (this._subWindowsCreated = !1),
                (this._dragSources = []),
                (this._updatingColumnsResponsive = !1),
                (this._firstLoad = !0),
                (this.width = null),
                (this.height = null),
                (this.root = null),
                (this.openPopouts = []),
                (this.selectedItem = null),
                (this.isSubWindow = !1),
                (this.eventHub = new lm.utils.EventHub(this)),
                (this.config = this._createConfig(t)),
                (this.container = e),
                (this.dropTargetIndicator = null),
                (this.transitionIndicator = null),
                (this.tabDropPlaceholder = $('<div class="lm_drop_tab_placeholder"></div>')),
                this.isSubWindow === !0 && $("body").css("visibility", "hidden"),
                (this._typeToItem = { column: lm.utils.fnBind(lm.items.RowOrColumn, this, [!0]), row: lm.utils.fnBind(lm.items.RowOrColumn, this, [!1]), stack: lm.items.Stack, component: lm.items.Component });
        }),
        (lm.LayoutManager.__lm = lm),
        (lm.LayoutManager.minifyConfig = function (t) {
            return new lm.utils.ConfigMinifier().minifyConfig(t);
        }),
        (lm.LayoutManager.unminifyConfig = function (t) {
            return new lm.utils.ConfigMinifier().unminifyConfig(t);
        }),
        lm.utils.copy(lm.LayoutManager.prototype, {
            registerComponent: function (t, e) {
                if ("function" != typeof e) throw new Error("Please register a constructor function");
                if (void 0 !== this._components[t]) throw new Error("Component " + t + " is already registered");
                this._components[t] = e;
            },
            toConfig: function (t) {
                var e, i, n;
                if (this.isInitialised === !1) throw new Error("Can't create config, layout not yet initialised");
                if (t && !(t instanceof lm.items.AbstractContentItem)) throw new Error("Root must be a ContentItem");
                for (
                    e = { settings: lm.utils.copy({}, this.config.settings), dimensions: lm.utils.copy({}, this.config.dimensions), labels: lm.utils.copy({}, this.config.labels) },
                        e.content = [],
                        i = function (t, e) {
                            var n, s;
                            for (n in e.config) "content" !== n && (t[n] = e.config[n]);
                            if (e.contentItems.length) for (t.content = [], s = 0; s < e.contentItems.length; s++) (t.content[s] = {}), i(t.content[s], e.contentItems[s]);
                        },
                        t ? i(e, { contentItems: [t] }) : i(e, this.root),
                        this._$reconcilePopoutWindows(),
                        e.openPopouts = [],
                        n = 0;
                    n < this.openPopouts.length;
                    n++
                )
                    e.openPopouts.push(this.openPopouts[n].toConfig());
                return (e.maximisedItemId = this._maximisedItem ? "__glMaximised" : null), e;
            },
            getComponent: function (t) {
                if (void 0 === this._components[t]) throw new lm.errors.ConfigurationError('Unknown component "' + t + '"');
                return this._components[t];
            },
            init: function () {
                return (
                    this._subWindowsCreated === !1 && (this._createSubWindows(), (this._subWindowsCreated = !0)),
                    "loading" === document.readyState || null === document.body
                        ? void $(document).ready(lm.utils.fnBind(this.init, this))
                        : this.isSubWindow === !0 && this._creationTimeoutPassed === !1
                        ? (setTimeout(lm.utils.fnBind(this.init, this), 7), void (this._creationTimeoutPassed = !0))
                        : (this.isSubWindow === !0 && this._adjustToWindowMode(),
                          this._setContainer(),
                          (this.dropTargetIndicator = new lm.controls.DropTargetIndicator(this.container)),
                          (this.transitionIndicator = new lm.controls.TransitionIndicator()),
                          this.updateSize(),
                          this._create(this.config),
                          this._bindEvents(),
                          (this.isInitialised = !0),
                          this._adjustColumnsResponsive(),
                          void this.emit("initialised"))
                );
            },
            updateSize: function (t, e) {
                2 === arguments.length ? ((this.width = t), (this.height = e)) : ((this.width = this.container.width()), (this.height = this.container.height())),
                    this.isInitialised === !0 &&
                        (this.root.callDownwards("setSize", [this.width, this.height]),
                        this._maximisedItem && (this._maximisedItem.element.width(this.container.width()), this._maximisedItem.element.height(this.container.height()), this._maximisedItem.callDownwards("setSize")),
                        this._adjustColumnsResponsive());
            },
            destroy: function () {
                this.isInitialised !== !1 &&
                    (this._onUnload(),
                    $(window).off("resize", this._resizeFunction),
                    $(window).off("unload beforeunload", this._unloadFunction),
                    this.root.callDownwards("_$destroy", [], !0),
                    (this.root.contentItems = []),
                    this.tabDropPlaceholder.remove(),
                    this.dropTargetIndicator.destroy(),
                    this.transitionIndicator.destroy(),
                    this.eventHub.destroy(),
                    this._dragSources.forEach(function (t) {
                        t._dragListener.destroy(), (t._element = null), (t._itemConfig = null), (t._dragListener = null);
                    }),
                    (this._dragSources = []));
            },
            createContentItem: function (t, e) {
                var i, n;
                if ("string" != typeof t.type) throw new lm.errors.ConfigurationError("Missing parameter 'type'", t);
                if (("react-component" === t.type && ((t.type = "component"), (t.componentName = "lm-react-component")), !this._typeToItem[t.type]))
                    throw ((i = "Unknown type '" + t.type + "'. Valid types are " + lm.utils.objectKeys(this._typeToItem).join(",")), new lm.errors.ConfigurationError(i));
                return (
                    "component" !== t.type || e instanceof lm.items.Stack || !e || (this.isSubWindow === !0 && e instanceof lm.items.Root) || (t = { type: "stack", width: t.width, height: t.height, content: [t] }),
                    (n = new this._typeToItem[t.type](this, t, e))
                );
            },
            createPopout: function (t, e, i, n) {
                var s,
                    o,
                    r,
                    a,
                    h,
                    l,
                    m = t,
                    c = t instanceof lm.items.AbstractContentItem,
                    d = this;
                if (((i = i || null), c)) {
                    for (m = this.toConfig(t).content, i = lm.utils.getUniqueId(), a = t.parent, h = t; 1 === a.contentItems.length && !a.isRoot; ) (a = a.parent), (h = h.parent);
                    a.addId(i), isNaN(n) && (n = lm.utils.indexOf(h, a.contentItems));
                } else m instanceof Array || (m = [m]);
                return (
                    !e &&
                        c &&
                        ((s = window.screenX || window.screenLeft), (o = window.screenY || window.screenTop), (r = t.element.offset()), (e = { left: s + r.left, top: o + r.top, width: t.element.width(), height: t.element.height() })),
                    e || c || (e = { left: window.screenX || window.screenLeft + 20, top: window.screenY || window.screenTop + 20, width: 500, height: 309 }),
                    c && t.remove(),
                    (l = new lm.controls.BrowserPopout(m, e, i, n, this)),
                    l.on("initialised", function () {
                        d.emit("windowOpened", l);
                    }),
                    l.on("closed", function () {
                        d._$reconcilePopoutWindows();
                    }),
                    this.openPopouts.push(l),
                    l
                );
            },
            createDragSource: function (t, e) {
                this.config.settings.constrainDragToContainer = !1;
                var i = new lm.controls.DragSource($(t), e, this);
                return this._dragSources.push(i), i;
            },
            selectItem: function (t, e) {
                if (this.config.settings.selectionEnabled !== !0) throw new Error("Please set selectionEnabled to true to use this feature");
                t !== this.selectedItem && (null !== this.selectedItem && this.selectedItem.deselect(), t && e !== !0 && t.select(), (this.selectedItem = t), this.emit("selectionChanged", t));
            },
            _$maximiseItem: function (t) {
                null !== this._maximisedItem && this._$minimiseItem(this._maximisedItem),
                    (this._maximisedItem = t),
                    this._maximisedItem.addId("__glMaximised"),
                    t.element.addClass("lm_maximised"),
                    t.element.after(this._maximisePlaceholder),
                    this.root.element.prepend(t.element),
                    t.element.width(this.container.width()),
                    t.element.height(this.container.height()),
                    t.callDownwards("setSize"),
                    this._maximisedItem.emit("maximised"),
                    this.emit("stateChanged");
            },
            _$minimiseItem: function (t) {
                t.element.removeClass("lm_maximised"),
                    t.removeId("__glMaximised"),
                    this._maximisePlaceholder.after(t.element),
                    this._maximisePlaceholder.remove(),
                    t.parent.callDownwards("setSize"),
                    (this._maximisedItem = null),
                    t.emit("minimised"),
                    this.emit("stateChanged");
            },
            _$closeWindow: function () {
                window.setTimeout(function () {
                    window.close();
                }, 1);
            },
            _$getArea: function (t, e) {
                var i,
                    n,
                    s = 1 / 0,
                    o = null;
                for (i = 0; i < this._itemAreas.length; i++) (n = this._itemAreas[i]), t > n.x1 && t < n.x2 && e > n.y1 && e < n.y2 && s > n.surface && ((s = n.surface), (o = n));
                return o;
            },
            _$createRootItemAreas: function () {
                var areaSize = 50,
                    sides = { y2: 0, x2: 0, y1: "y2", x1: "x2" };
                for (side in sides) {
                    var area = this.root._$getArea();
                    with (((area.side = side), sides[side] ? (area[side] = area[sides[side]] - areaSize) : (area[side] = areaSize), area)) surface = (x2 - x1) * (y2 - y1);
                    this._itemAreas.push(area);
                }
            },
            _$calculateItemAreas: function () {
                var i,
                    area,
                    allContentItems = this._getAllContentItems();
                if (((this._itemAreas = []), 1 === allContentItems.length)) return void this._itemAreas.push(this.root._$getArea());
                for (this._$createRootItemAreas(), i = 0; i < allContentItems.length; i++)
                    if (allContentItems[i].isStack && ((area = allContentItems[i]._$getArea()), null !== area))
                        if (area instanceof Array) this._itemAreas = this._itemAreas.concat(area);
                        else {
                            this._itemAreas.push(area);
                            var header = {};
                            with ((lm.utils.copy(header, area), lm.utils.copy(header, area.contentItem._contentAreaDimensions.header.highlightArea), header)) surface = (x2 - x1) * (y2 - y1);
                            this._itemAreas.push(header);
                        }
            },
            _$normalizeContentItem: function (t, e) {
                if (!t) throw new Error("No content item defined");
                if ((lm.utils.isFunction(t) && (t = t()), t instanceof lm.items.AbstractContentItem)) return t;
                if ($.isPlainObject(t) && t.type) {
                    var i = this.createContentItem(t, e);
                    return i.callDownwards("_$init"), i;
                }
                throw new Error("Invalid contentItem");
            },
            _$reconcilePopoutWindows: function () {
                var t,
                    e = [];
                for (t = 0; t < this.openPopouts.length; t++) this.openPopouts[t].getWindow().closed === !1 ? e.push(this.openPopouts[t]) : this.emit("windowClosed", this.openPopouts[t]);
                this.openPopouts.length !== e.length && (this.emit("stateChanged"), (this.openPopouts = e));
            },
            _getAllContentItems: function () {
                var t = [],
                    e = function (i) {
                        if ((t.push(i), i.contentItems instanceof Array)) for (var n = 0; n < i.contentItems.length; n++) e(i.contentItems[n]);
                    };
                return e(this.root), t;
            },
            _bindEvents: function () {
                this._isFullPage && $(window).resize(this._resizeFunction), $(window).on("unload beforeunload", this._unloadFunction);
            },
            _onResize: function () {
                clearTimeout(this._resizeTimeoutId), (this._resizeTimeoutId = setTimeout(lm.utils.fnBind(this.updateSize, this), 100));
            },
            _createConfig: function (t) {
                var e = lm.utils.getQueryStringParam("gl-window");
                e && ((this.isSubWindow = !0), (t = localStorage.getItem(e)), (t = JSON.parse(t)), (t = new lm.utils.ConfigMinifier().unminifyConfig(t)), localStorage.removeItem(e)), (t = $.extend(!0, {}, lm.config.defaultConfig, t));
                var i = function (t) {
                    for (var e in t) "props" !== e && "object" == typeof t[e] ? i(t[e]) : "type" === e && "react-component" === t[e] && ((t.type = "component"), (t.componentName = "lm-react-component"));
                };
                return i(t), t.settings.hasHeaders === !1 && (t.dimensions.headerHeight = 0), t;
            },
            _adjustToWindowMode: function () {
                var t = $('<div class="lm_popin" title="' + this.config.labels.popin + '"><div class="lm_icon"></div><div class="lm_bg"></div></div>');
                t.click(
                    lm.utils.fnBind(function () {
                        this.emit("popIn");
                    }, this)
                ),
                    (document.title = lm.utils.stripTags(this.config.content[0].title)),
                    $("head").append($("body link, body style, template, .gl_keep")),
                    (this.container = $("body").html("").css("visibility", "visible").append(t));
                document.body.offsetHeight;
                window.__glInstance = this;
            },
            _createSubWindows: function () {
                var t, e;
                for (t = 0; t < this.config.openPopouts.length; t++) (e = this.config.openPopouts[t]), this.createPopout(e.content, e.dimensions, e.parentId, e.indexInParent);
            },
            _setContainer: function () {
                var t = $(this.container || "body");
                if (0 === t.length) throw new Error("GoldenLayout container not found");
                if (t.length > 1) throw new Error("GoldenLayout more than one container element specified");
                t[0] === document.body && ((this._isFullPage = !0), $("html, body").css({ height: "100%", margin: 0, padding: 0, overflow: "hidden" })), (this.container = t);
            },
            _create: function (t) {
                var e;
                if (!(t.content instanceof Array))
                    throw ((e = void 0 === t.content ? "Missing setting 'content' on top level of configuration" : "Configuration parameter 'content' must be an array"), new lm.errors.ConfigurationError(e, t));
                if (t.content.length > 1) throw ((e = "Top level content can't contain more then one element."), new lm.errors.ConfigurationError(e, t));
                (this.root = new lm.items.Root(this, { content: t.content }, this.container)), this.root.callDownwards("_$init"), "__glMaximised" === t.maximisedItemId && this.root.getItemsById(t.maximisedItemId)[0].toggleMaximise();
            },
            _onUnload: function () {
                if (this.config.settings.closePopoutsOnUnload === !0) for (var t = 0; t < this.openPopouts.length; t++) this.openPopouts[t].close();
            },
            _adjustColumnsResponsive: function () {
                if (!this._useResponsiveLayout() || this._updatingColumnsResponsive || !this.config.dimensions || !this.config.dimensions.minItemWidth || 0 === this.root.contentItems.length || !this.root.contentItems[0].isRow)
                    return void (this._firstLoad = !1);
                this._firstLoad = !1;
                var t = this.root.contentItems[0].contentItems.length;
                if (!(t <= 1)) {
                    var e = this.config.dimensions.minItemWidth,
                        i = t * e;
                    if (!(i <= this.width)) {
                        this._updatingColumnsResponsive = !0;
                        for (var n = Math.max(Math.floor(this.width / e), 1), s = t - n, o = this.root.contentItems[0], r = this._findAllStackContainers()[0], a = 0; a < s; a++) {
                            var h = o.contentItems[o.contentItems.length - 1];
                            o.removeChild(h), this._addChildContentItemsToContainer(r, h);
                        }
                        this._updatingColumnsResponsive = !1;
                    }
                }
            },
            _useResponsiveLayout: function () {
                return this.config.settings && ("always" == this.config.settings.responsiveMode || ("onload" == this.config.settings.responsiveMode && this._firstLoad));
            },
            _addChildContentItemsToContainer: function (t, e) {
                "stack" === e.type
                    ? e.contentItems.forEach(function (e) {
                          t.addChild(e);
                      })
                    : e.contentItems.forEach(
                          lm.utils.fnBind(function (e) {
                              this._addChildContentItemsToContainer(t, e);
                          }, this)
                      );
            },
            _findAllStackContainers: function () {
                var t = [];
                return this._findAllStackContainersRecursive(t, this.root), t;
            },
            _findAllStackContainersRecursive: function (t, e) {
                e.contentItems.forEach(
                    lm.utils.fnBind(function (e) {
                        "stack" == e.type ? t.push(e) : e.isComponent || this._findAllStackContainersRecursive(t, e);
                    }, this)
                );
            },
        }),
        (function () {
            "function" == typeof define && define.amd
                ? define(["jquery"], function (t) {
                      return ($ = t), lm.LayoutManager;
                  })
                : "object" == typeof exports
                ? (module.exports = lm.LayoutManager)
                : (window.GoldenLayout = lm.LayoutManager);
        })(),
        (lm.config.itemDefaultConfig = { isClosable: !0, reorderEnabled: !0, title: "" }),
        (lm.config.defaultConfig = {
            openPopouts: [],
            settings: {
                hasHeaders: !0,
                constrainDragToContainer: !0,
                reorderEnabled: !0,
                selectionEnabled: !1,
                popoutWholeStack: !1,
                blockedPopoutsThrowError: !0,
                closePopoutsOnUnload: !0,
                showPopoutIcon: !0,
                showMaximiseIcon: !0,
                showCloseIcon: !0,
                responsiveMode: "onload",
            },
            dimensions: { borderWidth: 5, minItemHeight: 10, minItemWidth: 10, headerHeight: 20, dragProxyWidth: 300, dragProxyHeight: 200 },
            labels: { close: "close", maximise: "maximise", minimise: "minimise", popout: "open in new window", popin: "pop in", tabDropdown: "additional tabs" },
        }),
        (lm.container.ItemContainer = function (t, e, i) {
            lm.utils.EventEmitter.call(this),
                (this.width = null),
                (this.height = null),
                (this.title = t.componentName),
                (this.parent = e),
                (this.layoutManager = i),
                (this.isHidden = !1),
                (this._config = t),
                (this._element = $(['<div class="lm_item_container">', '<div class="lm_content"></div>', "</div>"].join(""))),
                (this._contentElement = this._element.find(".lm_content"));
        }),
        lm.utils.copy(lm.container.ItemContainer.prototype, {
            getElement: function () {
                return this._contentElement;
            },
            hide: function () {
                this.emit("hide"), (this.isHidden = !0), this._element.hide();
            },
            show: function () {
                this.emit("show"), (this.isHidden = !1), this._element.show(), (0 == this.height && 0 == this.width) || this.emit("shown");
            },
            setSize: function (t, e) {
                for (var i, n, s, o, r, a, h = this.parent, l = this; !h.isColumn && !h.isRow; ) if (((l = h), (h = h.parent), h.isRoot)) return !1;
                for (s = h.isColumn ? "height" : "width", o = "height" === s ? e : t, i = this[s] * (1 / (l.config[s] / 100)), n = (o / i) * 100, r = (l.config[s] - n) / (h.contentItems.length - 1), a = 0; a < h.contentItems.length; a++)
                    h.contentItems[a] === l ? (h.contentItems[a].config[s] = n) : (h.contentItems[a].config[s] += r);
                return h.callDownwards("setSize"), !0;
            },
            close: function () {
                this._config.isClosable && (this.emit("close"), this.parent.close());
            },
            getState: function () {
                return this._config.componentState;
            },
            extendState: function (t) {
                this.setState($.extend(!0, this.getState(), t));
            },
            setState: function (t) {
                (this._config.componentState = t), this.parent.emitBubblingEvent("stateChanged");
            },
            setTitle: function (t) {
                this.parent.setTitle(t);
            },
            _$setSize: function (t, e) {
                (t === this.width && e === this.height) || ((this.width = t), (this.height = e), this._contentElement.width(this.width).height(this.height), this.emit("resize"));
            },
        }),
        (lm.controls.BrowserPopout = function (t, e, i, n, s) {
            lm.utils.EventEmitter.call(this),
                (this.isInitialised = !1),
                (this._config = t),
                (this._dimensions = e),
                (this._parentId = i),
                (this._indexInParent = n),
                (this._layoutManager = s),
                (this._popoutWindow = null),
                (this._id = null),
                this._createWindow();
        }),
        lm.utils.copy(lm.controls.BrowserPopout.prototype, {
            toConfig: function () {
                if (this.isInitialised === !1) throw new Error("Can't create config, layout not yet initialised");
                return {
                    dimensions: { width: this.getGlInstance().width, height: this.getGlInstance().height, left: this._popoutWindow.screenX || this._popoutWindow.screenLeft, top: this._popoutWindow.screenY || this._popoutWindow.screenTop },
                    content: this.getGlInstance().toConfig().content,
                    parentId: this._parentId,
                    indexInParent: this._indexInParent,
                };
            },
            getGlInstance: function () {
                return this._popoutWindow.__glInstance;
            },
            getWindow: function () {
                return this._popoutWindow;
            },
            close: function () {
                if (this.getGlInstance()) this.getGlInstance()._$closeWindow();
                else
                    try {
                        this.getWindow().close();
                    } catch (t) {}
            },
            popIn: function () {
                var t,
                    e,
                    i = this._indexInParent;
                this._parentId &&
                    ((t = $.extend(!0, {}, this.getGlInstance().toConfig()).content[0]),
                    (e = this._layoutManager.root.getItemsById(this._parentId)[0]),
                    e || ((e = this._layoutManager.root.contentItems.length > 0 ? this._layoutManager.root.contentItems[0] : this._layoutManager.root), (i = 0))),
                    e.addChild(t, this._indexInParent),
                    this.close();
            },
            _createWindow: function () {
                var t,
                    e = this._createUrl(),
                    i = Math.floor(1e6 * Math.random()).toString(36),
                    n = this._serializeWindowOptions({
                        width: this._dimensions.width,
                        height: this._dimensions.height,
                        innerWidth: this._dimensions.width,
                        innerHeight: this._dimensions.height,
                        menubar: "no",
                        toolbar: "no",
                        location: "no",
                        personalbar: "no",
                        resizable: "yes",
                        scrollbars: "no",
                        status: "no",
                    });
                if (((this._popoutWindow = window.open(e, i, n)), this._popoutWindow))
                    $(this._popoutWindow).on("load", lm.utils.fnBind(this._positionWindow, this)).on("unload beforeunload", lm.utils.fnBind(this._onClose, this)),
                        (t = setInterval(
                            lm.utils.fnBind(function () {
                                this._popoutWindow.__glInstance && this._popoutWindow.__glInstance.isInitialised && (this._onInitialised(), clearInterval(t));
                            }, this),
                            10
                        ));
                else if (this._layoutManager.config.settings.blockedPopoutsThrowError === !0) {
                    var s = new Error("Popout blocked");
                    throw ((s.type = "popoutBlocked"), s);
                }
            },
            _serializeWindowOptions: function (t) {
                var e,
                    i = [];
                for (e in t) i.push(e + "=" + t[e]);
                return i.join(",");
            },
            _createUrl: function () {
                var t,
                    e = { content: this._config },
                    i = "gl-window-config-" + lm.utils.getUniqueId();
                e = new lm.utils.ConfigMinifier().minifyConfig(e);
                try {
                    localStorage.setItem(i, JSON.stringify(e));
                } catch (n) {
                    throw new Error("Error while writing to localStorage " + n.toString());
                }
                return (t = document.location.href.split("?")), 1 === t.length ? t[0] + "?gl-window=" + i : document.location.href + "&gl-window=" + i;
            },
            _positionWindow: function () {
                this._popoutWindow.moveTo(this._dimensions.left, this._dimensions.top), this._popoutWindow.focus();
            },
            _onInitialised: function () {
                (this.isInitialised = !0), this.getGlInstance().on("popIn", this.popIn, this), this.emit("initialised");
            },
            _onClose: function () {
                setTimeout(lm.utils.fnBind(this.emit, this, ["closed"]), 50);
            },
        }),
        (lm.controls.DragProxy = function (t, e, i, n, s, o) {
            lm.utils.EventEmitter.call(this),
                (this._dragListener = i),
                (this._layoutManager = n),
                (this._contentItem = s),
                (this._originalParent = o),
                (this._area = null),
                (this._lastValidArea = null),
                this._dragListener.on("drag", this._onDrag, this),
                this._dragListener.on("dragStop", this._onDrop, this),
                (this.element = $(lm.controls.DragProxy._template)),
                o && o._side && ((this._sided = o._sided), this.element.addClass("lm_" + o._side), ["right", "bottom"].indexOf(o._side) >= 0 && this.element.find(".lm_content").after(this.element.find(".lm_header"))),
                this.element.css({ left: t, top: e }),
                this.element.find(".lm_tab").attr("title", lm.utils.stripTags(this._contentItem.config.title)),
                this.element.find(".lm_title").html(this._contentItem.config.title),
                (this.childElementContainer = this.element.find(".lm_content")),
                this.childElementContainer.append(s.element),
                this._updateTree(),
                this._layoutManager._$calculateItemAreas(),
                this._setDimensions(),
                $(document.body).append(this.element);
            var r = this._layoutManager.container.offset();
            (this._minX = r.left),
                (this._minY = r.top),
                (this._maxX = this._layoutManager.container.width() + this._minX),
                (this._maxY = this._layoutManager.container.height() + this._minY),
                (this._width = this.element.width()),
                (this._height = this.element.height()),
                this._setDropPosition(t, e);
        }),
        (lm.controls.DragProxy._template =
            '<div class="lm_dragProxy"><div class="lm_header"><ul class="lm_tabs"><li class="lm_tab lm_active"><i class="lm_left"></i><span class="lm_title"></span><i class="lm_right"></i></li></ul></div><div class="lm_content"></div></div>'),
        lm.utils.copy(lm.controls.DragProxy.prototype, {
            _onDrag: function (t, e, i) {
                i = i.originalEvent && i.originalEvent.touches ? i.originalEvent.touches[0] : i;
                var n = i.pageX,
                    s = i.pageY,
                    o = n > this._minX && n < this._maxX && s > this._minY && s < this._maxY;
                (o || this._layoutManager.config.settings.constrainDragToContainer !== !0) && this._setDropPosition(n, s);
            },
            _setDropPosition: function (t, e) {
                this.element.css({ left: t, top: e }), (this._area = this._layoutManager._$getArea(t, e)), null !== this._area && ((this._lastValidArea = this._area), this._area.contentItem._$highlightDropZone(t, e, this._area));
            },
            _onDrop: function () {
                this._layoutManager.dropTargetIndicator.hide(),
                    null !== this._area
                        ? this._area.contentItem._$onDrop(this._contentItem, this._area)
                        : null !== this._lastValidArea
                        ? this._lastValidArea.contentItem._$onDrop(this._contentItem, this._lastValidArea)
                        : this._originalParent
                        ? this._originalParent.addChild(this._contentItem)
                        : this._contentItem._$destroy(),
                    this.element.remove(),
                    this._layoutManager.emit("itemDropped", this._contentItem);
            },
            _updateTree: function () {
                this._contentItem.parent && this._contentItem.parent.removeChild(this._contentItem, !0), this._contentItem._$setParent(this);
            },
            _setDimensions: function () {
                var t = this._layoutManager.config.dimensions,
                    e = t.dragProxyWidth,
                    i = t.dragProxyHeight;
                this.element.width(e),
                    this.element.height(i),
                    (e -= this._sided ? t.headerHeight : 0),
                    (i -= this._sided ? 0 : t.headerHeight),
                    this.childElementContainer.width(e),
                    this.childElementContainer.height(i),
                    this._contentItem.element.width(e),
                    this._contentItem.element.height(i),
                    this._contentItem.callDownwards("_$show"),
                    this._contentItem.callDownwards("setSize");
            },
        }),
        (lm.controls.DragSource = function (t, e, i) {
            (this._element = t), (this._itemConfig = e), (this._layoutManager = i), (this._dragListener = null), this._createDragListener();
        }),
        lm.utils.copy(lm.controls.DragSource.prototype, {
            _createDragListener: function () {
                null !== this._dragListener && this._dragListener.destroy(),
                    (this._dragListener = new lm.utils.DragListener(this._element)),
                    this._dragListener.on("dragStart", this._onDragStart, this),
                    this._dragListener.on("dragStop", this._createDragListener, this);
            },
            _onDragStart: function (t, e) {
                var i = this._itemConfig;
                lm.utils.isFunction(i) && (i = i());
                var n = this._layoutManager._$normalizeContentItem($.extend(!0, {}, i)),
                    s = new lm.controls.DragProxy(t, e, this._dragListener, this._layoutManager, n, null);
                this._layoutManager.transitionIndicator.transitionElements(this._element, s.element);
            },
        }),
        (lm.controls.DropTargetIndicator = function () {
            (this.element = $(lm.controls.DropTargetIndicator._template)), $(document.body).append(this.element);
        }),
        (lm.controls.DropTargetIndicator._template = '<div class="lm_dropTargetIndicator"><div class="lm_inner"></div></div>'),
        lm.utils.copy(lm.controls.DropTargetIndicator.prototype, {
            destroy: function () {
                this.element.remove();
            },
            highlight: function (t, e, i, n) {
                this.highlightArea({ x1: t, y1: e, x2: i, y2: n });
            },
            highlightArea: function (t) {
                this.element.css({ left: t.x1, top: t.y1, width: t.x2 - t.x1, height: t.y2 - t.y1 }).show();
            },
            hide: function () {
                this.element.hide();
            },
        }),
        (lm.controls.Header = function (t, e) {
            lm.utils.EventEmitter.call(this),
                (this.layoutManager = t),
                (this.element = $(lm.controls.Header._template)),
                this.layoutManager.config.settings.selectionEnabled === !0 && (this.element.addClass("lm_selectable"), this.element.on("click touchstart", lm.utils.fnBind(this._onHeaderClick, this))),
                (this.tabsContainer = this.element.find(".lm_tabs")),
                (this.tabDropdownContainer = this.element.find(".lm_tabdropdown_list")),
                this.tabDropdownContainer.hide(),
                (this.controlsContainer = this.element.find(".lm_controls")),
                (this.parent = e),
                this.parent.on("resize", this._updateTabSizes, this),
                (this.tabs = []),
                (this.activeContentItem = null),
                (this.closeButton = null),
                (this.tabDropdownButton = null),
                $(document).mouseup(lm.utils.fnBind(this._hideAdditionalTabsDropdown, this)),
                (this._lastVisibleTabIndex = -1),
                (this._tabControlOffset = 10),
                this._createControls();
        }),
        (lm.controls.Header._template = ['<div class="lm_header">', '<ul class="lm_tabs"></ul>', '<ul class="lm_controls"></ul>', '<ul class="lm_tabdropdown_list"></ul>', "</div>"].join("")),
        lm.utils.copy(lm.controls.Header.prototype, {
            createTab: function (t, e) {
                var i, n;
                for (n = 0; n < this.tabs.length; n++) if (this.tabs[n].contentItem === t) return;
                return (
                    (i = new lm.controls.Tab(this, t)),
                    0 === this.tabs.length
                        ? (this.tabs.push(i), void this.tabsContainer.append(i.element))
                        : (void 0 === e && (e = this.tabs.length), e > 0 ? this.tabs[e - 1].element.after(i.element) : this.tabs[0].element.before(i.element), this.tabs.splice(e, 0, i), void this._updateTabSizes())
                );
            },
            removeTab: function (t) {
                for (var e = 0; e < this.tabs.length; e++) if (this.tabs[e].contentItem === t) return this.tabs[e]._$destroy(), void this.tabs.splice(e, 1);
                throw new Error("contentItem is not controlled by this header");
            },
            setActiveContentItem: function (t) {
                var e, i, n, s;
                for (e = 0; e < this.tabs.length; e++) (n = this.tabs[e].contentItem === t), this.tabs[e].setActive(n), n === !0 && ((this.activeContentItem = t), (this.parent.config.activeItemIndex = e));
                if (this._lastVisibleTabIndex !== -1 && this.parent.config.activeItemIndex > this._lastVisibleTabIndex) {
                    for (s = this.tabs[this.parent.config.activeItemIndex], i = this.parent.config.activeItemIndex; i > 0; i--) this.tabs[i] = this.tabs[i - 1];
                    (this.tabs[0] = s), (this.parent.config.activeItemIndex = 0);
                }
                this._updateTabSizes(), this.parent.emitBubblingEvent("stateChanged");
            },
            position: function (t) {
                var e = this.parent._header.show;
                return e && !this.parent._side && (e = "top"), void 0 !== t && this.parent._header.show != t && ((this.parent._header.show = t), this.parent._setupHeaderPosition()), e;
            },
            _$setClosable: function (t) {
                return !(!this.closeButton || !this._isClosable()) && (this.closeButton.element[t ? "show" : "hide"](), !0);
            },
            _$destroy: function () {
                this.emit("destroy", this);
                for (var t = 0; t < this.tabs.length; t++) this.tabs[t]._$destroy();
                this.element.remove();
            },
            _getHeaderSetting: function (t) {
                if (t in this.parent._header) return this.parent._header[t];
            },
            _createControls: function () {
                var t, e, i, n, s, o, r, a, h;
                (h = lm.utils.fnBind(this._showAdditionalTabsDropdown, this)),
                    (a = this.layoutManager.config.labels.tabDropdown),
                    (this.tabDropdownButton = new lm.controls.HeaderButton(this, a, "lm_tabdropdown", h)),
                    this.tabDropdownButton.element.hide(),
                    this._getHeaderSetting("popout") && ((e = lm.utils.fnBind(this._onPopoutClick, this)), (i = this._getHeaderSetting("popout")), new lm.controls.HeaderButton(this, i, "lm_popout", e)),
                    this._getHeaderSetting("maximise") &&
                        ((o = lm.utils.fnBind(this.parent.toggleMaximise, this.parent)),
                        (n = this._getHeaderSetting("maximise")),
                        (s = this._getHeaderSetting("minimise")),
                        (r = new lm.controls.HeaderButton(this, n, "lm_maximise", o)),
                        this.parent.on("maximised", function () {
                            r.element.attr("title", s);
                        }),
                        this.parent.on("minimised", function () {
                            r.element.attr("title", n);
                        })),
                    this._isClosable() && ((t = lm.utils.fnBind(this.parent.remove, this.parent)), (i = this._getHeaderSetting("close")), (this.closeButton = new lm.controls.HeaderButton(this, i, "lm_close", t)));
            },
            _showAdditionalTabsDropdown: function () {
                this.tabDropdownContainer.show();
            },
            _hideAdditionalTabsDropdown: function (t) {
                this.tabDropdownContainer.hide();
            },
            _isClosable: function () {
                return this.parent.config.isClosable && this.layoutManager.config.settings.showCloseIcon;
            },
            _onPopoutClick: function () {
                this.layoutManager.config.settings.popoutWholeStack === !0 ? this.parent.popout() : this.activeContentItem.popout();
            },
            _onHeaderClick: function (t) {
                t.target === this.element[0] && this.parent.select();
            },
            _updateTabSizes: function () {
                if (0 !== this.tabs.length) {
                    var t = function (t) {
                        return t ? "width" : "height";
                    };
                    this.element.css(t(!this.parent._sided), ""), this.element[t(this.parent._sided)](this.layoutManager.config.dimensions.headerHeight);
                    var e,
                        i,
                        n,
                        s,
                        o = this.element.outerWidth() - this.controlsContainer.outerWidth() - this._tabControlOffset,
                        r = 0,
                        a = !1;
                    for (this.parent._sided && (o = this.element.outerHeight() - this.controlsContainer.outerHeight() - this._tabControlOffset), this._lastVisibleTabIndex = -1, i = 0; i < this.tabs.length; i++)
                        (e = this.tabs[i].element),
                            (s = e.data("lastTabWidth")),
                            s || (s = e.outerWidth() + parseInt(e.css("margin-right"), 10)),
                            (r += s),
                            r > o && a ? (e.data("lastTabWidth", s), this.tabDropdownContainer.append(e)) : ((a = !0), (this._lastVisibleTabIndex = i), e.removeData("lastTabWidth"), this.tabsContainer.append(e));
                    (n = r > o), this.tabDropdownButton.element[n ? "show" : "hide"]();
                }
            },
        }),
        (lm.controls.HeaderButton = function (t, e, i, n) {
            (this._header = t),
                (this.element = $('<li class="' + i + '" title="' + e + '"></li>')),
                this._header.on("destroy", this._$destroy, this),
                (this._action = n),
                this.element.on("click touchstart", this._action),
                this._header.controlsContainer.append(this.element);
        }),
        lm.utils.copy(lm.controls.HeaderButton.prototype, {
            _$destroy: function () {
                this.element.off(), this.element.remove();
            },
        }),
        (lm.controls.Splitter = function (t, e) {
            (this._isVertical = t), (this._size = e), (this.element = this._createElement()), (this._dragListener = new lm.utils.DragListener(this.element));
        }),
        lm.utils.copy(lm.controls.Splitter.prototype, {
            on: function (t, e, i) {
                this._dragListener.on(t, e, i);
            },
            _$destroy: function () {
                this.element.remove();
            },
            _createElement: function () {
                var t = $('<div class="lm_splitter"><div class="lm_drag_handle"></div></div>');
                return t.addClass("lm_" + (this._isVertical ? "vertical" : "horizontal")), t[this._isVertical ? "height" : "width"](this._size), t;
            },
        }),
        (lm.controls.Tab = function (t, e) {
            (this.header = t),
                (this.contentItem = e),
                (this.element = $(lm.controls.Tab._template)),
                (this.titleElement = this.element.find(".lm_title")),
                (this.closeElement = this.element.find(".lm_close_tab")),
                this.closeElement[e.config.isClosable ? "show" : "hide"](),
                (this.isActive = !1),
                this.setTitle(e.config.title),
                this.contentItem.on("titleChanged", this.setTitle, this),
                (this._layoutManager = this.contentItem.layoutManager),
                this._layoutManager.config.settings.reorderEnabled === !0 && e.config.reorderEnabled === !0 && ((this._dragListener = new lm.utils.DragListener(this.element)), this._dragListener.on("dragStart", this._onDragStart, this)),
                (this._onTabClickFn = lm.utils.fnBind(this._onTabClick, this)),
                (this._onCloseClickFn = lm.utils.fnBind(this._onCloseClick, this)),
                this.element.on("mousedown touchstart", this._onTabClickFn),
                this.contentItem.config.isClosable ? this.closeElement.on("click touchstart", this._onCloseClickFn) : this.closeElement.remove(),
                (this.contentItem.tab = this),
                this.contentItem.emit("tab", this),
                this.contentItem.layoutManager.emit("tabCreated", this),
                this.contentItem.isComponent && ((this.contentItem.container.tab = this), this.contentItem.container.emit("tab", this));
        }),
        (lm.controls.Tab._template = '<li class="lm_tab"><i class="lm_left"></i><span class="lm_title"></span><div class="lm_close_tab"></div><i class="lm_right"></i></li>'),
        lm.utils.copy(lm.controls.Tab.prototype, {
            setTitle: function (t) {
                this.element.attr("title", lm.utils.stripTags(t)), this.titleElement.html(t);
            },
            setActive: function (t) {
                t !== this.isActive && ((this.isActive = t), t ? this.element.addClass("lm_active") : this.element.removeClass("lm_active"));
            },
            _$destroy: function () {
                this.element.off("mousedown touchstart", this._onTabClickFn),
                    this.closeElement.off("click touchstart", this._onCloseClickFn),
                    this._dragListener && (this._dragListener.off("dragStart", this._onDragStart), (this._dragListener = null)),
                    this.element.remove();
            },
            _onDragStart: function (t, e) {
                this.contentItem.parent.isMaximised === !0 && this.contentItem.parent.toggleMaximise(), new lm.controls.DragProxy(t, e, this._dragListener, this._layoutManager, this.contentItem, this.header.parent);
            },
            _onTabClick: function (t) {
                if (0 === t.button || "touchstart" === t.type) {
                    var e = this.header.parent.getActiveContentItem();
                    this.contentItem !== e && this.header.parent.setActiveContentItem(this.contentItem);
                } else 1 === t.button && this.contentItem.config.isClosable && this._onCloseClick(t);
            },
            _onCloseClick: function (t) {
                t.stopPropagation(), this.header.parent.removeChild(this.contentItem);
            },
        }),
        (lm.controls.TransitionIndicator = function () {
            (this._element = $('<div class="lm_transition_indicator"></div>')),
                $(document.body).append(this._element),
                (this._toElement = null),
                (this._fromDimensions = null),
                (this._totalAnimationDuration = 200),
                (this._animationStartTime = null);
        }),
        lm.utils.copy(lm.controls.TransitionIndicator.prototype, {
            destroy: function () {
                this._element.remove();
            },
            transitionElements: function (t, e) {},
            _nextAnimationFrame: function () {
                var t,
                    e = this._measure(this._toElement),
                    i = (lm.utils.now() - this._animationStartTime) / this._totalAnimationDuration,
                    n = {};
                if (i >= 1) return void this._element.hide();
                e.opacity = 0;
                for (t in this._fromDimensions) n[t] = this._fromDimensions[t] + (e[t] - this._fromDimensions[t]) * i;
                this._element.css(n), lm.utils.animFrame(lm.utils.fnBind(this._nextAnimationFrame, this));
            },
            _measure: function (t) {
                var e = t.offset();
                return { left: e.left, top: e.top, width: t.outerWidth(), height: t.outerHeight() };
            },
        }),
        (lm.errors.ConfigurationError = function (t, e) {
            Error.call(this), (this.name = "Configuration Error"), (this.message = t), (this.node = e);
        }),
        (lm.errors.ConfigurationError.prototype = new Error()),
        (lm.items.AbstractContentItem = function (t, e, i) {
            lm.utils.EventEmitter.call(this),
                (this.config = this._extendItemNode(e)),
                (this.type = e.type),
                (this.contentItems = []),
                (this.parent = i),
                (this.isInitialised = !1),
                (this.isMaximised = !1),
                (this.isRoot = !1),
                (this.isRow = !1),
                (this.isColumn = !1),
                (this.isStack = !1),
                (this.isComponent = !1),
                (this.layoutManager = t),
                (this._pendingEventPropagations = {}),
                (this._throttledEvents = ["stateChanged"]),
                this.on(lm.utils.EventEmitter.ALL_EVENT, this._propagateEvent, this),
                e.content && this._createContentItems(e);
        }),
        lm.utils.copy(lm.items.AbstractContentItem.prototype, {
            setSize: function () {
                throw new Error("Abstract Method");
            },
            callDownwards: function (t, e, i, n) {
                var s;
                for (i !== !0 && n !== !0 && this[t].apply(this, e || []), s = 0; s < this.contentItems.length; s++) this.contentItems[s].callDownwards(t, e, i);
                i === !0 && n !== !0 && this[t].apply(this, e || []);
            },
            removeChild: function (t, e) {
                var i = lm.utils.indexOf(t, this.contentItems);
                if (i === -1) throw new Error("Can't remove child item. Unknown content item");
                e !== !0 && this.contentItems[i]._$destroy(),
                    this.contentItems.splice(i, 1),
                    this.config.content.splice(i, 1),
                    this.contentItems.length > 0 ? this.callDownwards("setSize") : this instanceof lm.items.Root || this.config.isClosable !== !0 || this.parent.removeChild(this);
            },
            addChild: function (t, e) {
                void 0 === e && (e = this.contentItems.length),
                    this.contentItems.splice(e, 0, t),
                    void 0 === this.config.content && (this.config.content = []),
                    this.config.content.splice(e, 0, t.config),
                    (t.parent = this),
                    t.parent.isInitialised === !0 && t.isInitialised === !1 && t._$init();
            },
            replaceChild: function (t, e, i) {
                e = this.layoutManager._$normalizeContentItem(e);
                var n = lm.utils.indexOf(t, this.contentItems),
                    s = t.element[0].parentNode;
                if (n === -1) throw new Error("Can't replace child. oldChild is not child of this");
                s.replaceChild(e.element[0], t.element[0]),
                    i === !0 && ((t.parent = null), t._$destroy()),
                    (this.contentItems[n] = e),
                    (e.parent = this),
                    this.isStack && (this.header.tabs[n].contentItem = e),
                    e.parent.isInitialised === !0 && e.isInitialised === !1 && e._$init(),
                    this.callDownwards("setSize");
            },
            remove: function () {
                this.parent.removeChild(this);
            },
            popout: function () {
                var t = this.layoutManager.createPopout(this);
                return this.emitBubblingEvent("stateChanged"), t;
            },
            toggleMaximise: function (t) {
                t && t.preventDefault(), this.isMaximised === !0 ? this.layoutManager._$minimiseItem(this) : this.layoutManager._$maximiseItem(this), (this.isMaximised = !this.isMaximised), this.emitBubblingEvent("stateChanged");
            },
            select: function () {
                this.layoutManager.selectedItem !== this && (this.layoutManager.selectItem(this, !0), this.element.addClass("lm_selected"));
            },
            deselect: function () {
                this.layoutManager.selectedItem === this && ((this.layoutManager.selectedItem = null), this.element.removeClass("lm_selected"));
            },
            setTitle: function (t) {
                (this.config.title = t), this.emit("titleChanged", t), this.emit("stateChanged");
            },
            hasId: function (t) {
                return !!this.config.id && ("string" == typeof this.config.id ? this.config.id === t : this.config.id instanceof Array ? lm.utils.indexOf(t, this.config.id) !== -1 : void 0);
            },
            addId: function (t) {
                this.hasId(t) || (this.config.id ? ("string" == typeof this.config.id ? (this.config.id = [this.config.id, t]) : this.config.id instanceof Array && this.config.id.push(t)) : (this.config.id = t));
            },
            removeId: function (t) {
                if (!this.hasId(t)) throw new Error("Id not found");
                if ("string" == typeof this.config.id) delete this.config.id;
                else if (this.config.id instanceof Array) {
                    var e = lm.utils.indexOf(t, this.config.id);
                    this.config.id.splice(e, 1);
                }
            },
            getItemsByFilter: function (t) {
                var e = [],
                    i = function (n) {
                        for (var s = 0; s < n.contentItems.length; s++) t(n.contentItems[s]) === !0 && e.push(n.contentItems[s]), i(n.contentItems[s]);
                    };
                return i(this), e;
            },
            getItemsById: function (t) {
                return this.getItemsByFilter(function (e) {
                    return e.config.id instanceof Array ? lm.utils.indexOf(t, e.config.id) !== -1 : e.config.id === t;
                });
            },
            getItemsByType: function (t) {
                return this._$getItemsByProperty("type", t);
            },
            getComponentsByName: function (t) {
                var e,
                    i = this._$getItemsByProperty("componentName", t),
                    n = [];
                for (e = 0; e < i.length; e++) n.push(i[e].instance);
                return n;
            },
            _$getItemsByProperty: function (t, e) {
                return this.getItemsByFilter(function (i) {
                    return i[t] === e;
                });
            },
            _$setParent: function (t) {
                this.parent = t;
            },
            _$highlightDropZone: function (t, e, i) {
                this.layoutManager.dropTargetIndicator.highlightArea(i);
            },
            _$onDrop: function (t) {
                this.addChild(t);
            },
            _$hide: function () {
                this._callOnActiveComponents("hide"), this.element.hide(), this.layoutManager.updateSize();
            },
            _$show: function () {
                this._callOnActiveComponents("show"), this.element.show(), this.layoutManager.updateSize();
            },
            _callOnActiveComponents: function (t) {
                var e,
                    i,
                    n = this.getItemsByType("stack");
                for (i = 0; i < n.length; i++) (e = n[i].getActiveContentItem()), e && e.isComponent && e.container[t]();
            },
            _$destroy: function () {
                this.emitBubblingEvent("beforeItemDestroyed"), this.callDownwards("_$destroy", [], !0, !0), this.element.remove(), this.emitBubblingEvent("itemDestroyed");
            },
            _$getArea: function (t) {
                t = t || this.element;
                var e = t.offset(),
                    i = t.width(),
                    n = t.height();
                return { x1: e.left, y1: e.top, x2: e.left + i, y2: e.top + n, surface: i * n, contentItem: this };
            },
            _$init: function () {
                var t;
                for (this.setSize(), t = 0; t < this.contentItems.length; t++) this.childElementContainer.append(this.contentItems[t].element);
                (this.isInitialised = !0), this.emitBubblingEvent("itemCreated"), this.emitBubblingEvent(this.type + "Created");
            },
            emitBubblingEvent: function (t) {
                var e = new lm.utils.BubblingEvent(t, this);
                this.emit(t, e);
            },
            _createContentItems: function (t) {
                var e, i;
                if (!(t.content instanceof Array)) throw new lm.errors.ConfigurationError("content must be an Array", t);
                for (i = 0; i < t.content.length; i++) (e = this.layoutManager.createContentItem(t.content[i], this)), this.contentItems.push(e);
            },
            _extendItemNode: function (t) {
                for (var e in lm.config.itemDefaultConfig) void 0 === t[e] && (t[e] = lm.config.itemDefaultConfig[e]);
                return t;
            },
            _propagateEvent: function (t, e) {
                e instanceof lm.utils.BubblingEvent &&
                    e.isPropagationStopped === !1 &&
                    this.isInitialised === !0 &&
                    (this.isRoot === !1 && this.parent ? this.parent.emit.apply(this.parent, Array.prototype.slice.call(arguments, 0)) : this._scheduleEventPropagationToLayoutManager(t, e));
            },
            _scheduleEventPropagationToLayoutManager: function (t, e) {
                lm.utils.indexOf(t, this._throttledEvents) === -1
                    ? this.layoutManager.emit(t, e.origin)
                    : this._pendingEventPropagations[t] !== !0 && ((this._pendingEventPropagations[t] = !0), lm.utils.animFrame(lm.utils.fnBind(this._propagateEventToLayoutManager, this, [t, e])));
            },
            _propagateEventToLayoutManager: function (t, e) {
                (this._pendingEventPropagations[t] = !1), this.layoutManager.emit(t, e);
            },
        }),
        (lm.items.Component = function (t, e, i) {
            lm.items.AbstractContentItem.call(this, t, e, i);
            var n = t.getComponent(this.config.componentName),
                s = $.extend(!0, {}, this.config.componentState || {});
            (s.componentName = this.config.componentName),
                (this.componentName = this.config.componentName),
                "" === this.config.title && (this.config.title = this.config.componentName),
                (this.isComponent = !0),
                (this.container = new lm.container.ItemContainer(this.config, this, t)),
                (this.instance = new n(this.container, s)),
                (this.element = this.container._element);
        }),
        lm.utils.extend(lm.items.Component, lm.items.AbstractContentItem),
        lm.utils.copy(lm.items.Component.prototype, {
            close: function () {
                this.parent.removeChild(this);
            },
            setSize: function () {
                this.element.is(":visible") && this.container._$setSize(this.element.width(), this.element.height());
            },
            _$init: function () {
                lm.items.AbstractContentItem.prototype._$init.call(this), this.container.emit("open");
            },
            _$hide: function () {
                this.container.hide(), lm.items.AbstractContentItem.prototype._$hide.call(this);
            },
            _$show: function () {
                this.container.show(), lm.items.AbstractContentItem.prototype._$show.call(this);
            },
            _$shown: function () {
                this.container.shown(), lm.items.AbstractContentItem.prototype._$shown.call(this);
            },
            _$destroy: function () {
                this.container.emit("destroy", this), lm.items.AbstractContentItem.prototype._$destroy.call(this);
            },
            _$getArea: function () {
                return null;
            },
        }),
        (lm.items.Root = function (t, e, i) {
            lm.items.AbstractContentItem.call(this, t, e, null),
                (this.isRoot = !0),
                (this.type = "root"),
                (this.element = $('<div class="lm_goldenlayout lm_item lm_root"></div>')),
                (this.childElementContainer = this.element),
                (this._containerElement = i),
                this._containerElement.append(this.element);
        }),
        lm.utils.extend(lm.items.Root, lm.items.AbstractContentItem),
        lm.utils.copy(lm.items.Root.prototype, {
            addChild: function (t) {
                if (this.contentItems.length > 0) throw new Error("Root node can only have a single child");
                (t = this.layoutManager._$normalizeContentItem(t, this)),
                    this.childElementContainer.append(t.element),
                    lm.items.AbstractContentItem.prototype.addChild.call(this, t),
                    this.callDownwards("setSize"),
                    this.emitBubblingEvent("stateChanged");
            },
            setSize: function (t, e) {
                (t = "undefined" == typeof t ? this._containerElement.width() : t),
                    (e = "undefined" == typeof e ? this._containerElement.height() : e),
                    this.element.width(t),
                    this.element.height(e),
                    this.contentItems[0] && (this.contentItems[0].element.width(t), this.contentItems[0].element.height(e));
            },
            _$highlightDropZone: function (t, e, i) {
                this.layoutManager.tabDropPlaceholder.remove(), lm.items.AbstractContentItem.prototype._$highlightDropZone.apply(this, arguments);
            },
            _$onDrop: function (t, e) {
                var i;
                if ((t.isComponent && ((i = this.layoutManager.createContentItem({ type: "stack", header: t.config.header || {} }, this)), i._$init(), i.addChild(t), (t = i)), this.contentItems.length)) {
                    var n = "x" == e.side[0] ? "row" : "column",
                        s = "x" == e.side[0] ? "width" : "height",
                        o = "2" == e.side[1],
                        r = this.contentItems[0];
                    if (!r instanceof lm.items.RowOrColumn || r.type != n) {
                        var a = this.layoutManager.createContentItem({ type: n }, this);
                        this.replaceChild(r, a), a.addChild(t, o ? 0 : void 0, !0), a.addChild(r, o ? void 0 : 0, !0), (r.config[s] = 50), (t.config[s] = 50), a.callDownwards("setSize");
                    } else {
                        var h = r.contentItems[o ? 0 : r.contentItems.length - 1];
                        r.addChild(t, o ? 0 : void 0, !0), (h.config[s] *= 0.5), (t.config[s] = h.config[s]), r.callDownwards("setSize");
                    }
                } else this.addChild(t);
            },
        }),
        (lm.items.RowOrColumn = function (t, e, i, n) {
            lm.items.AbstractContentItem.call(this, e, i, n),
                (this.isRow = !t),
                (this.isColumn = t),
                (this.element = $('<div class="lm_item lm_' + (t ? "column" : "row") + '"></div>')),
                (this.childElementContainer = this.element),
                (this._splitterSize = e.config.dimensions.borderWidth),
                (this._isColumn = t),
                (this._dimension = t ? "height" : "width"),
                (this._splitter = []),
                (this._splitterPosition = null),
                (this._splitterMinPosition = null),
                (this._splitterMaxPosition = null);
        }),
        lm.utils.extend(lm.items.RowOrColumn, lm.items.AbstractContentItem),
        lm.utils.copy(lm.items.RowOrColumn.prototype, {
            addChild: function (t, e, i) {
                var n, s, o, r;
                if (
                    ((t = this.layoutManager._$normalizeContentItem(t, this)),
                    void 0 === e && (e = this.contentItems.length),
                    this.contentItems.length > 0
                        ? ((r = this._createSplitter(Math.max(0, e - 1)).element), e > 0 ? (this.contentItems[e - 1].element.after(r), r.after(t.element)) : (this.contentItems[0].element.before(r), r.before(t.element)))
                        : this.childElementContainer.append(t.element),
                    lm.items.AbstractContentItem.prototype.addChild.call(this, t, e),
                    (n = (1 / this.contentItems.length) * 100),
                    i === !0)
                )
                    return void this.emitBubblingEvent("stateChanged");
                for (o = 0; o < this.contentItems.length; o++)
                    this.contentItems[o] === t ? (t.config[this._dimension] = n) : ((s = this.contentItems[o].config[this._dimension] *= (100 - n) / 100), (this.contentItems[o].config[this._dimension] = s));
                this.callDownwards("setSize"), this.emitBubblingEvent("stateChanged");
            },
            removeChild: function (t, e) {
                var i,
                    n,
                    s = t.config[this._dimension],
                    o = lm.utils.indexOf(t, this.contentItems),
                    r = Math.max(o - 1, 0);
                if (o === -1) throw new Error("Can't remove child. ContentItem is not child of this Row or Column");
                for (this._splitter[r] && (this._splitter[r]._$destroy(), this._splitter.splice(r, 1)), i = 0; i < this.contentItems.length; i++)
                    this.contentItems[i] !== t && (this.contentItems[i].config[this._dimension] += s / (this.contentItems.length - 1));
                lm.items.AbstractContentItem.prototype.removeChild.call(this, t, e),
                    1 === this.contentItems.length && this.config.isClosable === !0
                        ? ((n = this.contentItems[0]), (this.contentItems = []), this.parent.replaceChild(this, n, !0))
                        : (this.callDownwards("setSize"), this.emitBubblingEvent("stateChanged"));
            },
            replaceChild: function (t, e) {
                var i = t.config[this._dimension];
                lm.items.AbstractContentItem.prototype.replaceChild.call(this, t, e), (e.config[this._dimension] = i), this.callDownwards("setSize"), this.emitBubblingEvent("stateChanged");
            },
            setSize: function () {
                this.contentItems.length > 0 && (this._calculateRelativeSizes(), this._setAbsoluteSizes()), this.emitBubblingEvent("stateChanged"), this.emit("resize");
            },
            _$init: function () {
                if (this.isInitialised !== !0) {
                    var t;
                    for (lm.items.AbstractContentItem.prototype._$init.call(this), t = 0; t < this.contentItems.length - 1; t++) this.contentItems[t].element.after(this._createSplitter(t).element);
                }
            },
            _setAbsoluteSizes: function () {
                var t,
                    e = this._calculateAbsoluteSizes();
                for (t = 0; t < this.contentItems.length; t++)
                    e.additionalPixel - t > 0 && e.itemSizes[t]++,
                        this._isColumn
                            ? (this.contentItems[t].element.width(e.totalWidth), this.contentItems[t].element.height(e.itemSizes[t]))
                            : (this.contentItems[t].element.width(e.itemSizes[t]), this.contentItems[t].element.height(e.totalHeight));
            },
            _calculateAbsoluteSizes: function () {
                var t,
                    e,
                    i,
                    n = (this.contentItems.length - 1) * this._splitterSize,
                    s = this.element.width(),
                    o = this.element.height(),
                    r = 0,
                    a = [];
                for (this._isColumn ? (o -= n) : (s -= n), t = 0; t < this.contentItems.length; t++)
                    (i = this._isColumn ? Math.floor(o * (this.contentItems[t].config.height / 100)) : Math.floor(s * (this.contentItems[t].config.width / 100))), (r += i), a.push(i);
                return (e = Math.floor((this._isColumn ? o : s) - r)), { itemSizes: a, additionalPixel: e, totalWidth: s, totalHeight: o };
            },
            _calculateRelativeSizes: function () {
                var t,
                    e = 0,
                    i = [],
                    n = this._isColumn ? "height" : "width";
                for (t = 0; t < this.contentItems.length; t++) void 0 !== this.contentItems[t].config[n] ? (e += this.contentItems[t].config[n]) : i.push(this.contentItems[t]);
                if (100 === Math.round(e)) return void this._respectMinItemWidth();
                if (Math.round(e) < 100 && i.length > 0) {
                    for (t = 0; t < i.length; t++) i[t].config[n] = (100 - e) / i.length;
                    return void this._respectMinItemWidth();
                }
                if (Math.round(e) > 100) for (t = 0; t < i.length; t++) (i[t].config[n] = 50), (e += 50);
                for (t = 0; t < this.contentItems.length; t++) this.contentItems[t].config[n] = (this.contentItems[t].config[n] / e) * 100;
                this._respectMinItemWidth();
            },
            _respectMinItemWidth: function () {
                var t,
                    e,
                    n,
                    s = this.layoutManager.config.dimensions ? this.layoutManager.config.dimensions.minItemWidth || 0 : 0,
                    o = null,
                    r = [],
                    a = 0,
                    h = 0,
                    l = 0,
                    m = 0,
                    c = null,
                    d = [];
                if (!(this._isColumn || !s || this.contentItems.length <= 1)) {
                    for (o = this._calculateAbsoluteSizes(), i = 0; i < this.contentItems.length; i++)
                        (c = this.contentItems[i]), (m = o.itemSizes[i]), m < s ? ((h += s - m), (n = { width: s })) : ((a += m - s), (n = { width: m }), r.push(n)), d.push(n);
                    if (!(0 === h || h > a)) {
                        for (t = h / a, l = h, i = 0; i < r.length; i++) (n = r[i]), (e = Math.round((n.width - s) * t)), (l -= e), (n.width -= e);
                        for (0 !== l && (d[d.length - 1].width -= l), i = 0; i < this.contentItems.length; i++) this.contentItems[i].config.width = (d[i].width / o.totalWidth) * 100;
                    }
                }
            },
            _createSplitter: function (t) {
                var e;
                return (
                    (e = new lm.controls.Splitter(this._isColumn, this._splitterSize)),
                    e.on("drag", lm.utils.fnBind(this._onSplitterDrag, this, [e]), this),
                    e.on("dragStop", lm.utils.fnBind(this._onSplitterDragStop, this, [e]), this),
                    e.on("dragStart", lm.utils.fnBind(this._onSplitterDragStart, this, [e]), this),
                    this._splitter.splice(t, 0, e),
                    e
                );
            },
            _getItemsForSplitter: function (t) {
                var e = lm.utils.indexOf(t, this._splitter);
                return { before: this.contentItems[e], after: this.contentItems[e + 1] };
            },
            _getMinimumDimensions: function (t) {
                for (var e = 0, i = 0, n = 0; n < t.length; ++n) (e = Math.max(t[n].minWidth || 0, e)), (i = Math.max(t[n].minHeight || 0, i));
                return { horizontal: e, vertical: i };
            },
            _onSplitterDragStart: function (t) {
                var e = this._getItemsForSplitter(t),
                    i = this.layoutManager.config.dimensions[this._isColumn ? "minItemHeight" : "minItemWidth"],
                    n = this._getMinimumDimensions(e.before.config.content),
                    s = this._isColumn ? n.vertical : n.horizontal,
                    o = this._getMinimumDimensions(e.after.config.content),
                    r = this._isColumn ? o.vertical : o.horizontal;
                (this._splitterPosition = 0), (this._splitterMinPosition = -1 * (e.before.element[this._dimension]() - (s || i))), (this._splitterMaxPosition = e.after.element[this._dimension]() - (r || i));
            },
            _onSplitterDrag: function (t, e, i) {
                var n = this._isColumn ? i : e;
                n > this._splitterMinPosition && n < this._splitterMaxPosition && ((this._splitterPosition = n), t.element.css(this._isColumn ? "top" : "left", n));
            },
            _onSplitterDragStop: function (t) {
                var e = this._getItemsForSplitter(t),
                    i = e.before.element[this._dimension](),
                    n = e.after.element[this._dimension](),
                    s = (this._splitterPosition + i) / (i + n),
                    o = e.before.config[this._dimension] + e.after.config[this._dimension];
                (e.before.config[this._dimension] = s * o), (e.after.config[this._dimension] = (1 - s) * o), t.element.css({ top: 0, left: 0 }), lm.utils.animFrame(lm.utils.fnBind(this.callDownwards, this, ["setSize"]));
            },
        }),
        (lm.items.Stack = function (t, e, i) {
            lm.items.AbstractContentItem.call(this, t, e, i), (this.element = $('<div class="lm_item lm_stack"></div>')), (this._activeContentItem = null);
            var n = t.config;
            (this._header = {
                show: n.settings.hasHeaders === !0 && e.hasHeaders !== !1,
                popout: n.settings.showPopoutIcon && n.labels.popout,
                maximise: n.settings.showMaximiseIcon && n.labels.maximise,
                close: n.settings.showCloseIcon && n.labels.close,
                minimise: n.labels.minimise,
            }),
                n.header && lm.utils.copy(this._header, n.header),
                e.header && lm.utils.copy(this._header, e.header),
                e.content && e.content[0] && e.content[0].header && lm.utils.copy(this._header, e.content[0].header),
                (this._dropZones = {}),
                (this._dropSegment = null),
                (this._contentAreaDimensions = null),
                (this._dropIndex = null),
                (this.isStack = !0),
                (this.childElementContainer = $('<div class="lm_items"></div>')),
                (this.header = new lm.controls.Header(t, this)),
                this.element.append(this.header.element),
                this.element.append(this.childElementContainer),
                this._setupHeaderPosition(),
                this._$validateClosability();
        }),
        lm.utils.extend(lm.items.Stack, lm.items.AbstractContentItem),
        lm.utils.copy(lm.items.Stack.prototype, {
            setSize: function () {
                var t,
                    e = this._header.show ? this.layoutManager.config.dimensions.headerHeight : 0,
                    i = this.element.width() - (this._sided ? e : 0),
                    n = this.element.height() - (this._sided ? 0 : e);
                for (this.childElementContainer.width(i), this.childElementContainer.height(n), t = 0; t < this.contentItems.length; t++) this.contentItems[t].element.width(i).height(n);
                this.emit("resize"), this.emitBubblingEvent("stateChanged");
            },
            _$init: function () {
                var t, e;
                if (this.isInitialised !== !0) {
                    for (lm.items.AbstractContentItem.prototype._$init.call(this), t = 0; t < this.contentItems.length; t++) this.header.createTab(this.contentItems[t]), this.contentItems[t]._$hide();
                    if (this.contentItems.length > 0) {
                        if (((e = this.contentItems[this.config.activeItemIndex || 0]), !e)) throw new Error("Configured activeItemIndex out of bounds");
                        this.setActiveContentItem(e);
                    }
                }
            },
            setActiveContentItem: function (t) {
                if (lm.utils.indexOf(t, this.contentItems) === -1) throw new Error("contentItem is not a child of this stack");
                null !== this._activeContentItem && this._activeContentItem._$hide(),
                    (this._activeContentItem = t),
                    this.header.setActiveContentItem(t),
                    t._$show(),
                    this.emit("activeContentItemChanged", t),
                    this.emitBubblingEvent("stateChanged");
            },
            getActiveContentItem: function () {
                return this.header.activeContentItem;
            },
            addChild: function (t, e) {
                (t = this.layoutManager._$normalizeContentItem(t, this)),
                    lm.items.AbstractContentItem.prototype.addChild.call(this, t, e),
                    this.childElementContainer.append(t.element),
                    this.header.createTab(t, e),
                    this.setActiveContentItem(t),
                    this.callDownwards("setSize"),
                    this._$validateClosability(),
                    this.emitBubblingEvent("stateChanged");
            },
            removeChild: function (t, e) {
                var i = lm.utils.indexOf(t, this.contentItems);
                lm.items.AbstractContentItem.prototype.removeChild.call(this, t, e),
                    this.header.removeTab(t),
                    this.contentItems.length > 0 ? this.setActiveContentItem(this.contentItems[Math.max(i - 1, 0)]) : (this._activeContentItem = null),
                    this._$validateClosability(),
                    this.emitBubblingEvent("stateChanged");
            },
            _$validateClosability: function () {
                var t, e, i;
                for (t = this.header._isClosable(), i = 0, e = this.contentItems.length; i < e && t; i++) t = this.contentItems[i].config.isClosable;
                this.header._$setClosable(t);
            },
            _$destroy: function () {
                lm.items.AbstractContentItem.prototype._$destroy.call(this), this.header._$destroy();
            },
            _$onDrop: function (t) {
                if ("header" === this._dropSegment) return this._resetHeaderDropZone(), void this.addChild(t, this._dropIndex);
                if ("body" === this._dropSegment) return void this.addChild(t);
                var e,
                    i,
                    n,
                    s = "top" === this._dropSegment || "bottom" === this._dropSegment,
                    o = "left" === this._dropSegment || "right" === this._dropSegment,
                    r = "top" === this._dropSegment || "left" === this._dropSegment,
                    a = (s && this.parent.isColumn) || (o && this.parent.isRow),
                    h = s ? "column" : "row",
                    l = s ? "height" : "width";
                t.isComponent && ((i = this.layoutManager.createContentItem({ type: "stack", header: t.config.header || {} }, this)), i._$init(), i.addChild(t), (t = i)),
                    a
                        ? ((e = lm.utils.indexOf(this, this.parent.contentItems)), this.parent.addChild(t, r ? e : e + 1, !0), (this.config[l] *= 0.5), (t.config[l] = this.config[l]), this.parent.callDownwards("setSize"))
                        : ((h = s ? "column" : "row"),
                          (n = this.layoutManager.createContentItem({ type: h }, this)),
                          this.parent.replaceChild(this, n),
                          n.addChild(t, r ? 0 : void 0, !0),
                          n.addChild(this, r ? void 0 : 0, !0),
                          (this.config[l] = 50),
                          (t.config[l] = 50),
                          n.callDownwards("setSize"));
            },
            _$highlightDropZone: function (t, e) {
                var i, n;
                for (i in this._contentAreaDimensions)
                    if (((n = this._contentAreaDimensions[i].hoverArea), n.x1 < t && n.x2 > t && n.y1 < e && n.y2 > e))
                        return void ("header" === i ? ((this._dropSegment = "header"), this._highlightHeaderDropZone(this._sided ? e : t)) : (this._resetHeaderDropZone(), this._highlightBodyDropZone(i)));
            },
            _$getArea: function () {
                if (this.element.is(":visible") === !1) return null;
                var t = lm.items.AbstractContentItem.prototype._$getArea,
                    e = t.call(this, this.header.element),
                    i = t.call(this, this.childElementContainer),
                    n = i.x2 - i.x1,
                    s = i.y2 - i.y1;
                return (
                    (this._contentAreaDimensions = { header: { hoverArea: { x1: e.x1, y1: e.y1, x2: e.x2, y2: e.y2 }, highlightArea: { x1: e.x1, y1: e.y1, x2: e.x2, y2: e.y2 } } }),
                    this._activeContentItem && this._activeContentItem.isComponent === !1
                        ? e
                        : 0 === this.contentItems.length
                        ? ((this._contentAreaDimensions.body = { hoverArea: { x1: i.x1, y1: i.y1, x2: i.x2, y2: i.y2 }, highlightArea: { x1: i.x1, y1: i.y1, x2: i.x2, y2: i.y2 } }), t.call(this, this.element))
                        : ((this._contentAreaDimensions.left = { hoverArea: { x1: i.x1, y1: i.y1, x2: i.x1 + 0.25 * n, y2: i.y2 }, highlightArea: { x1: i.x1, y1: i.y1, x2: i.x1 + 0.5 * n, y2: i.y2 } }),
                          (this._contentAreaDimensions.top = { hoverArea: { x1: i.x1 + 0.25 * n, y1: i.y1, x2: i.x1 + 0.75 * n, y2: i.y1 + 0.5 * s }, highlightArea: { x1: i.x1, y1: i.y1, x2: i.x2, y2: i.y1 + 0.5 * s } }),
                          (this._contentAreaDimensions.right = { hoverArea: { x1: i.x1 + 0.75 * n, y1: i.y1, x2: i.x2, y2: i.y2 }, highlightArea: { x1: i.x1 + 0.5 * n, y1: i.y1, x2: i.x2, y2: i.y2 } }),
                          (this._contentAreaDimensions.bottom = { hoverArea: { x1: i.x1 + 0.25 * n, y1: i.y1 + 0.5 * s, x2: i.x1 + 0.75 * n, y2: i.y2 }, highlightArea: { x1: i.x1, y1: i.y1 + 0.5 * s, x2: i.x2, y2: i.y2 } }),
                          t.call(this, this.element))
                );
            },
            _highlightHeaderDropZone: function (t) {
                var e,
                    i,
                    n,
                    s,
                    o,
                    r,
                    a,
                    h,
                    l,
                    m = this.header.tabs.length,
                    c = !1;
                if (0 === m)
                    return (
                        (a = this.header.element.offset()), void this.layoutManager.dropTargetIndicator.highlightArea({ x1: a.left, x2: a.left + 100, y1: a.top + this.header.element.height() - 20, y2: a.top + this.header.element.height() })
                    );
                for (e = 0; e < m; e++)
                    if (((i = this.header.tabs[e].element), (o = i.offset()), this._sided ? ((s = o.top), (n = o.left), (h = i.height())) : ((s = o.left), (n = o.top), (h = i.width())), t > s && t < s + h)) {
                        c = !0;
                        break;
                    }
                if (!(c === !1 && t < s)) {
                    if (((l = s + h / 2), t < l ? ((this._dropIndex = e), i.before(this.layoutManager.tabDropPlaceholder)) : ((this._dropIndex = Math.min(e + 1, m)), i.after(this.layoutManager.tabDropPlaceholder)), this._sided))
                        return (
                            (placeHolderTop = this.layoutManager.tabDropPlaceholder.offset().top),
                            void this.layoutManager.dropTargetIndicator.highlightArea({ x1: n, x2: n + i.innerHeight(), y1: placeHolderTop, y2: placeHolderTop + this.layoutManager.tabDropPlaceholder.width() })
                        );
                    (r = this.layoutManager.tabDropPlaceholder.offset().left), this.layoutManager.dropTargetIndicator.highlightArea({ x1: r, x2: r + this.layoutManager.tabDropPlaceholder.width(), y1: n, y2: n + i.innerHeight() });
                }
            },
            _resetHeaderDropZone: function () {
                this.layoutManager.tabDropPlaceholder.remove();
            },
            _setupHeaderPosition: function () {
                var t = ["right", "left", "bottom"].indexOf(this._header.show) >= 0 && this._header.show;
                if (
                    (this.header.element.toggle(!!this._header.show),
                    (this._side = t),
                    (this._sided = ["right", "left"].indexOf(this._side) >= 0),
                    this.element.removeClass("lm_left lm_right lm_bottom"),
                    this._side && this.element.addClass("lm_" + this._side),
                    this.element.find(".lm_header").length && this.childElementContainer)
                ) {
                    var e = ["right", "bottom"].indexOf(this._side) >= 0 ? "before" : "after";
                    this.header.element[e](this.childElementContainer), this.callDownwards("setSize");
                }
            },
            _highlightBodyDropZone: function (t) {
                var e = this._contentAreaDimensions[t].highlightArea;
                this.layoutManager.dropTargetIndicator.highlightArea(e), (this._dropSegment = t);
            },
        }),
        (lm.utils.BubblingEvent = function (t, e) {
            (this.name = t), (this.origin = e), (this.isPropagationStopped = !1);
        }),
        (lm.utils.BubblingEvent.prototype.stopPropagation = function () {
            this.isPropagationStopped = !0;
        }),
        (lm.utils.ConfigMinifier = function () {
            (this._keys = [
                "settings",
                "hasHeaders",
                "constrainDragToContainer",
                "selectionEnabled",
                "dimensions",
                "borderWidth",
                "minItemHeight",
                "minItemWidth",
                "headerHeight",
                "dragProxyWidth",
                "dragProxyHeight",
                "labels",
                "close",
                "maximise",
                "minimise",
                "popout",
                "content",
                "componentName",
                "componentState",
                "id",
                "width",
                "type",
                "height",
                "isClosable",
                "title",
                "popoutWholeStack",
                "openPopouts",
                "parentId",
                "activeItemIndex",
                "reorderEnabled",
            ]),
                (this._values = [!0, !1, "row", "column", "stack", "component", "close", "maximise", "minimise", "open in new window"]);
        }),
        lm.utils.copy(lm.utils.ConfigMinifier.prototype, {
            minifyConfig: function (t) {
                var e = {};
                return this._nextLevel(t, e, "_min"), e;
            },
            unminifyConfig: function (t) {
                var e = {};
                return this._nextLevel(t, e, "_max"), e;
            },
            _nextLevel: function (t, e, i) {
                var n, s;
                for (n in t)
                    t instanceof Array && (n = parseInt(n, 10)),
                        t.hasOwnProperty(n) && ((s = this[i](n, this._keys)), "object" == typeof t[n] ? ((e[s] = t[n] instanceof Array ? [] : {}), this._nextLevel(t[n], e[s], i)) : (e[s] = this[i](t[n], this._values)));
            },
            _min: function (t, e) {
                if ("string" == typeof t && 1 === t.length) return "___" + t;
                var i = lm.utils.indexOf(t, e);
                return i === -1 ? t : i.toString(36);
            },
            _max: function (t, e) {
                return "string" == typeof t && 1 === t.length ? e[parseInt(t, 36)] : "string" == typeof t && "___" === t.substr(0, 3) ? t[3] : t;
            },
        }),
        (lm.utils.EventHub = function (t) {
            lm.utils.EventEmitter.call(this),
                (this._layoutManager = t),
                (this._dontPropagateToParent = null),
                (this._childEventSource = null),
                this.on(lm.utils.EventEmitter.ALL_EVENT, lm.utils.fnBind(this._onEventFromThis, this)),
                (this._boundOnEventFromChild = lm.utils.fnBind(this._onEventFromChild, this)),
                $(window).on("gl_child_event", this._boundOnEventFromChild);
        }),
        (lm.utils.EventHub.prototype._onEventFromThis = function () {
            var t = Array.prototype.slice.call(arguments);
            this._layoutManager.isSubWindow && t[0] !== this._dontPropagateToParent && this._propagateToParent(t), this._propagateToChildren(t), (this._dontPropagateToParent = null), (this._childEventSource = null);
        }),
        (lm.utils.EventHub.prototype._$onEventFromParent = function (t) {
            (this._dontPropagateToParent = t[0]), this.emit.apply(this, t);
        }),
        (lm.utils.EventHub.prototype._onEventFromChild = function (t) {
            (this._childEventSource = t.originalEvent.__gl), this.emit.apply(this, t.originalEvent.__glArgs);
        }),
        (lm.utils.EventHub.prototype._propagateToParent = function (t) {
            var e,
                i = "gl_child_event";
            document.createEvent ? ((e = window.opener.document.createEvent("HTMLEvents")), e.initEvent(i, !0, !0)) : ((e = window.opener.document.createEventObject()), (e.eventType = i)),
                (e.eventName = i),
                (e.__glArgs = t),
                (e.__gl = this._layoutManager),
                document.createEvent ? window.opener.dispatchEvent(e) : window.opener.fireEvent("on" + e.eventType, e);
        }),
        (lm.utils.EventHub.prototype._propagateToChildren = function (t) {
            var e, i;
            for (i = 0; i < this._layoutManager.openPopouts.length; i++) (e = this._layoutManager.openPopouts[i].getGlInstance()), e && e !== this._childEventSource && e.eventHub._$onEventFromParent(t);
        }),
        (lm.utils.EventHub.prototype.destroy = function () {
            $(window).off("gl_child_event", this._boundOnEventFromChild);
        }),
        (lm.utils.ReactComponentHandler = function (t, e) {
            (this._reactComponent = null),
                (this._originalComponentWillUpdate = null),
                (this._container = t),
                (this._initialState = e),
                (this._reactClass = this._getReactClass()),
                this._container.on("open", this._render, this),
                this._container.on("destroy", this._destroy, this);
        }),
        lm.utils.copy(lm.utils.ReactComponentHandler.prototype, {
            _render: function () {
                (this._reactComponent = ReactDOM.render(this._getReactComponent(), this._container.getElement()[0])),
                    (this._originalComponentWillUpdate = this._reactComponent.componentWillUpdate || function () {}),
                    (this._reactComponent.componentWillUpdate = this._onUpdate.bind(this)),
                    this._container.getState() && this._reactComponent.setState(this._container.getState());
            },
            _destroy: function () {
                ReactDOM.unmountComponentAtNode(this._container.getElement()[0]), this._container.off("open", this._render, this), this._container.off("destroy", this._destroy, this);
            },
            _onUpdate: function (t, e) {
                this._container.setState(e), this._originalComponentWillUpdate.call(this._reactComponent, t, e);
            },
            _getReactClass: function () {
                var t,
                    e = this._container._config.component;
                if (!e) throw new Error("No react component name. type: react-component needs a field `component`");
                if (((t = this._container.layoutManager.getComponent(e)), !t)) throw new Error('React component "' + e + '" not found. Please register all components with GoldenLayout using `registerComponent(name, component)`');
                return t;
            },
            _getReactComponent: function () {
                var t = { glEventHub: this._container.layoutManager.eventHub, glContainer: this._container },
                    e = $.extend(t, this._container._config.props);
                return React.createElement(this._reactClass, e);
            },
        });
})(window.$);
