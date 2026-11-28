import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"
import "../services"

FocusScope {
    id: root
    required property var shellState

    implicitWidth: 880
    implicitHeight: 540

    // Picker mode configuration
    property bool isPicker: false
    property string pickerActionMode: "upload" // "upload" | "download"
    property bool pickerMultiple: false
    property bool pickerDirectory: false
    property string pickerTitle: "File Chooser"
    property string pickerSubtitle: "xdg-desktop-portal"
    property string pickerBadgeText: "Upload (Open File)"
    property string pickerAcceptLabel: ""
    property var pickerFilters: []
    property string filterType: "all" // "all" | "image" | "document" | "code" | "archive" | "media" | "portal"
    property int activePortalFilterIdx: -1
    property var selectedPaths: []
    property bool previewDismissed: false
    property int _previewSeq: 0
    property var _previewDisplayItem: null
    property string _previewDisplayLabel: ""
    property string _previewDisplayMode: ""
    property string _previewMediaSource: ""
    property string _previewText: ""
    property bool filterMenuOpen: false

    // Extendable preview handler registry: add a FileService.classifyType() key
    // with { label, mode, load(item, done) } to support more file types later.
    readonly property var previewHandlers: ({
        image: {
            label: "Image",
            mode: "image",
            load: (item, done) => done({ source: FileService.fileUrl(item.path) })
        },
        video: {
            label: "Video",
            mode: "video",
            load: (item, done) => FileService.requestVideoThumb(item.path, (url) => done({ source: url }))
        }
    })

    function previewHandlerFor(item) {
        return (item && item.type && previewHandlers[item.type]) ? previewHandlers[item.type] : null;
    }

    readonly property var previewItem: selectedPaths.length === 1 ? getPrimarySelectedItem() : null
    readonly property var activePreviewHandler: previewHandlerFor(previewItem)
    readonly property bool showPreviewPanel: !archiverActive && activePreviewHandler !== null && !previewDismissed

    onSelectedPathsChanged: {
        previewDismissed = false;
    }

    onPreviewItemChanged: {
        const item = previewItem;
        const handler = previewHandlerFor(item);
        const seq = ++_previewSeq;
        if (!handler) return;
        _previewDisplayItem = item;
        _previewDisplayLabel = handler.label || item.type;
        _previewDisplayMode = handler.mode || "image";
        _previewMediaSource = "";
        _previewText = "";
        handler.load(item, (res) => {
            if (!root || seq !== root._previewSeq) return;
            if (res && res.source !== undefined) root._previewMediaSource = String(res.source || "");
            if (res && res.text !== undefined) root._previewText = String(res.text || "");
        });
    }

    onShowPreviewPanelChanged: {
        if (showPreviewPanel && !isListView && lastSelectedIdx >= 0) {
            Qt.callLater(() => {
                if (root && root.showPreviewPanel && !root.isListView && root.lastSelectedIdx >= 0 && root.lastSelectedIdx < viewModel.count) {
                    filesGrid.forceLayout();
                    filesGrid.positionViewAtIndex(root.lastSelectedIdx, GridView.Contain);
                }
            });
        }
    }

    signal pickerSubmitted(var paths)
    signal pickerCancelled()

    // Filesystem & view state
    property string currentPath: FileService.homeDir
    property string virtualMode: "" // "" | "recent" | "starred"
    property var currentItems: []
    property var history: [FileService.homeDir]
    property int historyIdx: 0
    property bool isListView: false
    property bool showHidden: false
    property string sortBy: "name" // "name" | "mtime" | "size" | "type"
    property bool sortAsc: true
    property string searchQuery: ""
    property bool isDeepSearch: false
    property int lastSelectedIdx: -1
    property string statusMessage: ""
    property string loadError: ""
    property string diskInfo: ""
    property bool isLoading: true
    property bool _hasLoadedOnce: false
    property int _navSeq: 0

    readonly property bool _isDetachedWindow: Boolean(root.shellState && (root.shellState.detachedApp === "files" || root.shellState.detachedApp === "picker"))
    readonly property int _appBottomRadius: _isDetachedWindow ? 13 : ((!root.shellState || root.shellState.barPosition !== "bottom") ? 17 : 0)
    readonly property int _appTopRadius: (!_isDetachedWindow && root.shellState && root.shellState.barPosition === "bottom") ? 17 : 0

    // Collapsible sidebar groups
    property bool placesOpen: true
    property bool libraryOpen: true

    // Real transfer progress state
    property bool transferActive: false
    property string transferLabel: ""
    property string transferSub: ""
    property int transferPct: 0
    property string transferDestDir: ""
    property double transferBaselineBytes: 0
    property double transferTotalBytes: 0

    // Inline path editing
    property bool pathEditing: false

    // Archiver & Password modal state
    property bool archiverActive: false
    property bool archiverLoading: false
    property string archiverArchivePath: ""
    property string archiverArchiveName: ""
    property var archiverEntries: []
    property string archiverError: ""
    property int _archiveSeq: 0

    readonly property var filteredArchiveEntries: {
        const list = archiverEntries || [];
        const q = searchQuery.trim().toLowerCase();
        if (q === "") return list;
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            if (String(list[i].name || "").toLowerCase().indexOf(q) !== -1) out.push(list[i]);
        }
        return out;
    }

    property bool passwordOpen: false
    property string passwordTargetPath: ""
    property string passwordTargetName: ""
    property string passwordError: ""

    // Input modal state ("mkdir" | "mkfile" | "rename")
    property bool inputModalOpen: false
    property string inputModalMode: ""
    property string inputModalTitle: ""
    property string inputModalValue: ""
    property string inputModalTargetPath: ""
    property string inputModalError: ""

    // Confirm modal state ("trash" | "permanent" | "empty_trash" | "overwrite")
    property bool confirmOpen: false
    property string confirmMode: "trash"
    property var confirmPaths: []
    property string confirmTitle: ""
    property string confirmLabel: ""
    property string confirmSub: ""

    // Properties modal state
    property bool propsOpen: false
    property string propsName: ""
    property string propsPath: ""
    property var propsData: null

    // Built-in media viewer state (image & video)
    property bool viewerOpen: false
    property var viewerItems: []
    property int viewerIndex: -1
    property int viewerStepDir: 0
    readonly property var viewerItem: (viewerIndex >= 0 && viewerIndex < viewerItems.length) ? viewerItems[viewerIndex] : null

    readonly property bool isInTrash: virtualMode === "" && (currentPath === FileService.trashDir || currentPath.startsWith(FileService.trashDir + "/"))
    readonly property bool anyModalOpen: passwordOpen || inputModalOpen || confirmOpen || propsOpen || viewerOpen

    readonly property var libraryItems: [
        { key: "recent", label: "Recent", icon: "clock" },
        { key: "starred", label: "Starred", icon: "star" }
    ]

    readonly property var breadcrumbSegments: {
        let segs = [];
        if (virtualMode === "recent") {
            segs = [{ label: "Recent Files", path: "", clickable: false }];
        } else if (virtualMode === "starred") {
            segs = [{ label: "Starred Items", path: "", clickable: false }];
        } else if (currentPath === FileService.trashDir) {
            segs = [{ label: "Trash", path: FileService.trashDir, clickable: true }];
        } else {
            let rel = "";
            if (currentPath === FileService.homeDir || currentPath.startsWith(FileService.homeDir + "/")) {
                segs.push({ label: "~", path: FileService.homeDir, clickable: true });
                rel = currentPath.slice(FileService.homeDir.length);
            } else {
                segs.push({ label: "/", path: "/", clickable: true });
                rel = currentPath === "/" ? "" : currentPath;
            }
            const parts = rel.split("/").filter(Boolean);
            let acc = segs[0].path;
            for (let i = 0; i < parts.length; ++i) {
                acc = (acc === "/" ? "" : acc) + "/" + parts[i];
                segs.push({ label: parts[i], path: acc, clickable: true });
            }
        }
        if (archiverActive && archiverArchiveName !== "") {
            segs.push({ label: archiverArchiveName, path: "", clickable: false, isArchive: true });
        }
        if (segs.length > 4) {
            return [
                segs[0],
                { label: "…", path: "", clickable: false },
                segs[segs.length - 2],
                segs[segs.length - 1]
            ];
        }
        return segs;
    }

    readonly property string activeFilterLabel: {
        if (filterType === "portal" && pickerFilters && activePortalFilterIdx >= 0 && activePortalFilterIdx < pickerFilters.length) {
            return pickerFilters[activePortalFilterIdx].label;
        }
        if (filterType === "image") return "Images (*.png, *.jpg, *.webp)";
        if (filterType === "document") return "Documents (*.pdf, *.txt, *.md)";
        if (filterType === "code") return "Config & Code (*.qml, *.py, *.json)";
        if (filterType === "archive") return "Archives (*.pak, *.zip, *.tar, *.7z)";
        if (filterType === "media") return "Audio & Video";
        return "All Files (*.*)";
    }

    readonly property var visibleItems: {
        const list = currentItems || [];
        const q = isDeepSearch ? "" : searchQuery.trim().toLowerCase();
        const applyTypeFilter = isPicker && filterType !== "all";
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            const it = list[i];
            if (q !== "" && it.name.toLowerCase().indexOf(q) === -1) continue;
            if (applyTypeFilter && it.type !== "folder" && !matchesActiveFilter(it)) continue;
            out.push(it);
        }
        return FileService.sortItems(out, sortBy, sortAsc);
    }

    ListModel {
        id: viewModel
    }

    ListModel {
        id: emptyModel
    }

    // Tab state (Manager mode only, synced with FileService for Island <-> Detached persistence)
    ListModel {
        id: tabsModel
    }
    property int activeTabIndex: 0
    property bool _switchingTab: false

    function tabMetaFor(path, vMode) {
        if (vMode === "recent") return { label: "Recent", icon: "clock" };
        if (vMode === "starred") return { label: "Starred", icon: "star" };
        const p = path || FileService.homeDir;
        if (p === FileService.homeDir) return { label: "Home", icon: "home" };
        if (p === FileService.trashDir) return { label: "Trash", icon: "trash" };
        if (p === "/") return { label: "/", icon: "hard-drive" };
        const places = FileService.resolvedPlaces || [];
        for (let i = 0; i < places.length; ++i) {
            if (places[i].path === p) return { label: places[i].label, icon: places[i].icon || "folder" };
        }
        const parts = p.split("/").filter(Boolean);
        return { label: parts.length > 0 ? parts[parts.length - 1] : "/", icon: "folder" };
    }

    function _makeTabObj(targetPath, vMode) {
        const p = expandUserPath(targetPath || FileService.homeDir);
        const vm = vMode || "";
        return {
            id: FileService._nextTabId++,
            path: p,
            virtualMode: vm,
            history: [p],
            historyIdx: 0,
            searchQuery: "",
            isDeepSearch: false
        };
    }

    function _toTabRow(t) {
        const m = tabMetaFor(t.path, t.virtualMode);
        return {
            tabId: Number(t.id),
            label: String(m.label),
            icon: String(m.icon),
            path: String(t.path || ""),
            virtualMode: String(t.virtualMode || "")
        };
    }

    function syncActiveTab() {
        if (isPicker || _switchingTab) return;
        const list = FileService.tabs || [];
        if (activeTabIndex < 0 || activeTabIndex >= list.length) return;
        const cur = list[activeTabIndex];
        cur.path = currentPath;
        cur.virtualMode = virtualMode;
        cur.history = (history || [currentPath]).slice();
        cur.historyIdx = historyIdx;
        cur.searchQuery = searchQuery;
        cur.isDeepSearch = isDeepSearch;
        if (activeTabIndex < tabsModel.count) {
            const m = tabMetaFor(cur.path, cur.virtualMode);
            if (tabsModel.get(activeTabIndex).label !== m.label) tabsModel.setProperty(activeTabIndex, "label", m.label);
            if (tabsModel.get(activeTabIndex).icon !== m.icon) tabsModel.setProperty(activeTabIndex, "icon", m.icon);
            if (tabsModel.get(activeTabIndex).path !== cur.path) tabsModel.setProperty(activeTabIndex, "path", cur.path);
            if (tabsModel.get(activeTabIndex).virtualMode !== cur.virtualMode) tabsModel.setProperty(activeTabIndex, "virtualMode", cur.virtualMode);
        }
    }

    function initTabs() {
        if (isPicker) return;
        let list = (FileService.tabs || []).slice();
        const start = FileService.lastPath || FileService.homeDir;
        if (list.length === 0) {
            list = [_makeTabObj(start, "")];
            FileService.tabs = list;
            FileService.activeTabIndex = 0;
        }
        const idx = Math.max(0, Math.min(FileService.activeTabIndex || 0, list.length - 1));
        FileService.activeTabIndex = idx;
        tabsModel.clear();
        for (let i = 0; i < list.length; ++i) {
            tabsModel.append(_toTabRow(list[i]));
        }
        activeTabIndex = idx;
        if (FileService.pendingSelectPath !== "") {
            const t = list[idx];
            t.path = start;
            t.virtualMode = "";
            if (t.history[t.historyIdx] !== start) {
                t.history = t.history.slice(0, t.historyIdx + 1);
                t.history.push(start);
                t.historyIdx = t.history.length - 1;
            }
            const m = tabMetaFor(start, "");
            tabsModel.setProperty(idx, "label", m.label);
            tabsModel.setProperty(idx, "icon", m.icon);
            tabsModel.setProperty(idx, "path", start);
            tabsModel.setProperty(idx, "virtualMode", "");
        }
        _applyTabAt(idx);
    }

    function _applyTabAt(idx) {
        const list = FileService.tabs || [];
        if (idx < 0 || idx >= list.length) return;
        const t = list[idx];
        _switchingTab = true;
        activeTabIndex = idx;
        FileService.activeTabIndex = idx;
        archiverActive = false;
        pathEditing = false;
        loadError = "";
        selectedPaths = [];
        lastSelectedIdx = -1;
        currentPath = t.path || FileService.homeDir;
        virtualMode = t.virtualMode || "";
        history = (t.history && t.history.length > 0) ? t.history.slice() : [currentPath];
        historyIdx = Math.max(0, Math.min(t.historyIdx || 0, history.length - 1));
        searchQuery = t.searchQuery || "";
        isDeepSearch = Boolean(t.isDeepSearch);
        if (searchField && searchField.text !== searchQuery) searchField.text = searchQuery;
        _switchingTab = false;
        if (virtualMode === "") FileService.lastPath = currentPath;
        if (isDeepSearch && searchQuery.trim() !== "" && virtualMode === "") {
            runDeepSearch();
        } else {
            refreshCurrent();
        }
        if (tabList) Qt.callLater(() => { if (tabList && idx < tabsModel.count) tabList.positionViewAtIndex(idx, ListView.Contain); });
    }

    function switchTab(idx) {
        if (isPicker) return;
        const list = FileService.tabs || [];
        if (idx < 0 || idx >= list.length || idx === activeTabIndex) return;
        syncActiveTab();
        _applyTabAt(idx);
    }

    function openTab(targetPath, vMode, activate) {
        if (isPicker) return;
        syncActiveTab();
        const t = _makeTabObj(targetPath || currentPath || FileService.homeDir, vMode || "");
        const list = (FileService.tabs || []).slice();
        list.push(t);
        FileService.tabs = list;
        tabsModel.append(_toTabRow(t));
        const newIdx = list.length - 1;
        if (activate !== false) {
            _applyTabAt(newIdx);
        } else if (tabList) {
            Qt.callLater(() => { if (tabList && newIdx < tabsModel.count) tabList.positionViewAtIndex(newIdx, ListView.Contain); });
        }
    }

    function closeTab(idx) {
        if (isPicker) return;
        const list = (FileService.tabs || []).slice();
        if (list.length <= 1 || idx < 0 || idx >= list.length) return;
        if (idx === activeTabIndex) syncActiveTab();
        list.splice(idx, 1);
        FileService.tabs = list;
        tabsModel.remove(idx, 1);
        if (idx === activeTabIndex) {
            _applyTabAt(Math.min(idx, list.length - 1));
        } else if (idx < activeTabIndex) {
            activeTabIndex = activeTabIndex - 1;
            FileService.activeTabIndex = activeTabIndex;
        }
    }

    function closeOtherTabs(keepIdx) {
        if (isPicker) return;
        const list = (FileService.tabs || []).slice();
        if (list.length <= 1 || keepIdx < 0 || keepIdx >= list.length) return;
        syncActiveTab();
        const kept = list[keepIdx];
        for (let i = tabsModel.count - 1; i >= 0; --i) {
            if (i !== keepIdx) tabsModel.remove(i, 1);
        }
        FileService.tabs = [kept];
        if (activeTabIndex !== keepIdx) {
            _applyTabAt(0);
        } else {
            activeTabIndex = 0;
            FileService.activeTabIndex = 0;
        }
    }

    function nextTab() {
        if (isPicker || tabsModel.count <= 1) return;
        switchTab((activeTabIndex + 1) % tabsModel.count);
    }

    function prevTab() {
        if (isPicker || tabsModel.count <= 1) return;
        switchTab((activeTabIndex - 1 + tabsModel.count) % tabsModel.count);
    }

    function openTabContextMenu(srcItem, mouse, tabIdx) {
        if (isPicker) return;
        const list = FileService.tabs || [];
        if (tabIdx < 0 || tabIdx >= list.length) return;
        const pt = srcItem.mapToItem(root, mouse.x, mouse.y);
        const t = list[tabIdx];
        ctxMenu.menuWidth = 200;
        ctxMenu.openAt(pt.x, pt.y, [
            { text: "Duplicate Tab", iconName: "copy", action: () => openTab(t.path, t.virtualMode, true) },
            { separator: true },
            { text: "Close Tab", iconName: "close", shortcut: "Ctrl+W", enabled: list.length > 1, action: () => closeTab(tabIdx) },
            { text: "Close Other Tabs", iconName: "close", enabled: list.length > 1, action: () => closeOtherTabs(tabIdx) }
        ]);
    }

    property string _lastModelContext: ""
    property bool _transitionsEnabled: false

    Timer {
        id: animEnableTimer
        interval: 60
        repeat: false
        onTriggered: if (root) root._transitionsEnabled = true
    }

    function _toRowObj(it) {
        return {
            name: String(it.name || ""),
            path: String(it.path || ""),
            parentDir: String(it.parentDir || ""),
            relPath: String(it.relPath || ""),
            type: String(it.type || "file"),
            size: Number(it.size || 0),
            mtime: Number(it.mtime || 0),
            modifiedText: String(it.modifiedText || ""),
            meta: String(it.meta || "")
        };
    }

    function syncViewModel() {
        const nextList = visibleItems || [];
        const ctx = virtualMode + "::" + currentPath + "::" + (isDeepSearch ? "deep" : "dir") + "::" + (isListView ? "list" : "grid");
        if (_lastModelContext !== ctx || (viewModel.count === 0 && nextList.length > 0)) {
            const contextChanged = _lastModelContext !== ctx;
            _lastModelContext = ctx;
            _transitionsEnabled = false;
            viewModel.clear();
            for (let i = 0; i < nextList.length; ++i) {
                viewModel.append(_toRowObj(nextList[i]));
            }
            if (contextChanged) {
                if (filesGrid) filesGrid.contentY = 0;
                if (filesList) filesList.contentY = 0;
            }
            animEnableTimer.interval = 60;
            animEnableTimer.restart();
            return;
        }

        // Build lookup set of target paths
        const nextSet = {};
        for (let i = 0; i < nextList.length; ++i) {
            nextSet[nextList[i].path] = true;
        }

        // 1. Remove items no longer in nextList (triggers remove + displaced slide-up)
        for (let i = viewModel.count - 1; i >= 0; --i) {
            const p = viewModel.get(i).path;
            if (!nextSet[p]) {
                viewModel.remove(i, 1);
            }
        }

        // 2. Insert new items & reorder existing items (triggers add + move + displaced slide-down)
        for (let i = 0; i < nextList.length; ++i) {
            const target = nextList[i];
            let foundIdx = -1;
            for (let j = i; j < viewModel.count; ++j) {
                if (viewModel.get(j).path === target.path) {
                    foundIdx = j;
                    break;
                }
            }
            if (foundIdx === -1) {
                viewModel.insert(i, _toRowObj(target));
            } else {
                if (foundIdx !== i) {
                    viewModel.move(foundIdx, i, 1);
                }
                const cur = viewModel.get(i);
                if (cur.name !== target.name) viewModel.setProperty(i, "name", String(target.name || ""));
                if (cur.size !== Number(target.size || 0)) viewModel.setProperty(i, "size", Number(target.size || 0));
                if (cur.mtime !== Number(target.mtime || 0)) viewModel.setProperty(i, "mtime", Number(target.mtime || 0));
                if (cur.modifiedText !== String(target.modifiedText || "")) viewModel.setProperty(i, "modifiedText", String(target.modifiedText || ""));
                if (cur.meta !== String(target.meta || "")) viewModel.setProperty(i, "meta", String(target.meta || ""));
            }
        }
    }

    onVisibleItemsChanged: syncViewModel()
    onIsListViewChanged: syncViewModel()

    readonly property bool canPickerSubmit: {
        if (!isPicker) return false;
        if (pickerDirectory) return true;
        if (pickerMultiple && selectedPaths.length > 0) return true;
        return nameField.text.trim() !== "";
    }

    function matchesPortalPatterns(item, patterns) {
        if (!patterns || patterns.length === 0) return true;
        const name = (item.name || "").toLowerCase();
        for (let i = 0; i < patterns.length; ++i) {
            const p = patterns[i];
            if (!p) continue;
            const pat = String(p.pattern || "").trim().toLowerCase();
            if (!pat || pat === "*" || pat === "*.*" || pat === "*/*") return true;
            if (p.kind === 1) {
                if (pat.startsWith("image/") && item.type === "image") return true;
                if (pat.startsWith("video/") && item.type === "video") return true;
                if (pat.startsWith("audio/") && item.type === "music") return true;
                if (pat.startsWith("text/") && (item.type === "code" || item.type === "document")) return true;
                if (pat === "application/pdf" && name.endsWith(".pdf")) return true;
                if ((pat === "application/zip" || pat.indexOf("compressed") !== -1 || pat.indexOf("archive") !== -1) && item.type === "archive") return true;
            } else {
                const regexStr = "^" + pat.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$";
                try {
                    if (new RegExp(regexStr, "i").test(name)) return true;
                } catch (e) {}
            }
        }
        return false;
    }

    function matchesActiveFilter(item) {
        if (filterType === "all") return true;
        if (filterType === "portal" && pickerFilters && activePortalFilterIdx >= 0 && activePortalFilterIdx < pickerFilters.length) {
            return matchesPortalPatterns(item, pickerFilters[activePortalFilterIdx].patterns);
        }
        if (filterType === "media") return item.type === "music" || item.type === "video";
        return item.type === filterType;
    }

    function isPathSelected(path) {
        return selectedPaths.indexOf(path) !== -1;
    }

    function getSelectedItems() {
        const list = visibleItems || [];
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            if (selectedPaths.indexOf(list[i].path) !== -1) out.push(list[i]);
        }
        return out;
    }

    function getPrimarySelectedItem() {
        const list = visibleItems || [];
        for (let i = 0; i < list.length; ++i) {
            if (selectedPaths.indexOf(list[i].path) !== -1) return list[i];
        }
        return null;
    }

    function selectedTotalBytes() {
        const sel = getSelectedItems();
        let sum = 0;
        let hasFiles = false;
        for (let i = 0; i < sel.length; ++i) {
            if (sel[i].type !== "folder" && sel[i].size > 0) {
                sum += sel[i].size;
                hasFiles = true;
            }
        }
        return hasFiles ? FileService.formatSize(sum) : "";
    }

    function displayPath(p) {
        if (!p) return "~";
        if (p === FileService.homeDir) return "~";
        if (p.startsWith(FileService.homeDir + "/")) return "~" + p.slice(FileService.homeDir.length);
        return p;
    }

    function expandUserPath(raw) {
        const s = String(raw || "").trim();
        if (!s || s === "~") return FileService.homeDir;
        if (s.startsWith("~/")) return FileService.homeDir + s.slice(1);
        return s;
    }

    function iconFor(type) {
        return FileService.iconForType(type);
    }

    function iconColorFor(type) {
        const a = Theme.accent;
        const t = Theme.text;
        const mono = a.hslSaturation < 0.08;
        if (mono) {
            if (type === "folder") return t;
            if (type === "code" || type === "image" || type === "video" || type === "music") return Qt.rgba(t.r, t.g, t.b, 0.88);
            if (type === "archive" || type === "document") return Qt.rgba(t.r, t.g, t.b, 0.78);
            return Theme.textSub;
        }
        const s = Math.min(0.45, Math.max(0.24, a.hslSaturation * 0.88));
        if (type === "folder") return a;
        if (type === "code") return Qt.hsla((a.hslHue + 0.05) % 1.0, s, 0.76, 1.0);
        if (type === "image") return Qt.hsla((a.hslHue + 0.90) % 1.0, s, 0.76, 1.0);
        if (type === "video") return Qt.hsla((a.hslHue + 0.14) % 1.0, s, 0.75, 1.0);
        if (type === "music") return Qt.hsla((a.hslHue + 0.80) % 1.0, s, 0.75, 1.0);
        if (type === "archive") return Qt.hsla(0.10, s, 0.74, 1.0);
        if (type === "document") return Qt.rgba(t.r * 0.74 + a.r * 0.26, t.g * 0.74 + a.g * 0.26, t.b * 0.74 + a.b * 0.26, 0.95);
        return Qt.rgba(t.r, t.g, t.b, 0.74);
    }

    function refreshCurrent() {
        if (archiverActive && archiverArchivePath !== "") {
            openArchiveInspector({ path: archiverArchivePath, name: archiverArchiveName });
            return;
        }
        if (virtualMode === "recent") {
            loadRecent();
            return;
        }
        if (virtualMode === "starred") {
            loadStarred();
            return;
        }
        const seq = ++_navSeq;
        isLoading = true;
        isDeepSearch = false;
        loadError = "";
        const target = currentPath;
        FileService.listDir(target, showHidden, (ok, items, err) => {
            if (!root || seq !== root._navSeq) return;
            root.isLoading = false;
            root._hasLoadedOnce = true;
            if (!ok) {
                root.currentItems = [];
                root.loadError = err || "Cannot open directory";
                root.statusMessage = root.loadError;
                return;
            }
            root.loadError = "";
            root.currentItems = items;
            root.statusMessage = items.length + (items.length === 1 ? " item" : " items");
            if (!root.isPicker && FileService.pendingSelectPath !== "") {
                const want = FileService.pendingSelectPath;
                FileService.pendingSelectPath = "";
                for (let i = 0; i < items.length; ++i) {
                    if (items[i].path === want) {
                        root.selectedPaths = [want];
                        root.lastSelectedIdx = i;
                        break;
                    }
                }
            }
            if (!root.isPicker) {
                FileService.getDiskUsage(target, (info) => {
                    if (root && seq === root._navSeq) root.diskInfo = info;
                });
            }
        });
    }

    function loadRecent() {
        const seq = ++_navSeq;
        virtualMode = "recent";
        archiverActive = false;
        isDeepSearch = false;
        loadError = "";
        isLoading = true;
        selectedPaths = [];
        lastSelectedIdx = -1;
        currentItems = [];
        syncActiveTab();
        if (isPicker && pickerDirectory) nameField.text = "";
        FileService.listRecent((ok, items) => {
            if (!root || seq !== root._navSeq) return;
            isLoading = false;
            _hasLoadedOnce = true;
            currentItems = items || [];
            statusMessage = currentItems.length + " recent files";
        });
    }

    function loadStarred() {
        ++_navSeq;
        virtualMode = "starred";
        archiverActive = false;
        isDeepSearch = false;
        loadError = "";
        isLoading = false;
        _hasLoadedOnce = true;
        selectedPaths = [];
        lastSelectedIdx = -1;
        if (isPicker && pickerDirectory) nameField.text = "";
        const out = [];
        const stars = FileService.starredPaths || [];
        for (let i = 0; i < stars.length; ++i) {
            const p = stars[i];
            const slash = p.lastIndexOf("/");
            const name = slash >= 0 ? p.slice(slash + 1) : p;
            const parent = slash > 0 ? p.slice(0, slash) : "/";
            out.push({
                name: name,
                path: p,
                parentDir: parent,
                type: FileService.classifyType(name, "f"),
                size: 0,
                mtime: 0,
                modifiedText: "",
                isHidden: name.startsWith("."),
                meta: displayPath(parent)
            });
        }
        currentItems = out;
        syncActiveTab();
        statusMessage = out.length + " starred items";
    }

    function runDeepSearch() {
        const q = searchField.text.trim();
        if (virtualMode !== "" || q === "") return;
        const seq = ++_navSeq;
        isLoading = true;
        loadError = "";
        isDeepSearch = true;
        syncActiveTab();
        FileService.searchFiles(currentPath, q, showHidden, (ok, items, err) => {
            if (!root || seq !== root._navSeq) return;
            isLoading = false;
            _hasLoadedOnce = true;
            if (!ok) {
                loadError = err || "Search failed";
                currentItems = [];
                statusMessage = loadError;
                return;
            }
            currentItems = items;
            statusMessage = "Deep search: " + items.length + (items.length === 1 ? " match" : " matches");
        });
    }

    function navigateTo(rawPath) {
        const target = expandUserPath(rawPath);
        virtualMode = "";
        archiverActive = false;
        isDeepSearch = false;
        loadError = "";
        selectedPaths = [];
        lastSelectedIdx = -1;
        if (isPicker && pickerDirectory) nameField.text = "";
        if (history[historyIdx] !== target) {
            const next = history.slice(0, historyIdx + 1);
            next.push(target);
            history = next;
            historyIdx = next.length - 1;
        }
        currentPath = target;
        currentItems = [];
        if (!isPicker) FileService.lastPath = target;
        syncActiveTab();
        refreshCurrent();
    }

    function resetNavigation(startPath, initialName) {
        const target = expandUserPath(startPath || FileService.homeDir);
        virtualMode = "";
        archiverActive = false;
        isDeepSearch = false;
        loadError = "";
        selectedPaths = [];
        lastSelectedIdx = -1;
        if (isPicker && pickerDirectory) nameField.text = "";
        searchQuery = "";
        searchField.text = "";
        nameField.text = initialName || "";
        history = [target];
        historyIdx = 0;
        currentPath = target;
        currentItems = [];
        refreshCurrent();
    }

    function setSort(by, asc) {
        sortBy = by;
        sortAsc = asc;
        FileService.setSortPref(by, asc);
    }

    function toggleSortColumn(by) {
        if (sortBy === by) {
            setSort(by, !sortAsc);
        } else {
            setSort(by, by === "name" || by === "type");
        }
    }

    function handleItemClick(item, index, mouse) {
        if (!item) return;
        root.forceActiveFocus();
        const allowMulti = !isPicker || pickerMultiple;
        const mod = mouse ? mouse.modifiers : 0;
        const isCtrl = (mod & Qt.ControlModifier) !== 0;
        const isShift = (mod & Qt.ShiftModifier) !== 0;

        if (allowMulti && isShift && lastSelectedIdx >= 0 && lastSelectedIdx < visibleItems.length) {
            const lo = Math.min(lastSelectedIdx, index);
            const hi = Math.max(lastSelectedIdx, index);
            const next = isCtrl ? selectedPaths.slice() : [];
            for (let i = lo; i <= hi; ++i) {
                const p = visibleItems[i].path;
                if (next.indexOf(p) === -1) next.push(p);
            }
            selectedPaths = next;
        } else if (allowMulti && isCtrl) {
            const next = selectedPaths.slice();
            const idx = next.indexOf(item.path);
            if (idx === -1) next.push(item.path);
            else next.splice(idx, 1);
            lastSelectedIdx = index;
            selectedPaths = next;
        } else {
            lastSelectedIdx = index;
            selectedPaths = [item.path];
        }

        if (isPicker) {
            const selItems = getSelectedItems();
            if (pickerDirectory) {
                nameField.text = (item.type === "folder") ? item.name : "";
            } else if (selItems.length > 1) {
                const fileCount = selItems.filter(it => it.type !== "folder").length;
                nameField.text = fileCount > 1 ? (fileCount + " files selected") : (selItems[0].type !== "folder" ? selItems[0].name : "");
            } else if (item.type !== "folder") {
                nameField.text = item.name;
            }
        }
    }

    function handleItemRightClick(srcItem, mouse, item, index) {
        if (!item) return;
        if (!isPathSelected(item.path)) {
            lastSelectedIdx = index;
            selectedPaths = [item.path];
            if (isPicker && (pickerDirectory || item.type !== "folder")) {
                nameField.text = item.name;
            }
        }
        openContextMenu(srcItem, mouse, item);
    }

    function handleItemDoubleClick(item) {
        if (!item) return;
        if (item.type === "folder") {
            navigateTo(item.path);
            return;
        }
        if (isPicker) {
            selectedPaths = [item.path];
            nameField.text = item.name;
            submitPicker();
        } else {
            openItem(item);
        }
    }

    function submitPicker() {
        let paths = [];
        if (pickerDirectory) {
            const sel = getSelectedItems().filter(it => it.type === "folder");
            if (sel.length > 0) paths = sel.map(it => it.path);
            else paths = [currentPath];
        } else if (pickerMultiple && selectedPaths.length > 0) {
            const selFiles = getSelectedItems().filter(it => it.type !== "folder");
            if (selFiles.length > 0) paths = selFiles.map(it => it.path);
            else {
                const primary = getPrimarySelectedItem();
                if (primary && primary.type === "folder") {
                    navigateTo(primary.path);
                    return;
                }
            }
        }

        if (paths.length === 0) {
            const f = nameField.text.trim();
            if (f === "") return;
            const full = f.startsWith("/")
                ? f
                : ((currentPath === "/" ? "" : currentPath) + "/" + f);
            paths = [full];
        }

        if (pickerActionMode === "download" && paths.length === 1) {
            const targetName = paths[0].split("/").pop();
            const exists = (currentItems || []).some(it => it.name === targetName && it.type !== "folder");
            if (exists && !confirmOpen) {
                confirmMode = "overwrite";
                confirmPaths = paths;
                confirmTitle = "Replace Existing File?";
                confirmLabel = "\"" + targetName + "\" already exists in " + displayPath(currentPath) + ".";
                confirmSub = "Saving will overwrite its current contents.";
                confirmOpen = true;
                confirmOverlay.forceActiveFocus();
                return;
            }
        }
        pickerSubmitted(paths);
    }

    function goBack() {
        if (historyIdx > 0) {
            historyIdx--;
            virtualMode = "";
            archiverActive = false;
            isDeepSearch = false;
            selectedPaths = [];
            lastSelectedIdx = -1;
            currentPath = history[historyIdx];
            currentItems = [];
            if (!isPicker) FileService.lastPath = currentPath;
            syncActiveTab();
            refreshCurrent();
        }
    }

    function goForward() {
        if (historyIdx < history.length - 1) {
            historyIdx++;
            virtualMode = "";
            archiverActive = false;
            isDeepSearch = false;
            selectedPaths = [];
            lastSelectedIdx = -1;
            currentPath = history[historyIdx];
            currentItems = [];
            if (!isPicker) FileService.lastPath = currentPath;
            syncActiveTab();
            refreshCurrent();
        }
    }

    function goUp() {
        if (archiverActive) {
            archiverActive = false;
            return;
        }
        if (virtualMode !== "") {
            navigateTo(currentPath);
            return;
        }
        if (currentPath === "/" || !currentPath) return;
        const idx = currentPath.lastIndexOf("/");
        const parent = idx <= 0 ? "/" : currentPath.slice(0, idx);
        navigateTo(parent);
    }

    function startTransfer(label, sub, destDir, totalBytes) {
        transferLabel = label;
        transferSub = sub;
        transferDestDir = destDir || "";
        transferTotalBytes = totalBytes > 0 ? totalBytes : 0;
        transferPct = 12;
        transferActive = true;
        if (destDir && totalBytes > 0) {
            FileService.dirSize(destDir, (baseBytes) => {
                if (!root) return;
                transferBaselineBytes = baseBytes;
                transferPollTimer.restart();
            });
        } else {
            transferPollTimer.restart();
        }
    }

    function finishTransfer(finalSub) {
        transferPollTimer.stop();
        transferPct = 100;
        if (finalSub) transferSub = finalSub;
        transferHideTimer.restart();
    }

    Timer {
        id: transferPollTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (root.transferTotalBytes > 0 && root.transferDestDir !== "") {
                FileService.dirSize(root.transferDestDir, (cur) => {
                    if (!root) return;
                    const delta = Math.max(0, cur - root.transferBaselineBytes);
                    const pct = Math.min(96, Math.max(15, Math.round((delta / root.transferTotalBytes) * 100)));
                    root.transferPct = pct;
                });
            } else {
                root.transferPct = Math.min(92, root.transferPct + 12);
            }
        }
    }

    Timer {
        id: transferHideTimer
        interval: 1500
        onTriggered: root.transferActive = false
    }

    function openItem(item) {
        if (!item) return;
        if (item.type === "folder") {
            navigateTo(item.path);
        } else if (item.type === "archive") {
            openArchiveInspector(item);
        } else if (item.type === "image" || item.type === "video") {
            openMediaViewer(item);
        } else {
            FileService.openFile(item.path);
        }
    }

    function openMediaViewer(item) {
        if (!item || (item.type !== "image" && item.type !== "video")) return;
        const siblings = (visibleItems || []).filter(it => it && (it.type === "image" || it.type === "video"));
        let idx = siblings.findIndex(it => it.path === item.path);
        if (idx < 0) {
            viewerItems = [item];
            idx = 0;
        } else {
            viewerItems = siblings;
        }
        viewerStepDir = 0;
        viewerIndex = idx;
        viewerOpen = true;
    }

    function closeMediaViewer() {
        viewerOpen = false;
        root.forceActiveFocus();
    }

    function stepMediaViewer(delta) {
        const len = viewerItems ? viewerItems.length : 0;
        if (len <= 1) return;
        viewerStepDir = delta > 0 ? 1 : -1;
        viewerIndex = ((viewerIndex + delta) % len + len) % len;
        const cur = viewerItems[viewerIndex];
        if (cur && cur.path) selectedPaths = [cur.path];
    }

    function openArchiveInspector(item) {
        const seq = ++_archiveSeq;
        archiverArchivePath = item.path;
        archiverArchiveName = item.name;
        archiverError = "";
        archiverEntries = [];
        archiverLoading = true;
        archiverActive = true;
        selectedPaths = [];
        lastSelectedIdx = -1;
        FileService.inspectArchive(item.path, (ok, entries, err) => {
            if (!root || seq !== root._archiveSeq) return;
            archiverLoading = false;
            if (!ok) {
                archiverError = err || "Unable to list archive (may be encrypted)";
                return;
            }
            archiverEntries = entries;
        });
    }

    function beginExtract(archivePath, archiveName, password) {
        startTransfer("Extracting " + archiveName, "To " + displayPath(currentPath), "", 0);
        FileService.extractArchive(archivePath, currentPath, password || "", (ok, outDir, errText, needsPwd) => {
            if (!root) return;
            if (!ok && needsPwd) {
                transferPollTimer.stop();
                transferActive = false;
                passwordTargetPath = archivePath;
                passwordTargetName = archiveName;
                passwordError = (password && password.length > 0) ? "Incorrect password" : "";
                passwordField.text = "";
                passwordOpen = true;
                passwordField.forceActiveFocus();
                if (password && password.length > 0) pwdShake.restart();
                return;
            }
            if (!ok) {
                finishTransfer("Failed: " + (errText || "extract error"));
                statusMessage = errText || "Extract failed";
                return;
            }
            passwordOpen = false;
            archiverActive = false;
            finishTransfer("Extracted to " + outDir.split("/").pop());
            refreshCurrent();
        });
    }

    function submitPassword() {
        const pwd = passwordField.text;
        if (pwd.length === 0) {
            passwordError = "Password cannot be empty";
            pwdShake.restart();
            return;
        }
        beginExtract(passwordTargetPath, passwordTargetName, pwd);
    }

    function performPaste(destOverride) {
        const paths = (FileService.clipboardPaths || []).slice();
        if (paths.length === 0 || (virtualMode !== "" && !destOverride)) return;
        const isCut = FileService.clipboardMode === "cut";
        const dest = destOverride || currentPath;
        FileService.measureSize(paths, (totalBytes) => {
            if (!root) return;
            startTransfer((isCut ? "Moving " : "Copying ") + paths.length + " item(s)", "To " + displayPath(dest), dest, totalBytes);
            const doneCb = (ok, err) => {
                if (!root) return;
                if (!ok) {
                    finishTransfer("Error: " + (err || "operation failed"));
                    statusMessage = err || "Paste failed";
                } else {
                    if (isCut) FileService.clearClipboard();
                    finishTransfer("Completed in " + displayPath(dest));
                    refreshCurrent();
                }
            };
            if (isCut) FileService.moveItems(paths, dest, doneCb);
            else FileService.copyItems(paths, dest, doneCb);
        });
    }

    function openInputModal(mode, title, initialValue, targetPath) {
        inputModalMode = mode;
        inputModalTitle = title;
        inputModalValue = initialValue || "";
        inputModalTargetPath = targetPath || "";
        inputModalError = "";
        inputModalOpen = true;
        modalTextField.text = inputModalValue;
        Qt.callLater(() => {
            if (!modalTextField) return;
            modalTextField.forceActiveFocus();
            if (mode === "rename" && inputModalValue.indexOf(".") > 0) {
                const dotIdx = inputModalValue.lastIndexOf(".");
                modalTextField.select(0, dotIdx);
            } else {
                modalTextField.selectAll();
            }
        });
    }

    function submitInputModal() {
        const val = modalTextField.text.trim();
        if (!val || val === "." || val === ".." || val.indexOf("/") !== -1) {
            inputModalError = val.indexOf("/") !== -1 ? "Name cannot contain '/'" : "Please enter a valid name";
            inputShake.restart();
            return;
        }
        inputModalError = "";
        if (inputModalMode === "mkdir") {
            FileService.createFolder(currentPath, val, (ok, err) => {
                if (!root) return;
                if (!ok) {
                    inputModalError = err || "Failed to create folder";
                    inputShake.restart();
                    return;
                }
                inputModalOpen = false;
                root.forceActiveFocus();
                refreshCurrent();
            });
        } else if (inputModalMode === "mkfile") {
            FileService.createFile(currentPath, val, (ok, err) => {
                if (!root) return;
                if (!ok) {
                    inputModalError = err || "Failed to create file";
                    inputShake.restart();
                    return;
                }
                inputModalOpen = false;
                root.forceActiveFocus();
                refreshCurrent();
            });
        } else if (inputModalMode === "rename") {
            FileService.renameItem(inputModalTargetPath, val, (ok, err) => {
                if (!root) return;
                if (!ok) {
                    inputModalError = err || "Rename failed";
                    inputShake.restart();
                    return;
                }
                inputModalOpen = false;
                root.forceActiveFocus();
                refreshCurrent();
            });
        }
    }

    function requestDelete(paths, permanent) {
        const list = (paths || []).filter(Boolean);
        if (list.length === 0) return;
        confirmPaths = list;
        confirmMode = permanent ? "permanent" : "trash";
        confirmTitle = permanent ? "Delete Permanently" : "Move to Trash";
        if (list.length === 1) {
            const name = list[0].split("/").pop();
            confirmLabel = (permanent ? "Permanently delete \"" : "Move \"") + name + (permanent ? "\"?" : "\" to Trash?");
        } else {
            confirmLabel = (permanent ? "Permanently delete " : "Move ") + list.length + " selected items" + (permanent ? "?" : " to Trash?");
        }
        confirmSub = permanent ? "This action cannot be undone." : "You can restore items later from Trash.";
        confirmOpen = true;
        confirmOverlay.forceActiveFocus();
    }

    function requestEmptyTrash() {
        confirmPaths = [];
        confirmMode = "empty_trash";
        confirmTitle = "Empty Trash";
        confirmLabel = "Permanently delete all items in Trash?";
        confirmSub = "This action cannot be undone.";
        confirmOpen = true;
        confirmOverlay.forceActiveFocus();
    }

    function executeConfirm() {
        const mode = confirmMode;
        const paths = confirmPaths.slice();
        confirmOpen = false;
        root.forceActiveFocus();

        if (mode === "overwrite") {
            pickerSubmitted(paths);
            return;
        }
        if (mode === "empty_trash") {
            FileService.emptyTrash((ok, err) => {
                if (!root) return;
                if (!ok) statusMessage = err || "Failed to empty Trash";
                else statusMessage = "Trash emptied";
                refreshCurrent();
            });
            return;
        }
        const permanent = (mode === "permanent");
        FileService.deleteItems(paths, permanent, (ok, err) => {
            if (!root) return;
            if (!ok) statusMessage = err || "Delete failed";
            selectedPaths = [];
            lastSelectedIdx = -1;
            refreshCurrent();
        });
    }

    function restoreItems(paths) {
        const list = (paths || []).filter(Boolean);
        if (list.length === 0) return;
        FileService.restoreFromTrash(list, (ok, err) => {
            if (!root) return;
            if (!ok) statusMessage = err || "Restore failed";
            else statusMessage = "Restored " + list.length + (list.length === 1 ? " item" : " items");
            selectedPaths = [];
            lastSelectedIdx = -1;
            refreshCurrent();
        });
    }

    function compressItems(items) {
        const list = (items || []).filter(it => it && it.path);
        if (list.length === 0) return;
        const paths = list.map(it => it.path);
        const zipName = list.length === 1 ? (list[0].name + ".zip") : "Archive.zip";
        startTransfer("Compressing " + list.length + (list.length === 1 ? " item" : " items"), "Creating " + zipName, "", 0);
        FileService.createArchive(paths, currentPath, zipName, (ok, err) => {
            if (!root) return;
            if (!ok) {
                finishTransfer("Failed: " + (err || "zip error"));
                statusMessage = err || "Compress failed";
            } else {
                finishTransfer("Created " + zipName);
                refreshCurrent();
            }
        });
    }

    function openProperties(item) {
        if (!item || !item.path) return;
        propsName = item.name || displayPath(item.path);
        propsPath = item.path;
        propsData = null;
        propsOpen = true;
        propsOverlay.forceActiveFocus();
        FileService.getProperties(item.path, (ok, data) => {
            if (root && ok) propsData = data;
        });
    }

    function openSortMenu(btnItem) {
        const pt = btnItem.mapToItem(root, 0, btnItem.height + 4);
        ctxMenu.menuWidth = 186;
        ctxMenu.openAt(pt.x, pt.y, [
            { text: "Sort by Name", checked: sortBy === "name", action: () => setSort("name", sortAsc) },
            { text: "Sort by Modified", checked: sortBy === "mtime", action: () => setSort("mtime", sortAsc) },
            { text: "Sort by Size", checked: sortBy === "size", action: () => setSort("size", sortAsc) },
            { text: "Sort by Type", checked: sortBy === "type", action: () => setSort("type", sortAsc) },
            { separator: true },
            { text: "Ascending", checked: sortAsc === true, action: () => setSort(sortBy, true) },
            { text: "Descending", checked: sortAsc === false, action: () => setSort(sortBy, false) }
        ]);
    }

    function openFilterMenu(btnItem) {
        const pt = btnItem.mapToItem(root, 0, btnItem.height + 4);
        const opts = [];
        if (pickerFilters && pickerFilters.length > 0) {
            for (let i = 0; i < pickerFilters.length; ++i) {
                const idx = i;
                opts.push({
                    text: pickerFilters[i].label,
                    checked: filterType === "portal" && activePortalFilterIdx === idx,
                    action: () => {
                        activePortalFilterIdx = idx;
                        filterType = "portal";
                    }
                });
            }
            opts.push({ separator: true });
        }
        const presets = [
            { key: "all", label: "All Files (*.*)" },
            { key: "image", label: "Images (*.png, *.jpg, *.webp)" },
            { key: "document", label: "Documents (*.pdf, *.txt, *.md)" },
            { key: "code", label: "Config & Code (*.qml, *.py, *.json)" },
            { key: "archive", label: "Archives (*.pak, *.zip, *.tar, *.7z)" },
            { key: "media", label: "Audio & Video" }
        ];
        for (let i = 0; i < presets.length; ++i) {
            const p = presets[i];
            opts.push({
                text: p.label,
                checked: filterType === p.key,
                action: () => {
                    activePortalFilterIdx = -1;
                    filterType = p.key;
                }
            });
        }
        ctxMenu.menuWidth = Math.max(220, btnItem.width);
        root.filterMenuOpen = true;
        ctxMenu.openAt(pt.x, pt.y, opts);
    }

    function openContextMenu(srcItem, mouse, clickedItem) {
        const pt = srcItem.mapToItem(root, mouse.x, mouse.y);
        const selItems = getSelectedItems();
        const sel = clickedItem || (selItems.length > 0 ? selItems[0] : null);
        const selCount = selItems.length;
        const clipCount = (FileService.clipboardPaths || []).length;

        ctxMenu.menuWidth = 252;

        // 1. Picker Context Menu (Safe subset)
        if (isPicker) {
            if (sel) {
                const isDir = sel.type === "folder";
                ctxMenu.openAt(pt.x, pt.y, [
                    { text: isDir ? "Open Folder" : "Select File", iconName: isDir ? "external-link" : "check", action: () => isDir ? navigateTo(sel.path) : handleItemDoubleClick(sel) },
                    { text: "Copy Path", iconName: "link", action: () => { FileService.copyToClipboard(sel.path); statusMessage = "Path copied"; } },
                    { separator: true },
                    { text: FileService.isStarred(sel.path) ? "Unstar" : "Star", iconName: "star", action: () => { FileService.toggleStar(sel.path); if (virtualMode === "starred") loadStarred(); } },
                    { text: "Properties", iconName: "info", action: () => openProperties(sel) }
                ]);
            } else {
                const menu = [];
                if (virtualMode === "") {
                    menu.push({ text: "New Folder", iconName: "folder-plus", shortcut: "Ctrl+Shift+N", action: () => openInputModal("mkdir", "New Folder", "New Folder", "") });
                    menu.push({ separator: true });
                }
                menu.push({ text: showHidden ? "Hide Hidden Files" : "Show Hidden Files", iconName: showHidden ? "eye-off" : "eye", checked: showHidden, action: () => { showHidden = !showHidden; FileService.setHiddenPref(showHidden); refreshCurrent(); } });
                menu.push({ text: "Refresh", iconName: "refresh", shortcut: "F5", action: () => refreshCurrent() });
                if (virtualMode === "") {
                    menu.push({ separator: true });
                    menu.push({ text: "Open in Terminal", iconName: "terminal", action: () => FileService.openTerminal(currentPath) });
                    menu.push({ text: "Folder Properties", iconName: "info", action: () => openProperties({ name: displayPath(currentPath), path: currentPath }) });
                }
                ctxMenu.openAt(pt.x, pt.y, menu);
            }
            return;
        }

        // 2. Trash Context Menu
        if (isInTrash) {
            if (sel) {
                const targetPaths = selCount > 1 ? selItems.map(it => it.path) : [sel.path];
                ctxMenu.openAt(pt.x, pt.y, [
                    { text: targetPaths.length > 1 ? ("Restore (" + targetPaths.length + ")") : "Restore", iconName: "restore", action: () => restoreItems(targetPaths) },
                    { text: "Delete Permanently", iconName: "close", danger: true, shortcut: "Shift+Del", action: () => requestDelete(targetPaths, true) },
                    { separator: true },
                    { text: "Properties", iconName: "info", enabled: selCount <= 1, action: () => openProperties(sel) }
                ]);
            } else {
                ctxMenu.openAt(pt.x, pt.y, [
                    { text: "Empty Trash", iconName: "trash", danger: true, enabled: (currentItems || []).length > 0, action: () => requestEmptyTrash() },
                    { text: "Refresh", iconName: "refresh", shortcut: "F5", action: () => refreshCurrent() }
                ]);
            }
            return;
        }

        // 3. Manager Mode — Item(s) Selected
        if (sel) {
            const targetItems = selCount > 1 ? selItems : [sel];
            const targetPaths = targetItems.map(it => it.path);
            const single = targetItems.length === 1;
            const menu = [];

            if (single) {
                const isMedia = (sel.type === "image" || sel.type === "video");
                menu.push({
                    text: sel.type === "archive" ? "Inspect Archive" : (isMedia ? "View" : "Open"),
                    iconName: isMedia ? "eye" : "external-link",
                    shortcut: "Enter",
                    action: () => openItem(sel)
                });
                if (isMedia) {
                    menu.push({ text: "Open Externally", iconName: "external-link", action: () => FileService.openFile(sel.path) });
                }
                if (sel.type === "folder") {
                    menu.push({ text: "Open in New Tab", iconName: "plus", action: () => openTab(sel.path, "", true) });
                    menu.push({ text: "Open in Terminal", iconName: "terminal", action: () => FileService.openTerminal(sel.path) });
                }
                menu.push({ separator: true });
            }

            menu.push({ text: single ? "Copy" : ("Copy (" + targetPaths.length + ")"), iconName: "copy", shortcut: "Ctrl+C", action: () => { FileService.setClipboard(targetPaths, "copy"); statusMessage = "Copied " + targetPaths.length + (targetPaths.length === 1 ? " item" : " items"); } });
            menu.push({ text: single ? "Cut" : ("Cut (" + targetPaths.length + ")"), iconName: "scissors", shortcut: "Ctrl+X", action: () => { FileService.setClipboard(targetPaths, "cut"); statusMessage = "Cut " + targetPaths.length + (targetPaths.length === 1 ? " item" : " items"); } });
            if (single && sel.type === "folder" && clipCount > 0) {
                menu.push({ text: "Paste into Folder (" + clipCount + ")", iconName: "clipboard", action: () => performPaste(sel.path) });
            }
            if (single) {
                menu.push({ text: "Copy Path", iconName: "link", action: () => { FileService.copyToClipboard(sel.path); statusMessage = "Path copied to clipboard"; } });
            }
            menu.push({ separator: true });

            if (single && virtualMode === "") {
                menu.push({ text: "Rename", iconName: "edit", shortcut: "F2", action: () => openInputModal("rename", "Rename Item", sel.name, sel.path) });
            }
            if (single) {
                menu.push({ text: FileService.isStarred(sel.path) ? "Unstar" : "Star", iconName: "star", action: () => { FileService.toggleStar(sel.path); if (virtualMode === "starred") loadStarred(); } });
            }
            if (virtualMode === "") {
                menu.push({ text: "Compress (.zip)", iconName: "archive", action: () => compressItems(targetItems) });
                if (single && sel.type === "archive") {
                    menu.push({ text: "Extract Here", iconName: "extract", action: () => beginExtract(sel.path, sel.name, "") });
                    if (sel.name.toLowerCase().endsWith(".pak")) {
                        menu.push({ text: "Restore Backup (.pak)...", iconName: "restore", action: () => { if (root.shellState) root.shellState.openBackupRestorePak(sel.path); } });
                    }
                }
            }
            menu.push({ separator: true });
            menu.push({ text: "Move to Trash", iconName: "trash", shortcut: "Del", action: () => requestDelete(targetPaths, false) });
            menu.push({ text: "Delete Permanently", iconName: "close", danger: true, shortcut: "Shift+Del", action: () => requestDelete(targetPaths, true) });
            if (single) {
                menu.push({ separator: true });
                menu.push({ text: "Properties", iconName: "info", action: () => openProperties(sel) });
            }
            ctxMenu.openAt(pt.x, pt.y, menu);
            return;
        }

        // 4. Manager Mode — Empty Space
        const emptyMenu = [];
        if (virtualMode === "") {
            emptyMenu.push({ text: "New Folder", iconName: "folder-plus", shortcut: "Ctrl+Shift+N", action: () => openInputModal("mkdir", "New Folder", "New Folder", "") });
            emptyMenu.push({ text: "New File", iconName: "file-plus", shortcut: "Ctrl+N", action: () => openInputModal("mkfile", "New File", "untitled.txt", "") });
            emptyMenu.push({ text: "Paste (" + clipCount + ")", iconName: "clipboard", shortcut: "Ctrl+V", enabled: clipCount > 0, action: () => performPaste() });
            emptyMenu.push({ separator: true });
        }
        emptyMenu.push({ text: showHidden ? "Hide Hidden Files" : "Show Hidden Files", iconName: showHidden ? "eye-off" : "eye", shortcut: "Ctrl+H", checked: showHidden, action: () => { showHidden = !showHidden; FileService.setHiddenPref(showHidden); refreshCurrent(); } });
        emptyMenu.push({ text: "Refresh", iconName: "refresh", shortcut: "F5", action: () => refreshCurrent() });
        if (virtualMode === "") {
            emptyMenu.push({ separator: true });
            emptyMenu.push({ text: "Open in Terminal", iconName: "terminal", action: () => FileService.openTerminal(currentPath) });
            emptyMenu.push({ text: "Folder Properties", iconName: "info", action: () => openProperties({ name: displayPath(currentPath), path: currentPath }) });
        }
        ctxMenu.openAt(pt.x, pt.y, emptyMenu);
    }

    function applyServicePrefs(refetchIfHiddenChanged) {
        const prevHidden = showHidden;
        isListView = FileService.prefListView;
        showHidden = FileService.prefShowHidden;
        sortBy = FileService.prefSortBy;
        sortAsc = FileService.prefSortAsc;
        if (refetchIfHiddenChanged && prevHidden !== showHidden) {
            refreshCurrent();
        }
    }

    Connections {
        target: FileService
        function onStateLoaded() {
            root.applyServicePrefs(!root.isPicker || root.virtualMode === "");
            if (root.virtualMode === "starred") root.loadStarred();
        }
    }

    Component.onCompleted: {
        libraryOpen = !isPicker;
        applyServicePrefs(false);
        if (!isPicker) {
            initTabs();
        }
    }

    function buildDragMime(itemPath) {
        const paths = root.isPathSelected(itemPath) && root.selectedPaths.length > 0
            ? root.selectedPaths
            : [itemPath];
        const uris = [];
        for (let i = 0; i < paths.length; ++i) {
            const p = String(paths[i] || "");
            if (!p) continue;
            const encoded = p.split("/").map(seg => encodeURIComponent(seg)).join("/");
            uris.push("file://" + encoded);
        }
        return uris.length > 0 ? { "text/uri-list": uris.join("\r\n") + "\r\n" } : ({});
    }

    // Layered Keyboard Shortcuts
    Keys.onPressed: (event) => {
        if (ctxMenu.isOpen) {
            if (event.key === Qt.Key_Escape) {
                ctxMenu.close();
                event.accepted = true;
            }
            return;
        }
        if (anyModalOpen) {
            if (event.key === Qt.Key_Escape) {
                passwordOpen = false;
                inputModalOpen = false;
                confirmOpen = false;
                propsOpen = false;
                viewerOpen = false;
                root.forceActiveFocus();
                event.accepted = true;
            }
            return;
        }

        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;

        if (event.key === Qt.Key_Escape) {
            if (pathEditing) {
                pathEditing = false;
                event.accepted = true;
                return;
            }
            if (searchField.text !== "" || isDeepSearch) {
                searchField.text = "";
                searchQuery = "";
                if (isDeepSearch) refreshCurrent();
                event.accepted = true;
                return;
            }
            if (archiverActive) {
                archiverActive = false;
                event.accepted = true;
                return;
            }
            if (selectedPaths.length > 0) {
                selectedPaths = [];
                lastSelectedIdx = -1;
                event.accepted = true;
                return;
            }
            // Let outer shell handle final Escape (collapse Island or cancel detached)
            event.accepted = false;
            return;
        }

        if (searchField.activeFocus || pathField.activeFocus || nameField.activeFocus) {
            return;
        }

        if (!isPicker && ctrl && event.key === Qt.Key_T) {
            openTab(currentPath, "", true);
            event.accepted = true;
            return;
        } else if (!isPicker && ctrl && event.key === Qt.Key_W) {
            if (tabsModel.count > 1) closeTab(activeTabIndex);
            event.accepted = true;
            return;
        } else if (!isPicker && ctrl && (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown) && !shift) {
            nextTab();
            event.accepted = true;
            return;
        } else if (!isPicker && ctrl && (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp || (shift && event.key === Qt.Key_Tab))) {
            prevTab();
            event.accepted = true;
            return;
        } else if (!isPicker && (ctrl || alt) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            const targetIdx = (event.key === Qt.Key_9) ? (tabsModel.count - 1) : (event.key - Qt.Key_1);
            if (targetIdx >= 0 && targetIdx < tabsModel.count) switchTab(targetIdx);
            event.accepted = true;
            return;
        }

        if (alt && event.key === Qt.Key_Left) {
            goBack();
            event.accepted = true;
        } else if (alt && event.key === Qt.Key_Right) {
            goForward();
            event.accepted = true;
        } else if ((alt && event.key === Qt.Key_Up) || event.key === Qt.Key_Backspace) {
            goUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_F5 || (ctrl && event.key === Qt.Key_R)) {
            refreshCurrent();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_L && virtualMode === "" && !archiverActive) {
            pathField.text = currentPath;
            pathEditing = true;
            pathField.forceActiveFocus();
            pathField.selectAll();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_F) {
            searchField.forceActiveFocus();
            searchField.selectAll();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_H && !archiverActive) {
            showHidden = !showHidden;
            FileService.setHiddenPref(showHidden);
            refreshCurrent();
            event.accepted = true;
        } else if (ctrl && shift && event.key === Qt.Key_N && virtualMode === "" && !isInTrash && !archiverActive) {
            openInputModal("mkdir", "New Folder", "New Folder", "");
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_N && !isPicker && virtualMode === "" && !isInTrash && !archiverActive) {
            openInputModal("mkfile", "New File", "untitled.txt", "");
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_A && !archiverActive && (!isPicker || pickerMultiple)) {
            const all = (visibleItems || []).map(it => it.path);
            selectedPaths = all;
            lastSelectedIdx = all.length - 1;
            event.accepted = true;
        } else if (!isPicker && !isInTrash && ctrl && event.key === Qt.Key_C && selectedPaths.length > 0) {
            FileService.setClipboard(selectedPaths, "copy");
            statusMessage = "Copied " + selectedPaths.length + (selectedPaths.length === 1 ? " item" : " items");
            event.accepted = true;
        } else if (!isPicker && !isInTrash && ctrl && event.key === Qt.Key_X && selectedPaths.length > 0) {
            FileService.setClipboard(selectedPaths, "cut");
            statusMessage = "Cut " + selectedPaths.length + (selectedPaths.length === 1 ? " item" : " items");
            event.accepted = true;
        } else if (!isPicker && !isInTrash && ctrl && event.key === Qt.Key_V && FileService.clipboardPaths.length > 0 && virtualMode === "") {
            performPaste();
            event.accepted = true;
        } else if (!isPicker && !isInTrash && event.key === Qt.Key_F2 && selectedPaths.length === 1 && virtualMode === "") {
            const p = getPrimarySelectedItem();
            if (p) openInputModal("rename", "Rename Item", p.name, p.path);
            event.accepted = true;
        } else if (!isPicker && event.key === Qt.Key_Delete && selectedPaths.length > 0) {
            requestDelete(selectedPaths, shift || isInTrash);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const p = getPrimarySelectedItem();
            if (p) {
                handleItemDoubleClick(p);
                event.accepted = true;
            } else if (isPicker && canPickerSubmit) {
                submitPicker();
                event.accepted = true;
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar (224px)
        Rectangle {
            Layout.preferredWidth: 224
            Layout.fillHeight: true
            color: Theme.pillBg
            bottomLeftRadius: root._appBottomRadius
            topLeftRadius: root._appTopRadius

            ThemeGradientFill {
                anchors.fill: parent
                enabled: Theme.effectiveShellGradient
                color1: Theme.pillBg
                colorMid: Theme.pillBgMid
                color2: Theme.pillBg2
                cornerRadius: 0
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // App Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: root.isPicker ? "download" : "folder"
                            iconSize: 16
                            color: Theme.accent
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.isPicker ? root.pickerTitle : "Files"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.isPicker ? root.pickerSubtitle : "File Manager"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                }

                // Search Input
                Rectangle {
                    Layout.fillWidth: true
                    height: 32; radius: 9
                    color: searchField.activeFocus ? Theme.surfaceRaised : Theme.cardBg
                    border.width: 1
                    border.color: searchField.activeFocus ? Theme.accent : Theme.borderSubtle
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9; anchors.rightMargin: 7; spacing: 6

                        SvgIcon {
                            sourceName: "search"
                            iconSize: 13
                            color: searchField.activeFocus ? Theme.accent : Theme.textMuted
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        AnimatedTextInput {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            textColor: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: {
                                if (root._switchingTab) return;
                                root.searchQuery = text;
                                root.syncActiveTab();
                                if (text.trim() === "" && root.isDeepSearch) {
                                    root.refreshCurrent();
                                }
                            }
                            Keys.onReturnPressed: root.runDeepSearch()
                            Keys.onEscapePressed: (event) => {
                                if (text !== "" || root.isDeepSearch) {
                                    text = "";
                                    root.searchQuery = "";
                                    if (root.isDeepSearch) root.refreshCurrent();
                                }
                                root.forceActiveFocus();
                                event.accepted = true;
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Search (Enter = deep)"
                                color: Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                opacity: (searchField.text === "" && searchField.preeditText === "") ? 1.0 : 0.0
                                visible: opacity > 0.01
                                elide: Text.ElideRight
                                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                        }

                        Rectangle {
                            opacity: root.isDeepSearch ? 1.0 : 0.0
                            visible: opacity > 0.01
                            width: root.isDeepSearch ? (deepLbl.implicitWidth + 8) : 0
                            height: 17; radius: 5
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            clip: true
                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Text {
                                id: deepLbl
                                anchors.centerIn: parent
                                text: "Deep"
                                color: Theme.accent
                                font.family: Theme.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            opacity: searchField.text !== "" ? 1.0 : 0.0
                            visible: opacity > 0.01
                            width: searchField.text !== "" ? 18 : 0
                            height: 18; radius: 6
                            color: clrSearchMouse.containsMouse ? Theme.cardHover : "transparent"
                            scale: clrSearchMouse.pressed ? 0.9 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            SvgIcon { anchors.centerIn: parent; sourceName: "close"; iconSize: 10; color: Theme.textSub }
                            MouseArea {
                                id: clrSearchMouse
                                anchors.fill: parent
                                enabled: searchField.text !== ""
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchField.text = "";
                                    root.searchQuery = "";
                                    if (root.isDeepSearch) root.refreshCurrent();
                                    root.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Tree Navigation
                Flickable {
                    id: sidebarFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: treeCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        policy: sidebarFlick.contentHeight > sidebarFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22)
                        }
                    }

                    ColumnLayout {
                        id: treeCol
                        width: parent.width
                        spacing: 2

                        // Places Tree Group
                        Rectangle {
                            Layout.fillWidth: true; height: 28; radius: 8
                            color: placesHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            scale: placesHeadMouse.pressed ? 0.98 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                SvgIcon { sourceName: "folder"; iconSize: 14; color: Theme.textSub }
                                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Places"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 13
                                    color: Theme.textMuted
                                    rotation: root.placesOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: placesHeadMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.placesOpen = !root.placesOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.placesOpen ? placesSubCol.implicitHeight : 0
                            opacity: root.placesOpen ? 1.0 : 0.0
                            visible: Layout.preferredHeight > 1 || opacity > 0.01
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160 } }

                            Rectangle {
                                width: 1; x: 16; y: 2; height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: placesSubCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 22; spacing: 2

                                Repeater {
                                    model: FileService.resolvedPlaces
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: root.virtualMode === "" && root.currentPath === modelData.path
                                        visible: !root.isPicker || modelData.key !== "Trash"
                                        Layout.fillWidth: true; height: 26; radius: 7
                                        color: isActive ? Theme.cardHover : (pMouse.containsMouse ? Theme.cardBg : "transparent")
                                        scale: pMouse.pressed ? 0.98 : 1.0
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                        Rectangle {
                                            width: 3; height: isActive ? 15 : 6; radius: 2
                                            anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 8; spacing: 7
                                            SvgIcon {
                                                sourceName: modelData.icon || "folder"
                                                iconSize: 13
                                                color: isActive ? Theme.accent : Theme.textMuted
                                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans; font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        MouseArea {
                                            id: pMouse
                                            anchors.fill: parent; enabled: root.placesOpen; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: (mouse) => {
                                                if (!root.isPicker && mouse.button === Qt.MiddleButton) root.openTab(modelData.path, "", true);
                                                else root.navigateTo(modelData.path);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Library Tree Group (Available in both Files & Picker)
                        Rectangle {
                            Layout.fillWidth: true; height: 28; radius: 8
                            color: libHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            scale: libHeadMouse.pressed ? 0.98 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                SvgIcon { sourceName: "clock"; iconSize: 14; color: Theme.textSub }
                                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Library"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 13
                                    color: Theme.textMuted
                                    rotation: root.libraryOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: libHeadMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.libraryOpen = !root.libraryOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.libraryOpen ? libSubCol.implicitHeight : 0
                            opacity: root.libraryOpen ? 1.0 : 0.0
                            visible: Layout.preferredHeight > 1 || opacity > 0.01
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160 } }

                            Rectangle {
                                width: 1; x: 16; y: 2; height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: libSubCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 22; spacing: 2

                                Repeater {
                                    model: root.libraryItems
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: root.virtualMode === modelData.key
                                        Layout.fillWidth: true; height: 26; radius: 7
                                        color: isActive ? Theme.cardHover : (lMouse.containsMouse ? Theme.cardBg : "transparent")
                                        scale: lMouse.pressed ? 0.98 : 1.0
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                        Rectangle {
                                            width: 3; height: isActive ? 15 : 6; radius: 2
                                            anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 8; spacing: 7
                                            SvgIcon {
                                                sourceName: modelData.icon
                                                iconSize: 13
                                                color: isActive ? Theme.accent : Theme.textMuted
                                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans; font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            }
                                            Text {
                                                visible: modelData.key === "starred" && FileService.starredPaths.length > 0
                                                text: String(FileService.starredPaths.length)
                                                color: Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                            }
                                        }

                                        MouseArea {
                                            id: lMouse
                                            anchors.fill: parent; enabled: root.libraryOpen; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: (mouse) => {
                                                if (!root.isPicker && mouse.button === Qt.MiddleButton) {
                                                    root.openTab(root.currentPath, modelData.key, true);
                                                } else if (modelData.key === "recent") {
                                                    root.loadRecent();
                                                } else {
                                                    root.loadStarred();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // / (Root)
                        Rectangle {
                            id: rootNavItem
                            readonly property bool isActive: root.virtualMode === "" && root.currentPath === "/"
                            Layout.fillWidth: true; height: 28; radius: 8
                            color: rootNavItem.isActive ? Theme.cardHover : (rootMouse.containsMouse ? Theme.cardBg : "transparent")
                            scale: rootMouse.pressed ? 0.98 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                            Rectangle {
                                width: 3; height: rootNavItem.isActive ? 15 : 6; radius: 2
                                anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                color: Theme.accent
                                opacity: rootNavItem.isActive ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 8; spacing: 8
                                SvgIcon {
                                    sourceName: "hard-drive"; iconSize: 14
                                    color: rootNavItem.isActive ? Theme.accent : Theme.textSub
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "/ (Root)"
                                    color: rootNavItem.isActive ? Theme.text : Theme.textSub
                                    font.family: Theme.fontSans; font.pixelSize: 13
                                    font.weight: rootNavItem.isActive ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: rootMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: (mouse) => {
                                    if (!root.isPicker && mouse.button === Qt.MiddleButton) root.openTab("/", "", true);
                                    else root.navigateTo("/");
                                }
                            }
                        }
                    }
                }

                // Transfer Progress Card
                Rectangle {
                    id: transferBox
                    visible: !root.isPicker && (Layout.preferredHeight > 1 || opacity > 0.01)
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.transferActive ? 74 : 0
                    opacity: root.transferActive ? 1.0 : 0.0
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: root.transferActive ? 1 : 0
                    border.color: Theme.borderSubtle
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        height: 54
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.transferLabel; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { text: root.transferPct >= 100 ? "Done" : (root.transferPct + "%"); color: Theme.accent; font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.DemiBold }
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 4; radius: 2
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                            Rectangle {
                                height: parent.height; radius: 2
                                color: Theme.accent
                                width: parent.width * (root.transferPct / 100.0)
                                Behavior on width { NumberAnimation { duration: 160 } }
                            }
                        }

                        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.transferSub; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; elide: Text.ElideRight }
                    }
                }

                // Portal Mode Badge Card (Picker Mode)
                Rectangle {
                    visible: root.isPicker
                    Layout.fillWidth: true
                    height: 52
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 2
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            SvgIcon { sourceName: "external-link"; iconSize: 12; color: Theme.textSub }
                            Text { text: "PORTAL MODE"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.pickerBadgeText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Main Content Pane
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Top Toolbar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    // Navigation Cluster
                    PillButton {
                        iconName: "arrow-left"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        enabled: root.historyIdx > 0
                        onClicked: root.goBack()
                    }
                    PillButton {
                        iconName: "arrow-right"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        enabled: root.historyIdx < root.history.length - 1
                        onClicked: root.goForward()
                    }
                    PillButton {
                        iconName: "arrow-up"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        enabled: root.archiverActive || root.virtualMode !== "" || root.currentPath !== "/"
                        onClicked: root.goUp()
                    }
                    PillButton {
                        iconName: "refresh"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.refreshCurrent()
                    }

                    // Interactive Breadcrumb / Path Input Bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 48
                        height: 30; radius: 9
                        color: root.pathEditing ? Theme.surfaceRaised : Theme.cardBg
                        border.width: 1
                        border.color: root.pathEditing ? Theme.accent : Theme.borderSubtle
                        clip: true
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        MouseArea {
                            anchors.fill: parent
                            visible: !root.pathEditing && root.virtualMode === "" && !root.archiverActive
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                pathField.text = root.currentPath;
                                root.pathEditing = true;
                                pathField.forceActiveFocus();
                                pathField.selectAll();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 2
                            opacity: root.pathEditing ? 0.0 : 1.0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Repeater {
                                model: root.breadcrumbSegments
                                delegate: RowLayout {
                                    required property var modelData
                                    required property int index
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: index === root.breadcrumbSegments.length - 1 ? 42 : 24
                                    Layout.preferredWidth: (index > 0 ? 12 : 0) + segText.implicitWidth + 12
                                    Layout.maximumWidth: (index > 0 ? 12 : 0) + Math.min(160, segText.implicitWidth + 12)

                                    Text {
                                        visible: index > 0
                                        text: "›"
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                    }

                                    Rectangle {
                                        height: 22
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: index === root.breadcrumbSegments.length - 1 ? 36 : 20
                                        Layout.preferredWidth: segText.implicitWidth + (modelData.isArchive ? 28 : 12)
                                        Layout.maximumWidth: Math.min(200, segText.implicitWidth + (modelData.isArchive ? 28 : 12))
                                        radius: 6
                                        color: modelData.isArchive
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                            : ((modelData.clickable && segMouse.containsMouse) ? Theme.cardHover : "transparent")
                                        scale: (modelData.clickable && segMouse.pressed) ? 0.95 : 1.0
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 4

                                            SvgIcon {
                                                visible: Boolean(modelData.isArchive)
                                                sourceName: "archive"
                                                iconSize: 12
                                                color: Theme.accent
                                            }

                                            Text {
                                                id: segText
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: modelData.isArchive ? Text.AlignLeft : Text.AlignHCenter
                                                text: modelData.label
                                                color: modelData.isArchive
                                                    ? Theme.accent
                                                    : (index === root.breadcrumbSegments.length - 1 ? Theme.text : Theme.textSub)
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                font.weight: (modelData.isArchive || index === root.breadcrumbSegments.length - 1) ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideMiddle
                                            }
                                        }

                                        MouseArea {
                                            id: segMouse
                                            anchors.fill: parent
                                            enabled: modelData.clickable
                                            hoverEnabled: true
                                            cursorShape: modelData.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (modelData.path && modelData.path !== root.currentPath) {
                                                    root.navigateTo(modelData.path);
                                                } else if (root.archiverActive) {
                                                    root.archiverActive = false;
                                                } else if (root.virtualMode === "") {
                                                    pathField.text = root.currentPath;
                                                    root.pathEditing = true;
                                                    pathField.forceActiveFocus();
                                                    pathField.selectAll();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }
                        }

                        AnimatedTextInput {
                            id: pathField
                            opacity: root.pathEditing ? 1.0 : 0.0
                            visible: root.pathEditing || opacity > 0.01
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            textColor: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            clip: true
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Keys.onReturnPressed: {
                                root.pathEditing = false;
                                root.navigateTo(text);
                                root.forceActiveFocus();
                            }
                            Keys.onEscapePressed: (event) => {
                                root.pathEditing = false;
                                root.forceActiveFocus();
                                event.accepted = true;
                            }
                            onActiveFocusChanged: { if (!activeFocus) root.pathEditing = false; }
                        }
                    }

                    // Right Action Cluster
                    PillButton {
                        id: sortBtn
                        visible: !root.archiverActive
                        iconName: "sort"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openSortMenu(sortBtn)
                    }

                    PillButton {
                        visible: !root.archiverActive
                        iconName: root.showHidden ? "eye" : "eye-off"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8
                        active: root.showHidden
                        subtle: !root.showHidden
                        onClicked: {
                            root.showHidden = !root.showHidden;
                            FileService.setHiddenPref(root.showHidden);
                            root.refreshCurrent();
                        }
                    }

                    PillButton {
                        visible: !root.archiverActive && root.isInTrash && !root.isPicker
                        iconName: "trash"; iconSize: 13
                        text: "Empty"
                        fontSize: 11; horizontalPadding: 9; verticalPadding: 5; radius: 8
                        danger: true
                        enabled: (root.currentItems || []).length > 0
                        onClicked: root.requestEmptyTrash()
                    }

                    PillButton {
                        visible: !root.archiverActive && root.virtualMode === "" && !root.isInTrash
                        iconName: "folder-plus"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openInputModal("mkdir", "New Folder", "New Folder", "")
                    }

                    PillButton {
                        visible: !root.archiverActive && !root.isPicker && root.virtualMode === "" && !root.isInTrash
                        iconName: "file-plus"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openInputModal("mkfile", "New File", "untitled.txt", "")
                    }

                    PillButton {
                        visible: !root.archiverActive && !root.isPicker && tabsModel.count <= 1
                        iconName: "plus"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openTab(root.currentPath, "", true)
                    }

                    // Segmented View Mode Control (Grid | List)
                    Rectangle {
                        visible: !root.archiverActive
                        width: 64; height: 30; radius: 9
                        color: Theme.cardBg
                        border.width: 1; border.color: Theme.borderSubtle

                        Rectangle {
                            x: root.isListView ? 32 : 2
                            y: 2
                            width: 30; height: 26; radius: 7
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 0

                            Item {
                                width: 30; height: 26
                                scale: gridSegMouse.pressed ? 0.90 : 1.0
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "grid"; iconSize: 14
                                    color: !root.isListView ? Theme.accent : (gridSegMouse.containsMouse ? Theme.text : Theme.textMuted)
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: gridSegMouse
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.isListView = false;
                                        FileService.setViewPref(false);
                                    }
                                }
                            }

                            Item {
                                width: 30; height: 26
                                scale: listSegMouse.pressed ? 0.90 : 1.0
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "list"; iconSize: 14
                                    color: root.isListView ? Theme.accent : (listSegMouse.containsMouse ? Theme.text : Theme.textMuted)
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: listSegMouse
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.isListView = true;
                                        FileService.setViewPref(true);
                                    }
                                }
                            }
                        }
                    }
                }

                // Animated Clipboard Banner (Copy / Cut Ready)
                Rectangle {
                    readonly property bool showClip: !root.isPicker && !root.archiverActive && FileService.clipboardPaths.length > 0 && root.virtualMode === "" && !root.isInTrash
                    visible: Layout.preferredHeight > 1 || opacity > 0.01
                    Layout.fillWidth: true
                    Layout.preferredHeight: showClip ? 36 : 0
                    opacity: showClip ? 1.0 : 0.0
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: showClip ? 1 : 0
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.leftMargin: 12; anchors.rightMargin: 8; height: 36; spacing: 8
                        SvgIcon {
                            sourceName: FileService.clipboardMode === "cut" ? "scissors" : "copy"
                            iconSize: 14; color: Theme.accent
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: FileService.clipboardPaths.length + (FileService.clipboardPaths.length === 1 ? " item" : " items") + (FileService.clipboardMode === "cut" ? " ready to move" : " ready to copy")
                            color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; elide: Text.ElideRight
                        }
                        PillButton {
                            text: "Paste Here"
                            iconName: "clipboard"; iconSize: 12
                            fontSize: 11; horizontalPadding: 10; verticalPadding: 4; radius: 7
                            active: true
                            onClicked: root.performPaste()
                        }
                        PillButton {
                            iconName: "close"; iconSize: 11
                            fixedWidth: 24; fixedHeight: 24; radius: 6; subtle: true
                            onClicked: FileService.clearClipboard()
                        }
                    }
                }

                // Animated Archive Context Banner (indicates active archive; contents render full-height in filesViewport)
                Rectangle {
                    visible: Layout.preferredHeight > 1 || opacity > 0.01
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.archiverActive ? 40 : 0
                    opacity: root.archiverActive ? 1.0 : 0.0
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: root.archiverActive ? 1 : 0
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.leftMargin: 8; anchors.rightMargin: 8; height: 40; spacing: 8

                        PillButton {
                            iconName: "arrow-left"; iconSize: 13
                            fixedWidth: 26; fixedHeight: 26; radius: 7; subtle: true
                            onClicked: root.archiverActive = false
                        }

                        Rectangle {
                            height: 20; radius: 5
                            implicitWidth: archBadgeRow.implicitWidth + 10
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            RowLayout {
                                id: archBadgeRow
                                anchors.centerIn: parent; spacing: 4
                                SvgIcon { sourceName: "archive"; iconSize: 11; color: Theme.accent }
                                Text {
                                    text: "ARCHIVE"
                                    color: Theme.accent
                                    font.family: Theme.fontSans; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.5
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: root.archiverArchiveName
                            color: Theme.text
                            font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }

                        Text {
                            text: {
                                if (root.archiverLoading) return "Reading...";
                                if (root.archiverError !== "") return "Protected";
                                const total = (root.archiverEntries || []).length;
                                const shown = (root.filteredArchiveEntries || []).length;
                                return (shown !== total ? (shown + "/" + total) : total) + (total === 1 ? " entry" : " entries");
                            }
                            color: root.archiverError !== "" ? Theme.dangerText : Theme.textSub
                            font.family: Theme.fontMono; font.pixelSize: 11
                        }

                        PillButton {
                            text: "Extract Here"
                            iconName: "extract"; iconSize: 12
                            fontSize: 11; horizontalPadding: 10; verticalPadding: 4; radius: 7
                            active: true
                            onClicked: root.beginExtract(root.archiverArchivePath, root.archiverArchiveName, "")
                        }

                        PillButton {
                            iconName: "close"; iconSize: 11
                            fixedWidth: 26; fixedHeight: 26; radius: 7; subtle: true
                            onClicked: root.archiverActive = false
                        }
                    }
                }

                // Virtualized Grid / List File Viewport + Right Preview Sidebar
                RowLayout {
                    id: filesViewportRow
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                Item {
                    id: filesViewport
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    clip: true

                    property real _selStartX: 0
                    property real _selStartY: 0
                    property bool _selMoved: false
                    property var _selBasePaths: []

                    function beginMarquee(vx, vy, modifiers) {
                        _selStartX = vx;
                        _selStartY = vy;
                        _selMoved = false;
                        const additive = (modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
                        _selBasePaths = additive ? root.selectedPaths.slice() : [];
                        marqueeRect.x = vx;
                        marqueeRect.y = vy;
                        marqueeRect.width = 0;
                        marqueeRect.height = 0;
                    }

                    function moveMarquee(vx, vy) {
                        const dist = Math.hypot(vx - _selStartX, vy - _selStartY);
                        if (dist > 6) {
                            _selMoved = true;
                            marqueeRect.visible = true;
                            const rx = Math.min(_selStartX, vx);
                            const ry = Math.min(_selStartY, vy);
                            const rw = Math.abs(vx - _selStartX);
                            const rh = Math.abs(vy - _selStartY);
                            marqueeRect.x = rx;
                            marqueeRect.y = ry;
                            marqueeRect.width = rw;
                            marqueeRect.height = rh;
                            updateMarqueeSelection(rx, ry, rw, rh);
                        }
                    }

                    function endMarquee() {
                        marqueeRect.visible = false;
                    }

                    function updateMarqueeSelection(rx, ry, rw, rh) {
                        const next = _selBasePaths.slice();
                        const count = viewModel.count;
                        if (!root.isListView) {
                            const cols = filesGrid.cols;
                            const cw = filesGrid.cellWidth;
                            const ch = filesGrid.cellHeight;
                            const cy = filesGrid.contentY;
                            for (let i = 0; i < count; ++i) {
                                const col = i % cols;
                                const row = Math.floor(i / cols);
                                const ix = col * cw + 4;
                                const iy = row * ch - cy + 2;
                                const iw = cw - 10;
                                const ih = ch - 10;
                                if (!(ix + iw < rx || ix > rx + rw || iy + ih < ry || iy > ry + rh)) {
                                    const p = viewModel.get(i).path;
                                    if (next.indexOf(p) === -1) next.push(p);
                                }
                            }
                        } else {
                            const cy = filesList.contentY;
                            const rowStep = 39; // 36 + 3 spacing
                            const headerOffset = 28; // 24 + 4 spacing
                            const iw = Math.max(0, filesList.width - 10);
                            for (let i = 0; i < count; ++i) {
                                const iy = headerOffset + i * rowStep - cy;
                                const ih = 36;
                                if (!(iw < rx || 0 > rx + rw || iy + ih < ry || iy > ry + rh)) {
                                    const p = viewModel.get(i).path;
                                    if (next.indexOf(p) === -1) next.push(p);
                                }
                            }
                        }
                        root.selectedPaths = next;
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.archiverActive
                        acceptedButtons: Qt.RightButton | Qt.LeftButton
                        onPressed: (mouse) => {
                            root.forceActiveFocus();
                            if (mouse.button === Qt.LeftButton && (!root.isPicker || root.pickerMultiple)) {
                                filesViewport.beginMarquee(mouse.x, mouse.y, mouse.modifiers);
                            }
                        }
                        onPositionChanged: (mouse) => {
                            if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return;
                            if (root.isPicker && !root.pickerMultiple) return;
                            filesViewport.moveMarquee(mouse.x, mouse.y);
                        }
                        onReleased: (mouse) => {
                            filesViewport.endMarquee();
                            if (mouse.button === Qt.LeftButton && !filesViewport._selMoved) {
                                root.selectedPaths = [];
                                root.lastSelectedIdx = -1;
                            }
                        }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                root.selectedPaths = [];
                                root.lastSelectedIdx = -1;
                                openContextMenu(this, mouse, null);
                            }
                        }
                    }

                    // Full-Viewport Archive Browser
                    Item {
                        id: archiveViewport
                        anchors.fill: parent
                        clip: true
                        z: 4
                        opacity: root.archiverActive ? 1.0 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        transform: Translate {
                            y: root.archiverActive ? 0 : 8
                            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }

                        // Loading / Error / Empty Archive State
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(340, parent.width - 40)
                            spacing: 10
                            opacity: (root.archiverLoading || root.archiverError !== "" || root.filteredArchiveEntries.length === 0) ? 1.0 : 0.0
                            visible: opacity > 0.01
                            z: 2
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 56; height: 56; radius: 16
                                color: Theme.cardBg
                                border.width: 1; border.color: Theme.borderSubtle
                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: root.archiverError !== "" ? "info" : (root.searchQuery.trim() !== "" ? "search" : "archive")
                                    iconSize: 24
                                    color: root.archiverError !== "" ? Theme.dangerText : (root.archiverLoading ? Theme.accent : Theme.textMuted)
                                }
                            }

                            Text {
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                horizontalAlignment: Text.AlignHCenter
                                text: root.archiverLoading
                                    ? "Reading archive..."
                                    : (root.archiverError !== ""
                                        ? "Unable to inspect archive"
                                        : (root.searchQuery.trim() !== "" ? "No matching entries" : "Archive is empty"))
                                color: Theme.text
                                font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: root.archiverLoading
                                    ? root.archiverArchiveName
                                    : (root.archiverError !== ""
                                        ? root.archiverError
                                        : (root.searchQuery.trim() !== ""
                                            ? "Try a different keyword to filter entries inside this archive."
                                            : "No files or folders were found inside this archive."))
                                color: Theme.textSub
                                font.family: Theme.fontSans; font.pixelSize: 11
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8
                                PillButton {
                                    visible: !root.archiverLoading && root.archiverError !== ""
                                    text: "Extract Here"
                                    iconName: "extract"; iconSize: 12
                                    active: true
                                    onClicked: root.beginExtract(root.archiverArchivePath, root.archiverArchiveName, "")
                                }
                                PillButton {
                                    visible: !root.archiverLoading && root.archiverError === "" && root.searchQuery.trim() !== ""
                                    text: "Clear Search"
                                    iconName: "close"; iconSize: 12
                                    onClicked: {
                                        searchField.text = "";
                                        root.searchQuery = "";
                                    }
                                }
                            }
                        }

                        ListView {
                            id: archiverList
                            anchors.fill: parent
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            reuseItems: true
                            cacheBuffer: 240
                            model: root.archiverActive ? root.filteredArchiveEntries : []

                            ScrollBar.vertical: ScrollBar {
                                policy: archiverList.contentHeight > archiverList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                width: 8
                                padding: 2
                                contentItem: Rectangle {
                                    implicitWidth: 4; radius: 2
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.28)
                                }
                            }

                            delegate: Rectangle {
                                id: archRow
                                required property var modelData
                                readonly property string cleanPath: String(modelData.name || "").replace(/\/+$/, "")
                                readonly property int slashIdx: cleanPath.lastIndexOf("/")
                                readonly property string entryName: slashIdx >= 0 ? cleanPath.slice(slashIdx + 1) : cleanPath
                                readonly property string entryDir: slashIdx >= 0 ? cleanPath.slice(0, slashIdx) : ""

                                width: Math.max(0, ListView.view.width - (archiverList.contentHeight > archiverList.height ? 10 : 0))
                                height: entryDir !== "" ? 42 : 36
                                radius: 8
                                clip: true
                                color: archRowMouse.containsMouse
                                    ? Theme.cardHover
                                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035)
                                border.width: 1
                                border.color: archRowMouse.containsMouse
                                    ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16)
                                    : "transparent"
                                scale: archRowMouse.pressed ? 0.99 : 1.0

                                Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                MouseArea {
                                    id: archRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 12
                                    spacing: 10

                                    Rectangle {
                                        width: 26; height: 26; radius: 7
                                        color: Theme.cardBg
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: root.iconFor(archRow.modelData.type)
                                            iconSize: 14
                                            color: root.iconColorFor(archRow.modelData.type)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: archRow.entryName
                                            color: Theme.text
                                            font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: archRow.entryDir !== ""
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: archRow.entryDir
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono; font.pixelSize: 10
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    Text {
                                        text: archRow.modelData.type === "folder" ? "Folder" : String(archRow.modelData.meta || "Compressed")
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono; font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }

                    // Rubber-band Marquee Selection Box
                    Rectangle {
                        id: marqueeRect
                        visible: false
                        z: 10
                        radius: 4
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.65)
                    }

                    // Empty / Error State Overlay
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(320, parent.width - 40)
                        spacing: 10
                        opacity: (!root.archiverActive && !root.isLoading && root._hasLoadedOnce && root.visibleItems.length === 0) ? 1.0 : 0.0
                        visible: opacity > 0.01
                        z: 2
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 56; height: 56; radius: 16
                            color: Theme.cardBg
                            border.width: 1; border.color: Theme.borderSubtle
                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: root.loadError !== "" ? "info" : (root.searchQuery !== "" ? "search" : (root.virtualMode === "starred" ? "star" : (root.isInTrash ? "trash" : "folder")))
                                iconSize: 24
                                color: root.loadError !== "" ? Theme.dangerText : Theme.textMuted
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: root.loadError !== ""
                                ? root.loadError
                                : (root.searchQuery.trim() !== ""
                                    ? "No matching items"
                                    : (root.virtualMode === "starred"
                                        ? "No starred items yet"
                                        : (root.isInTrash ? "Trash is empty" : "This folder is empty")))
                            color: Theme.text
                            font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.loadError !== ""
                                ? "Check that the directory exists and you have read permissions."
                                : (root.searchQuery.trim() !== ""
                                    ? "Try a different keyword or press Enter in Search for a deep scan."
                                    : (root.virtualMode === "starred"
                                        ? "Right-click any file or folder and choose Star for quick access."
                                        : (root.isInTrash ? "Items moved to Trash will appear here." : "Create a folder or paste items here.")))
                            color: Theme.textSub
                            font.family: Theme.fontSans; font.pixelSize: 11
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8
                            PillButton {
                                visible: root.loadError !== ""
                                text: "Go Home"
                                iconName: "home"; iconSize: 13
                                active: true
                                onClicked: root.navigateTo(FileService.homeDir)
                            }
                            PillButton {
                                visible: root.loadError === "" && (root.searchQuery.trim() !== "" || root.isDeepSearch)
                                text: "Clear Search"
                                iconName: "close"; iconSize: 12
                                onClicked: {
                                    searchField.text = "";
                                    root.searchQuery = "";
                                    if (root.isDeepSearch) root.refreshCurrent();
                                }
                            }
                            PillButton {
                                visible: root.loadError === "" && root.searchQuery.trim() === "" && root.virtualMode === "" && !root.isInTrash
                                text: "New Folder"
                                iconName: "folder-plus"; iconSize: 13
                                onClicked: root.openInputModal("mkdir", "New Folder", "New Folder", "")
                            }
                        }
                    }

                    // Virtualized Grid View (Balanced col math from target width + ScrollBar gutter)
                    GridView {
                        id: filesGrid
                        opacity: (!root.archiverActive && !root.isListView) ? 1.0 : 0.0
                        visible: opacity > 0.01
                        anchors.fill: parent
                        clip: true
                        interactive: false
                        reuseItems: false
                        cacheBuffer: 240
                        readonly property real targetViewportWidth: Math.max(200, filesViewportRow.width - (root.showPreviewPanel ? previewPanelHost.targetWidth : 0))
                        readonly property int cols: Math.max(2, Math.floor((targetViewportWidth - 10) / 154))
                        cellWidth: Math.floor((width - 10) / cols)
                        cellHeight: 118
                        model: !root.isListView ? viewModel : emptyModel
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        onColsChanged: {
                            root._transitionsEnabled = false;
                            animEnableTimer.interval = 60;
                            animEnableTimer.restart();
                        }

                        WheelHandler {
                            enabled: !root.anyModalOpen && !root.archiverActive
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (event) => {
                                const maxY = Math.max(0, filesGrid.contentHeight - filesGrid.height);
                                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y * 0.45);
                                filesGrid.contentY = Math.max(0, Math.min(maxY, filesGrid.contentY - delta));
                            }
                        }

                        Transition {
                            id: gridAddTrans
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 190; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; from: 0.88; to: 1.0; duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.85 }
                            }
                        }
                        Transition {
                            id: gridRemoveTrans
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; to: 0.85; duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                        Transition {
                            id: gridMoveTrans
                            NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutCubic }
                        }

                        add: (root._transitionsEnabled && !Theme.reduceMotion) ? gridAddTrans : null
                        remove: (root._transitionsEnabled && !Theme.reduceMotion) ? gridRemoveTrans : null
                        displaced: (root._transitionsEnabled && !Theme.reduceMotion) ? gridMoveTrans : null
                        move: (root._transitionsEnabled && !Theme.reduceMotion) ? gridMoveTrans : null

                        ScrollBar.vertical: ScrollBar {
                            policy: filesGrid.contentHeight > filesGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            width: 8
                            padding: 2
                            contentItem: Rectangle {
                                implicitWidth: 4
                                radius: 2
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.28)
                            }
                        }

                        delegate: Item {
                            id: gridDelegate
                            required property int index
                            required property string name
                            required property string path
                            required property string parentDir
                            required property string relPath
                            required property string type
                            required property double size
                            required property double mtime
                            required property string modifiedText
                            required property string meta

                            width: filesGrid.cellWidth
                            height: filesGrid.cellHeight

                            readonly property var itemObj: ({
                                name: name, path: path, parentDir: parentDir, relPath: relPath,
                                type: type, size: size, mtime: mtime, modifiedText: modifiedText, meta: meta
                            })
                            readonly property bool isSel: root.isPathSelected(path)
                            readonly property bool isCut: FileService.clipboardMode === "cut" && FileService.clipboardPaths.indexOf(path) !== -1
                            readonly property bool isStar: FileService.isStarred(path)
                            readonly property color itemColor: root.iconColorFor(type)

                            onPathChanged: gridThumbBox.loadThumb()
                            onTypeChanged: gridThumbBox.loadThumb()

                            Rectangle {
                                id: gridCard
                                anchors.fill: parent
                                anchors.topMargin: 2
                                anchors.leftMargin: 4
                                anchors.rightMargin: 6
                                anchors.bottomMargin: 8
                                radius: 12
                                opacity: isCut ? 0.46 : 1.0
                                color: isSel
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                    : (gMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                border.width: 1
                                border.color: isSel
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.58)
                                    : (gMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22) : Theme.borderSubtle)
                                scale: gMouse.pressed ? 0.96 : 1.0

                                Drag.active: gridDragHandler.active
                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.CopyAction
                                Drag.hotSpot: Qt.point(16, 16)
                                Drag.imageSource: Qt.resolvedUrl("../assets/icons/" + root.iconFor(gridDelegate.type) + ".svg")
                                Drag.mimeData: root.buildDragMime(gridDelegate.path)

                                DragHandler {
                                    id: gridDragHandler
                                    enabled: !root.anyModalOpen && !root.archiverActive
                                    target: null
                                    acceptedButtons: Qt.LeftButton
                                    onActiveChanged: {
                                        if (active && !root.isPathSelected(gridDelegate.path)) {
                                            root.selectedPaths = [gridDelegate.path];
                                            root.lastSelectedIdx = index;
                                        }
                                    }
                                }

                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                SvgIcon {
                                    visible: isStar
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.topMargin: 8; anchors.rightMargin: 8
                                    sourceName: "star"; iconSize: 11; color: Theme.accent
                                }

                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 6

                                    Rectangle {
                                        id: gridThumbBox
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 11
                                        color: Qt.rgba(itemColor.r, itemColor.g, itemColor.b, 0.13)
                                        property string videoThumbUrl: ""
                                        readonly property string thumbUrl: gridDelegate.type === "image"
                                            ? FileService.fileUrl(gridDelegate.path)
                                            : (gridDelegate.type === "video" ? videoThumbUrl : "")
                                        function loadThumb() {
                                            videoThumbUrl = "";
                                            if (gridDelegate.type === "video") {
                                                const reqPath = gridDelegate.path;
                                                FileService.requestVideoThumb(reqPath, (url) => {
                                                    if (gridDelegate && gridDelegate.path === reqPath) gridThumbBox.videoThumbUrl = url;
                                                });
                                            }
                                        }
                                        Component.onCompleted: loadThumb()
                                        AdaptiveClipRect {
                                            anchors.fill: parent
                                            radius: gridPreviewImg.opacity > 0.01 ? 11 : 0
                                            color: "transparent"
                                            visible: gridPreviewImg.opacity > 0.01
                                            Image {
                                                id: gridPreviewImg
                                                anchors.fill: parent
                                                source: gridThumbBox.thumbUrl
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                sourceSize: Qt.size(84, 84)
                                                opacity: status === Image.Ready ? 1 : 0
                                                visible: opacity > 0.01
                                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: root.iconFor(gridDelegate.type)
                                            iconSize: 22
                                            color: itemColor
                                            opacity: gridPreviewImg.status === Image.Ready ? 0.0 : 1.0
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        text: gridDelegate.name
                                        color: Theme.text
                                        font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        text: gridDelegate.meta
                                        color: Theme.textSub
                                        font.family: gridDelegate.type === "folder" ? Theme.fontSans : Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: gMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.MiddleButton) {
                                            if (!root.isPicker && gridDelegate.type === "folder") root.openTab(gridDelegate.path, "", true);
                                        } else if (mouse.button === Qt.RightButton) {
                                            root.handleItemRightClick(this, mouse, gridDelegate.itemObj, index);
                                        } else {
                                            root.handleItemClick(gridDelegate.itemObj, index, mouse);
                                        }
                                    }
                                    onDoubleClicked: (mouse) => {
                                        if (mouse.button === Qt.LeftButton) {
                                            root.handleItemDoubleClick(gridDelegate.itemObj);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Virtualized List View with Sortable Column Header
                    ColumnLayout {
                        opacity: (!root.archiverActive && root.isListView) ? 1.0 : 0.0
                        visible: opacity > 0.01
                        anchors.fill: parent
                        spacing: 4
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        // Column Header
                        Rectangle {
                            visible: root.visibleItems.length > 0
                            Layout.fillWidth: true
                            height: 24; radius: 6
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 20; spacing: 10

                                MouseArea {
                                    id: hdrNameMouse
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("name")
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        scale: hdrNameMouse.pressed ? 0.96 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                                        Text {
                                            text: "Name"
                                            color: root.sortBy === "name" ? Theme.text : (hdrNameMouse.containsMouse ? Theme.textSub : Theme.textMuted)
                                            font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }
                                        SvgIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: root.sortBy === "name"
                                            sourceName: "arrow-up"; iconSize: 11; color: Theme.accent
                                            rotation: root.sortAsc ? 0 : 180
                                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hdrModMouse
                                    Layout.preferredWidth: 88; Layout.fillHeight: true
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("mtime")
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        scale: hdrModMouse.pressed ? 0.96 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                                        SvgIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: root.sortBy === "mtime"
                                            sourceName: "arrow-up"; iconSize: 11; color: Theme.accent
                                            rotation: root.sortAsc ? 0 : 180
                                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                        Text {
                                            text: "Modified"
                                            color: root.sortBy === "mtime" ? Theme.text : (hdrModMouse.containsMouse ? Theme.textSub : Theme.textMuted)
                                            font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hdrSizeMouse
                                    Layout.preferredWidth: 72; Layout.fillHeight: true
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("size")
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        scale: hdrSizeMouse.pressed ? 0.96 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                                        SvgIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: root.sortBy === "size"
                                            sourceName: "arrow-up"; iconSize: 11; color: Theme.accent
                                            rotation: root.sortAsc ? 0 : 180
                                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                        Text {
                                            text: "Size"
                                            color: root.sortBy === "size" ? Theme.text : (hdrSizeMouse.containsMouse ? Theme.textSub : Theme.textMuted)
                                            font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: filesList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            interactive: false
                            reuseItems: false
                            cacheBuffer: 240
                            spacing: 3
                            model: root.isListView ? viewModel : emptyModel

                            WheelHandler {
                                enabled: !root.anyModalOpen && !root.archiverActive
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (event) => {
                                    const maxY = Math.max(0, filesList.contentHeight - filesList.height);
                                    const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y * 0.45);
                                    filesList.contentY = Math.max(0, Math.min(maxY, filesList.contentY - delta));
                                }
                            }

                            Transition {
                                id: listAddTrans
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 190; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 210; easing.type: Easing.OutCubic }
                                }
                            }
                            Transition {
                                id: listRemoveTrans
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; to: 0.94; duration: 160; easing.type: Easing.OutCubic }
                                }
                            }
                            Transition {
                                id: listMoveTrans
                                NumberAnimation { properties: "x,y"; duration: 240; easing.type: Easing.OutCubic }
                            }

                            add: (root._transitionsEnabled && !Theme.reduceMotion) ? listAddTrans : null
                            remove: (root._transitionsEnabled && !Theme.reduceMotion) ? listRemoveTrans : null
                            displaced: (root._transitionsEnabled && !Theme.reduceMotion) ? listMoveTrans : null
                            move: (root._transitionsEnabled && !Theme.reduceMotion) ? listMoveTrans : null

                            ScrollBar.vertical: ScrollBar {
                                policy: filesList.contentHeight > filesList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                width: 8
                                padding: 2
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.28)
                                }
                            }

                            delegate: Item {
                                id: listDelegate
                                required property int index
                                required property string name
                                required property string path
                                required property string parentDir
                                required property string relPath
                                required property string type
                                required property double size
                                required property double mtime
                                required property string modifiedText
                                required property string meta

                                readonly property var itemObj: ({
                                    name: name, path: path, parentDir: parentDir, relPath: relPath,
                                    type: type, size: size, mtime: mtime, modifiedText: modifiedText, meta: meta
                                })
                                readonly property bool isSel: root.isPathSelected(path)
                                readonly property bool isCut: FileService.clipboardMode === "cut" && FileService.clipboardPaths.indexOf(path) !== -1
                                readonly property bool isStar: FileService.isStarred(path)
                                readonly property color itemColor: root.iconColorFor(type)

                                width: Math.max(0, filesList.width - 10)
                                height: 36

                                onPathChanged: listThumbBox.loadThumb()
                                onTypeChanged: listThumbBox.loadThumb()

                                Rectangle {
                                    id: listCard
                                    anchors.fill: parent
                                    radius: 8
                                    opacity: isCut ? 0.46 : 1.0
                                    color: isSel
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                        : (rowMouse.containsMouse ? Theme.cardHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035))
                                    border.width: 1
                                    border.color: isSel
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.52)
                                        : (rowMouse.containsMouse ? Theme.borderSubtle : "transparent")
                                    scale: rowMouse.pressed ? 0.99 : 1.0

                                    Drag.active: listDragHandler.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction
                                    Drag.hotSpot: Qt.point(16, 16)
                                    Drag.imageSource: Qt.resolvedUrl("../assets/icons/" + root.iconFor(listDelegate.type) + ".svg")
                                    Drag.mimeData: root.buildDragMime(listDelegate.path)

                                    Item {
                                        id: listDragArea
                                        x: 0; y: 0; height: parent.height
                                        width: listDelegate.isSel ? parent.width : Math.min(parent.width - 176, 46 + listNameText.implicitWidth + 16)
                                        DragHandler {
                                            id: listDragHandler
                                            enabled: !root.anyModalOpen && !root.archiverActive
                                            target: null
                                            acceptedButtons: Qt.LeftButton
                                            onActiveChanged: {
                                                if (active && !root.isPathSelected(listDelegate.path)) {
                                                    root.selectedPaths = [listDelegate.path];
                                                    root.lastSelectedIdx = index;
                                                }
                                            }
                                        }
                                    }

                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10

                                        Item {
                                            id: listThumbBox
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20
                                            property string videoThumbUrl: ""
                                            readonly property string thumbUrl: listDelegate.type === "image"
                                                ? FileService.fileUrl(listDelegate.path)
                                                : (listDelegate.type === "video" ? videoThumbUrl : "")
                                            function loadThumb() {
                                                videoThumbUrl = "";
                                                if (listDelegate.type === "video") {
                                                    const reqPath = listDelegate.path;
                                                    FileService.requestVideoThumb(reqPath, (url) => {
                                                        if (listDelegate && listDelegate.path === reqPath) listThumbBox.videoThumbUrl = url;
                                                    });
                                                }
                                            }
                                            Component.onCompleted: loadThumb()
                                            AdaptiveClipRect {
                                                anchors.fill: parent
                                                radius: listPreviewImg.opacity > 0.01 ? 5 : 0
                                                color: "transparent"
                                                visible: listPreviewImg.opacity > 0.01
                                                Image {
                                                    id: listPreviewImg
                                                    anchors.fill: parent
                                                    source: listThumbBox.thumbUrl
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    sourceSize: Qt.size(40, 40)
                                                    opacity: status === Image.Ready ? 1 : 0
                                                    visible: opacity > 0.01
                                                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                            SvgIcon {
                                                anchors.centerIn: parent
                                                sourceName: root.iconFor(listDelegate.type)
                                                iconSize: 16
                                                color: itemColor
                                                opacity: listPreviewImg.status === Image.Ready ? 0.0 : 1.0
                                                visible: opacity > 0.01
                                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        Text {
                                            id: listNameText
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: listDelegate.name
                                            color: Theme.text
                                            font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: Boolean(listDelegate.relPath)
                                            text: listDelegate.relPath || ""
                                            color: Theme.textMuted
                                            font.family: Theme.fontSans; font.pixelSize: 11
                                            elide: Text.ElideMiddle
                                            Layout.maximumWidth: 140
                                        }

                                        SvgIcon {
                                            visible: isStar
                                            sourceName: "star"; iconSize: 11; color: Theme.accent
                                        }

                                        Text {
                                            Layout.preferredWidth: 88
                                            horizontalAlignment: Text.AlignRight
                                            text: listDelegate.modifiedText || ""
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono; font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.preferredWidth: 72
                                            horizontalAlignment: Text.AlignRight
                                            text: listDelegate.type === "folder" ? "Folder" : FileService.formatSize(listDelegate.size)
                                            color: Theme.textSub
                                            font.family: Theme.fontMono; font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        property bool _marqueeActive: false
                                        onPressed: (mouse) => {
                                            _marqueeActive = false;
                                            filesViewport._selMoved = false;
                                            if (mouse.button === Qt.LeftButton && (!root.isPicker || root.pickerMultiple)) {
                                                if (mouse.x > listDragArea.width && !listDelegate.isSel) {
                                                    _marqueeActive = true;
                                                    const pt = rowMouse.mapToItem(filesViewport, mouse.x, mouse.y);
                                                    filesViewport.beginMarquee(pt.x, pt.y, mouse.modifiers);
                                                }
                                            }
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!_marqueeActive || !pressed || (mouse.buttons & Qt.LeftButton) === 0) return;
                                            const pt = rowMouse.mapToItem(filesViewport, mouse.x, mouse.y);
                                            filesViewport.moveMarquee(pt.x, pt.y);
                                        }
                                        onReleased: (mouse) => {
                                            if (_marqueeActive) {
                                                _marqueeActive = false;
                                                filesViewport.endMarquee();
                                            }
                                        }
                                        onCanceled: {
                                            if (_marqueeActive) {
                                                _marqueeActive = false;
                                                filesViewport.endMarquee();
                                            }
                                        }
                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.LeftButton && filesViewport._selMoved) {
                                                filesViewport._selMoved = false;
                                                return;
                                            }
                                            if (mouse.button === Qt.MiddleButton) {
                                                if (!root.isPicker && listDelegate.type === "folder") root.openTab(listDelegate.path, "", true);
                                            } else if (mouse.button === Qt.RightButton) {
                                                root.handleItemRightClick(this, mouse, listDelegate.itemObj, index);
                                            } else {
                                                root.handleItemClick(listDelegate.itemObj, index, mouse);
                                            }
                                        }
                                        onDoubleClicked: (mouse) => {
                                            if (mouse.button === Qt.LeftButton) {
                                                root.handleItemDoubleClick(listDelegate.itemObj);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Preview Sidebar (beside viewport, opens only for registered previewable types)
                Item {
                    id: previewPanelHost
                    readonly property int targetWidth: Math.min(244, Math.max(180, Math.floor(filesViewportRow.width * 0.36)))
                    Layout.preferredWidth: root.showPreviewPanel ? targetWidth : 0
                    Layout.fillHeight: true
                    clip: true
                    visible: width > 1 || root.showPreviewPanel

                    Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                    onWidthChanged: {
                        if (!root.showPreviewPanel && width <= 1) {
                            root._previewDisplayItem = null;
                            root._previewDisplayLabel = "";
                            root._previewDisplayMode = "";
                            root._previewMediaSource = "";
                            root._previewText = "";
                        }
                    }

                    Rectangle {
                        id: previewPanel
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, previewPanelHost.targetWidth - 10)
                        radius: 12
                        color: Theme.pillBg
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        ThemeGradientFill {
                            anchors.fill: parent
                            anchors.margins: 1
                            enabled: Theme.effectiveShellGradient
                            color1: Theme.pillBg
                            colorMid: Theme.pillBgMid
                            color2: Theme.pillBg2
                            cornerRadius: 11
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            opacity: root.showPreviewPanel ? 1.0 : 0.0
                            transform: Translate {
                                x: root.showPreviewPanel ? 0 : 10
                                Behavior on x { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                            }
                            Behavior on opacity { NumberAnimation { duration: root.showPreviewPanel ? 150 : 90; easing.type: Easing.OutCubic } }

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "Preview"
                                    color: Theme.textSub
                                    font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                PillButton {
                                    iconName: "close"; iconSize: 12
                                    fixedWidth: 24; fixedHeight: 24; radius: 7; subtle: true
                                    onClicked: root.previewDismissed = true
                                }
                            }

                            // Preview Canvas
                            Rectangle {
                                id: previewCanvas
                                Layout.fillWidth: true
                                Layout.fillHeight: root._previewDisplayMode === "text" && root._previewText !== ""
                                Layout.preferredHeight: 176
                                radius: 12
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: (previewCanvasMouse.enabled && previewCanvasMouse.containsMouse)
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                    : Theme.borderSubtle
                                clip: true
                                scale: (previewCanvasMouse.enabled && previewCanvasMouse.pressed) ? 0.985 : 1.0
                                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                AdaptiveClipRect {
                                    readonly property real maxW: Math.max(1, previewCanvas.width - 8)
                                    readonly property real maxH: Math.max(1, previewCanvas.height - 8)
                                    readonly property bool hasImg: (root._previewDisplayMode === "image" || root._previewDisplayMode === "video")
                                        && panelPreviewImg.status === Image.Ready
                                        && panelPreviewImg.implicitWidth > 0 && panelPreviewImg.implicitHeight > 0
                                    readonly property real fitScale: hasImg ? Math.min(maxW / panelPreviewImg.implicitWidth, maxH / panelPreviewImg.implicitHeight) : 1
                                    anchors.centerIn: parent
                                    width: hasImg ? Math.max(1, Math.round(panelPreviewImg.implicitWidth * fitScale)) : maxW
                                    height: hasImg ? Math.max(1, Math.round(panelPreviewImg.implicitHeight * fitScale)) : maxH
                                    radius: panelPreviewImg.opacity > 0.01 ? 8 : 0
                                    color: "transparent"
                                    visible: panelPreviewImg.opacity > 0.01

                                    Image {
                                        id: panelPreviewImg
                                        anchors.fill: parent
                                        source: (root._previewDisplayMode === "image" || root._previewDisplayMode === "video") ? root._previewMediaSource : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        sourceSize: Qt.size(512, 512)
                                        opacity: status === Image.Ready ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Flickable {
                                    id: panelTextFlick
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    visible: root._previewDisplayMode === "text" && root._previewText !== ""
                                    contentWidth: width
                                    contentHeight: panelPreviewText.implicitHeight
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    Text {
                                        id: panelPreviewText
                                        width: panelTextFlick.width
                                        text: root._previewText
                                        color: Theme.text
                                        font.family: Theme.fontMono; font.pixelSize: 11
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    opacity: (panelPreviewImg.status === Image.Ready || (root._previewDisplayMode === "text" && root._previewText !== "")) ? 0.0 : 1.0
                                    visible: opacity > 0.01
                                    sourceName: root._previewDisplayItem ? root.iconFor(root._previewDisplayItem.type) : "file"
                                    iconSize: 44
                                    color: root._previewDisplayItem ? root.iconColorFor(root._previewDisplayItem.type) : Theme.textSub
                                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: previewCanvasMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !root.isPicker && root._previewDisplayItem !== null
                                        && (root._previewDisplayItem.type === "image" || root._previewDisplayItem.type === "video")
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.openMediaViewer(root._previewDisplayItem)
                                }
                            }

                            // File Name & Meta
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root._previewDisplayItem ? root._previewDisplayItem.name : ""
                                color: Theme.text
                                font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Type"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Text {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; horizontalAlignment: Text.AlignRight
                                        text: root._previewDisplayLabel
                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Size"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Text {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; horizontalAlignment: Text.AlignRight
                                        text: root._previewDisplayItem ? FileService.formatSize(root._previewDisplayItem.size) : ""
                                        color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Modified"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Text {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; horizontalAlignment: Text.AlignRight
                                        text: root._previewDisplayItem ? FileService.formatDate(root._previewDisplayItem.mtime) : ""
                                        color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight
                                    }
                                }
                            }

                            Item { Layout.fillHeight: !(root._previewDisplayMode === "text" && root._previewText !== "") }
                        }
                    }
                }
                }

                // Bottom Tab Bar (auto-hides when <= 1 tab)
                Item {
                    readonly property bool showTabs: !root.isPicker && tabsModel.count > 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: showTabs ? 30 : 0
                    opacity: showTabs ? 1.0 : 0.0
                    visible: Layout.preferredHeight > 1 || opacity > 0.01
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 30
                        spacing: 5

                        ListView {
                            id: tabList
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 30
                            orientation: ListView.Horizontal
                            spacing: 4
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: tabsModel

                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; to: 0.90; duration: 150; easing.type: Easing.OutCubic }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "x"; duration: 200; easing.type: Easing.OutCubic }
                            }

                            WheelHandler {
                                enabled: !root.anyModalOpen && tabList.contentWidth > tabList.width
                                onWheel: (event) => {
                                    const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                                    const maxX = Math.max(0, tabList.contentWidth - tabList.width);
                                    tabList.contentX = Math.max(0, Math.min(maxX, tabList.contentX - delta * 0.5));
                                }
                            }

                            delegate: Rectangle {
                                id: tabPill
                                required property int index
                                required property int tabId
                                required property string label
                                required property string icon

                                readonly property bool isActive: index === root.activeTabIndex
                                readonly property bool showClose: tabsModel.count > 1 && (isActive || tabMouse.containsMouse || closeTabMouse.containsMouse)

                                height: 30
                                width: Math.max(104, Math.floor((tabList.width - Math.max(0, tabsModel.count - 1) * tabList.spacing) / Math.max(1, tabsModel.count)))
                                radius: 8
                                clip: true
                                color: isActive ? Theme.surfaceRaised : (tabMouse.containsMouse ? Theme.cardBg : "transparent")
                                border.width: 1
                                border.color: isActive
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                                    : (tabMouse.containsMouse ? Theme.borderSubtle : "transparent")
                                scale: tabMouse.pressed ? 0.96 : 1.0

                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.MiddleButton) {
                                            if (tabsModel.count > 1) root.closeTab(tabPill.index);
                                        } else if (mouse.button === Qt.RightButton) {
                                            root.openTabContextMenu(tabPill, mouse, tabPill.index);
                                        } else {
                                            root.switchTab(tabPill.index);
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    SvgIcon {
                                        sourceName: tabPill.icon || "folder"
                                        iconSize: 12
                                        color: tabPill.isActive ? Theme.accent : Theme.textMuted
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: tabPill.label
                                        color: tabPill.isActive ? Theme.text : Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: tabPill.isActive ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        radius: 5
                                        clip: true
                                        opacity: tabPill.showClose ? 1.0 : 0.0
                                        color: closeTabMouse.containsMouse ? Theme.cardHover : "transparent"
                                        scale: closeTabMouse.pressed ? 0.88 : 1.0

                                        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: "close"
                                            iconSize: 10
                                            color: closeTabMouse.containsMouse ? Theme.text : Theme.textMuted
                                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            id: closeTabMouse
                                            anchors.fill: parent
                                            enabled: tabsModel.count > 1
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeTab(tabPill.index)
                                        }
                                    }
                                }
                            }
                        }

                        PillButton {
                            iconName: "plus"; iconSize: 13
                            fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                            onClicked: root.openTab(root.currentPath, "", true)
                        }
                    }
                }

                // Footer Divider
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Bottom Status Bar (Manager Mode)
                RowLayout {
                    visible: !root.isPicker
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: {
                            if (root.archiverActive) {
                                if (root.archiverLoading) return "Reading " + root.archiverArchiveName + "...";
                                if (root.archiverError !== "") return root.archiverError;
                                const total = (root.archiverEntries || []).length;
                                const shown = (root.filteredArchiveEntries || []).length;
                                return (shown !== total ? (shown + " of " + total) : total) + (total === 1 ? " entry" : " entries") + " inside " + root.archiverArchiveName;
                            }
                            if (root.isLoading) return "Loading...";
                            if (root.selectedPaths.length > 0) {
                                const bytesStr = root.selectedTotalBytes();
                                return root.selectedPaths.length + (root.selectedPaths.length === 1 ? " item selected" : " items selected") + (bytesStr !== "" ? (" (" + bytesStr + ")") : "");
                            }
                            return root.statusMessage || (root.visibleItems.length + " items");
                        }
                        color: root.selectedPaths.length > 0 ? Theme.text : Theme.textSub
                        font.family: Theme.fontSans; font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.diskInfo
                        color: Theme.textSub
                        font.family: Theme.fontMono; font.pixelSize: 11
                    }
                }

                // Bottom Picker Footer (Picker Mode)
                ColumnLayout {
                    visible: root.isPicker
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: root.pickerDirectory ? "Folder:" : "Name:"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true; height: 32; radius: 8
                            color: nameField.activeFocus ? Theme.surfaceRaised : Theme.cardBg
                            border.width: 1
                            border.color: nameField.activeFocus ? Theme.accent : Theme.borderSubtle
                            Behavior on border.color { ColorAnimation { duration: 140 } }
                            Behavior on color { ColorAnimation { duration: 140 } }

                            AnimatedTextInput {
                                id: nameField
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                textColor: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; clip: true
                                Keys.onReturnPressed: if (root.canPickerSubmit) root.submitPicker()
                                Keys.onEscapePressed: (event) => {
                                    root.forceActiveFocus();
                                    event.accepted = true;
                                }
                                Text {
                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                    text: root.pickerDirectory ? ("Current: " + root.displayPath(root.currentPath)) : "Select a file or type filename..."
                                    color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11
                                    opacity: (nameField.text === "" && nameField.preeditText === "") ? 1.0 : 0.0
                                    visible: opacity > 0.01
                                    elide: Text.ElideRight
                                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: !root.pickerDirectory
                        Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "File type:"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12 }

                        // Sleek Filter Dropdown (matches SettingsView CtrlSelect)
                        Rectangle {
                            id: filterSelectBtn
                            Layout.fillWidth: true
                            height: 30; radius: 8
                            color: filterSelMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                            border.width: 1
                            border.color: filterSelMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4) : Theme.borderSubtle
                            scale: filterSelMouse.pressed ? 0.99 : 1.0
                            Behavior on color { ColorAnimation { duration: 130 } }
                            Behavior on border.color { ColorAnimation { duration: 130 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: root.activeFilterLabel
                                    color: Theme.text
                                    font.family: Theme.fontSans; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 12; color: Theme.textSub
                                    rotation: root.filterMenuOpen ? 270 : 90
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                id: filterSelMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.openFilterMenu(filterSelectBtn)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: {
                                const prefix = root.isLoading ? "Loading..." : (root.visibleItems.length + (root.visibleItems.length === 1 ? " item" : " items"));
                                const selTxt = root.selectedPaths.length > 1 ? (" • " + root.selectedPaths.length + " selected") : "";
                                return prefix + selTxt + " • " + root.displayPath(root.currentPath);
                            }
                            color: Theme.textSub
                            font.family: Theme.fontSans; font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                        PillButton {
                            text: "Cancel"
                            iconName: "close"; iconSize: 12
                            onClicked: root.pickerCancelled()
                        }
                        PillButton {
                            text: root.pickerAcceptLabel !== ""
                                ? root.pickerAcceptLabel
                                : (root.pickerDirectory ? "Select Folder" : (root.pickerActionMode === "download" ? "Save" : "Open"))
                            iconName: "check"; iconSize: 13
                            active: root.canPickerSubmit
                            enabled: root.canPickerSubmit
                            onClicked: root.submitPicker()
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Hoisted Animated Modals (z: 80 — covers BOTH Sidebar & Main Content Pane)
    // =========================================================================

    // 1. Password Modal for Encrypted Archives
    Rectangle {
        id: pwdOverlay
        visible: root.passwordOpen || opacity > 0.01
        anchors.fill: parent
        bottomLeftRadius: root._appBottomRadius
        bottomRightRadius: root._appBottomRadius
        topLeftRadius: root._appTopRadius
        topRightRadius: root._appTopRadius
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: root.passwordOpen ? 1.0 : 0.0
        z: 80
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: root.passwordOpen
            onClicked: {
                root.passwordOpen = false;
                root.forceActiveFocus();
            }
        }

        Rectangle {
            id: pwdBox
            width: Math.min(350, parent.width - 32); height: 204; radius: 14
            anchors.centerIn: parent
            color: Theme.surfaceBg
            border.width: 1; border.color: Theme.borderSubtle
            clip: true
            scale: root.passwordOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }

            ThemeGradientFill {
                anchors.fill: parent
                anchors.margins: 1
                enabled: Theme.effectiveSurfaceGradient
                color1: Theme.surfaceBg
                colorMid: Theme.surfaceBgMid
                color2: Theme.surfaceBg2
                cornerRadius: 13
            }

            MouseArea { anchors.fill: parent; onClicked: (m) => { m.accepted = true; } }

            SequentialAnimation {
                id: pwdShake
                NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 45 }
                NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: 8; duration: 45 }
                NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: -6; duration: 45 }
                NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 10
                Text { text: "Encrypted Archive"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold }
                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Enter password for " + root.passwordTargetName; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 8
                    color: Theme.cardBg; border.width: 1
                    border.color: passwordField.activeFocus ? Theme.accent : Theme.borderSubtle
                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    AnimatedTextInput {
                        id: passwordField
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        textColor: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; clip: true
                        Keys.onReturnPressed: root.submitPassword()
                        Keys.onEscapePressed: (event) => {
                            root.passwordOpen = false;
                            root.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                }
                Text {
                    opacity: root.passwordError !== "" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.passwordError
                    color: Theme.dangerText
                    font.family: Theme.fontSans; font.pixelSize: 11
                    elide: Text.ElideRight
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Item { Layout.fillWidth: true }
                    PillButton { text: "Cancel"; onClicked: { root.passwordOpen = false; root.forceActiveFocus(); } }
                    PillButton { text: "Extract"; active: true; onClicked: root.submitPassword() }
                }
            }
        }
    }

    // 2. Input Modal (New Folder / New File / Rename)
    Rectangle {
        id: inputOverlay
        visible: root.inputModalOpen || opacity > 0.01
        anchors.fill: parent
        bottomLeftRadius: root._appBottomRadius
        bottomRightRadius: root._appBottomRadius
        topLeftRadius: root._appTopRadius
        topRightRadius: root._appTopRadius
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: root.inputModalOpen ? 1.0 : 0.0
        z: 81
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: root.inputModalOpen
            onClicked: {
                root.inputModalOpen = false;
                root.forceActiveFocus();
            }
        }

        Rectangle {
            id: inputBox
            width: Math.min(350, parent.width - 32)
            height: root.inputModalError !== "" ? 186 : 164
            radius: 14
            anchors.centerIn: parent
            color: Theme.surfaceBg
            border.width: 1; border.color: Theme.borderSubtle
            clip: true
            scale: root.inputModalOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ThemeGradientFill {
                anchors.fill: parent
                anchors.margins: 1
                enabled: Theme.effectiveSurfaceGradient
                color1: Theme.surfaceBg
                colorMid: Theme.surfaceBgMid
                color2: Theme.surfaceBg2
                cornerRadius: 13
            }

            MouseArea { anchors.fill: parent; onClicked: (m) => { m.accepted = true; } }

            SequentialAnimation {
                id: inputShake
                NumberAnimation { target: inputBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 45 }
                NumberAnimation { target: inputBox; property: "anchors.horizontalCenterOffset"; to: 8; duration: 45 }
                NumberAnimation { target: inputBox; property: "anchors.horizontalCenterOffset"; to: -6; duration: 45 }
                NumberAnimation { target: inputBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 10
                Text { text: root.inputModalTitle; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold }
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 8
                    color: Theme.cardBg; border.width: 1
                    border.color: root.inputModalError !== "" ? Theme.danger : (modalTextField.activeFocus ? Theme.accent : Theme.borderSubtle)
                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    AnimatedTextInput {
                        id: modalTextField
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        textColor: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; clip: true
                        onTextChanged: if (root.inputModalError !== "") root.inputModalError = ""
                        Keys.onReturnPressed: root.submitInputModal()
                        Keys.onEscapePressed: (event) => {
                            root.inputModalOpen = false;
                            root.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                }
                Text {
                    opacity: root.inputModalError !== "" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.inputModalError
                    color: Theme.dangerText
                    font.family: Theme.fontSans; font.pixelSize: 11
                    elide: Text.ElideRight
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Item { Layout.fillWidth: true }
                    PillButton { text: "Cancel"; onClicked: { root.inputModalOpen = false; root.forceActiveFocus(); } }
                    PillButton { text: "Confirm"; active: true; onClicked: root.submitInputModal() }
                }
            }
        }
    }

    // 3. Confirm Delete / Empty Trash / Overwrite Modal
    Rectangle {
        id: confirmOverlay
        visible: root.confirmOpen || opacity > 0.01
        anchors.fill: parent
        bottomLeftRadius: root._appBottomRadius
        bottomRightRadius: root._appBottomRadius
        topLeftRadius: root._appTopRadius
        topRightRadius: root._appTopRadius
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: root.confirmOpen ? 1.0 : 0.0
        z: 82
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Keys.onPressed: (event) => {
            if (!root.confirmOpen) return;
            if (event.key === Qt.Key_Escape) {
                root.confirmOpen = false;
                root.forceActiveFocus();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.executeConfirm();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.confirmOpen
            onClicked: {
                root.confirmOpen = false;
                root.forceActiveFocus();
            }
        }

        Rectangle {
            width: Math.min(368, parent.width - 32); height: 174; radius: 14
            anchors.centerIn: parent
            color: Theme.surfaceBg
            border.width: 1; border.color: Theme.borderSubtle
            clip: true
            scale: root.confirmOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }

            ThemeGradientFill {
                anchors.fill: parent
                anchors.margins: 1
                enabled: Theme.effectiveSurfaceGradient
                color1: Theme.surfaceBg
                colorMid: Theme.surfaceBgMid
                color2: Theme.surfaceBg2
                cornerRadius: 13
            }

            MouseArea { anchors.fill: parent; onClicked: (m) => { m.accepted = true; } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 8
                Text { text: root.confirmTitle; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold }
                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.confirmLabel; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.confirmSub; color: (root.confirmMode === "permanent" || root.confirmMode === "empty_trash") ? Theme.dangerText : Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Item { Layout.fillWidth: true }
                    PillButton { text: "Cancel"; onClicked: { root.confirmOpen = false; root.forceActiveFocus(); } }
                    PillButton {
                        readonly property bool isDestructive: root.confirmMode === "permanent" || root.confirmMode === "empty_trash" || root.confirmMode === "overwrite"
                        text: root.confirmMode === "empty_trash" ? "Empty Trash" : (root.confirmMode === "permanent" ? "Delete" : (root.confirmMode === "overwrite" ? "Replace" : "Move to Trash"))
                        danger: isDestructive
                        active: true
                        onClicked: root.executeConfirm()
                    }
                }
            }
        }
    }

    // 4. Properties Modal
    Rectangle {
        id: propsOverlay
        visible: root.propsOpen || opacity > 0.01
        anchors.fill: parent
        bottomLeftRadius: root._appBottomRadius
        bottomRightRadius: root._appBottomRadius
        topLeftRadius: root._appTopRadius
        topRightRadius: root._appTopRadius
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: root.propsOpen ? 1.0 : 0.0
        z: 83
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Keys.onPressed: (event) => {
            if (!root.propsOpen) return;
            if (event.key === Qt.Key_Escape) {
                root.propsOpen = false;
                root.forceActiveFocus();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.propsOpen
            onClicked: {
                root.propsOpen = false;
                root.forceActiveFocus();
            }
        }

        Rectangle {
            width: Math.min(390, parent.width - 32); height: 278; radius: 14
            anchors.centerIn: parent
            color: Theme.surfaceBg
            border.width: 1; border.color: Theme.borderSubtle
            clip: true
            scale: root.propsOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }

            ThemeGradientFill {
                anchors.fill: parent
                anchors.margins: 1
                enabled: Theme.effectiveSurfaceGradient
                color1: Theme.surfaceBg
                colorMid: Theme.surfaceBgMid
                color2: Theme.surfaceBg2
                cornerRadius: 13
            }

            MouseArea { anchors.fill: parent; onClicked: (m) => { m.accepted = true; } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 10

                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Rectangle {
                        width: 32; height: 32; radius: 9
                        color: Theme.cardBg
                        border.width: 1; border.color: Theme.borderSubtle
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: (root.propsData && root.propsData.isDir) ? "folder" : "info"
                            iconSize: 16
                            color: Theme.accent
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsName; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.displayPath(root.propsPath); color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideMiddle }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 7

                    Text { text: "Type"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsData ? root.propsData.kind : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Size"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsData ? root.propsData.size : "..."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Owner"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsData ? root.propsData.owner : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Permissions"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsData ? root.propsData.permissions : "..."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Modified"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.propsData ? root.propsData.modified : "..."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    PillButton {
                        visible: root.propsData !== null && !root.propsData.isDir
                        text: (root.propsData && root.propsData.executable) ? "Remove +x" : "Make +x"
                        fontSize: 11; horizontalPadding: 10; verticalPadding: 5; radius: 8
                        onClicked: {
                            const nextExec = !(root.propsData && root.propsData.executable);
                            FileService.setExecutable(root.propsPath, nextExec, () => {
                                FileService.getProperties(root.propsPath, (ok, data) => { if (root && ok) root.propsData = data; });
                            });
                        }
                    }
                    PillButton {
                        text: "Copy Path"
                        iconName: "link"; iconSize: 12
                        fontSize: 11; horizontalPadding: 10; verticalPadding: 5; radius: 8
                        onClicked: {
                            FileService.copyToClipboard(root.propsPath);
                            root.statusMessage = "Path copied to clipboard";
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PillButton { text: "Close"; active: true; onClicked: { root.propsOpen = false; root.forceActiveFocus(); } }
                }
            }
        }
    }

    // Built-in Image Viewer & Video Watcher (z: 85 — root-hoisted, lazy-loaded)
    Loader {
        id: mediaViewerLoader
        anchors.fill: parent
        z: 85
        active: root.viewerOpen || (item !== null && item.opacity > 0.01)
        source: "MediaViewerOverlay.qml"
        onLoaded: {
            if (item) {
                item.open = Qt.binding(() => root.viewerOpen);
                item.item = Qt.binding(() => root.viewerItem);
                item.currentIndex = Qt.binding(() => root.viewerIndex);
                item.totalCount = Qt.binding(() => root.viewerItems ? root.viewerItems.length : 0);
                item.stepDir = Qt.binding(() => root.viewerStepDir);
                item.topRadius = Qt.binding(() => root._appTopRadius);
                item.bottomRadius = Qt.binding(() => root._appBottomRadius);
                item.closeRequested.connect(() => root.closeMediaViewer());
                item.stepRequested.connect((delta) => root.stepMediaViewer(delta));
                item.openExternalRequested.connect((path) => FileService.openFile(path));
                if (root.viewerOpen) item.forceActiveFocus();
            }
        }
    }

    ContextMenu {
        id: ctxMenu
        onClosed: {
            root.filterMenuOpen = false;
            root.forceActiveFocus();
        }
    }
}
