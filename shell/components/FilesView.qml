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
    property bool isLoading: false
    property int _navSeq: 0

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
    property string archiverArchivePath: ""
    property string archiverArchiveName: ""
    property var archiverEntries: []
    property string archiverStatus: ""

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

    readonly property bool isInTrash: virtualMode === "" && (currentPath === FileService.trashDir || currentPath.startsWith(FileService.trashDir + "/"))
    readonly property bool anyModalOpen: passwordOpen || inputModalOpen || confirmOpen || propsOpen

    readonly property var libraryItems: [
        { key: "recent", label: "Recent", icon: "clock" },
        { key: "starred", label: "Starred", icon: "star" }
    ]

    readonly property var breadcrumbSegments: {
        if (virtualMode === "recent") return [{ label: "Recent Files", path: "", clickable: false }];
        if (virtualMode === "starred") return [{ label: "Starred Items", path: "", clickable: false }];
        if (currentPath === FileService.trashDir) return [{ label: "Trash", path: FileService.trashDir, clickable: true }];

        const segs = [];
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

    property string _lastModelContext: ""
    property bool _transitionsEnabled: false

    Timer {
        id: animEnableTimer
        interval: 480
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
        const ctx = virtualMode + "::" + currentPath + "::" + (isListView ? "list" : "grid");
        if (_lastModelContext !== ctx || (viewModel.count === 0 && nextList.length > 0)) {
            _lastModelContext = ctx;
            _transitionsEnabled = false;
            viewModel.clear();
            for (let i = 0; i < nextList.length; ++i) {
                viewModel.append(_toRowObj(nextList[i]));
            }
            animEnableTimer.interval = 480;
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
            if (!ok) {
                root.currentItems = [];
                root.loadError = err || "Cannot open directory";
                root.statusMessage = root.loadError;
                return;
            }
            root.loadError = "";
            root.currentItems = items;
            root.statusMessage = items.length + (items.length === 1 ? " item" : " items");
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
        isDeepSearch = false;
        loadError = "";
        isLoading = true;
        selectedPaths = [];
        lastSelectedIdx = -1;
        if (isPicker && pickerDirectory) nameField.text = "";
        FileService.listRecent((ok, items) => {
            if (!root || seq !== root._navSeq) return;
            isLoading = false;
            currentItems = items || [];
            statusMessage = currentItems.length + " recent files";
        });
    }

    function loadStarred() {
        ++_navSeq;
        virtualMode = "starred";
        isDeepSearch = false;
        loadError = "";
        isLoading = false;
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
        statusMessage = out.length + " starred items";
    }

    function runDeepSearch() {
        const q = searchField.text.trim();
        if (virtualMode !== "" || q === "") return;
        const seq = ++_navSeq;
        isLoading = true;
        loadError = "";
        isDeepSearch = true;
        FileService.searchFiles(currentPath, q, showHidden, (ok, items, err) => {
            if (!root || seq !== root._navSeq) return;
            isLoading = false;
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
        if (!isPicker) FileService.lastPath = target;
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
            selectedPaths = next;
            lastSelectedIdx = index;
        } else {
            selectedPaths = [item.path];
            lastSelectedIdx = index;
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
            selectedPaths = [item.path];
            lastSelectedIdx = index;
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
            if (!isPicker) FileService.lastPath = currentPath;
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
            if (!isPicker) FileService.lastPath = currentPath;
            refreshCurrent();
        }
    }

    function goUp() {
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
        } else {
            FileService.openFile(item.path);
        }
    }

    function openArchiveInspector(item) {
        archiverArchivePath = item.path;
        archiverArchiveName = item.name;
        archiverStatus = "Reading archive...";
        archiverEntries = [];
        archiverActive = true;
        FileService.inspectArchive(item.path, (ok, entries, err) => {
            if (!ok) {
                archiverStatus = err || "Unable to list archive (may be encrypted)";
                return;
            }
            archiverEntries = entries;
            archiverStatus = entries.length + " entries inside " + item.name;
        });
    }

    function beginExtract(archivePath, archiveName, password) {
        startTransfer("Extracting " + archiveName, "To " + displayPath(currentPath), "", 0);
        FileService.extractArchive(archivePath, currentPath, password || "", (ok, outDir, errText, needsPwd) => {
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
            startTransfer((isCut ? "Moving " : "Copying ") + paths.length + " item(s)", "To " + displayPath(dest), dest, totalBytes);
            const doneCb = (ok, err) => {
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
                if (!ok) statusMessage = err || "Failed to empty Trash";
                else statusMessage = "Trash emptied";
                refreshCurrent();
            });
            return;
        }
        const permanent = (mode === "permanent");
        FileService.deleteItems(paths, permanent, (ok, err) => {
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
                menu.push({ text: sel.type === "archive" ? "Inspect Archive" : "Open", iconName: "external-link", shortcut: "Enter", action: () => openItem(sel) });
                if (sel.type === "folder") {
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

    Component.onCompleted: {
        libraryOpen = !isPicker;
        isListView = FileService.prefListView;
        showHidden = FileService.prefShowHidden;
        sortBy = FileService.prefSortBy;
        sortAsc = FileService.prefSortAsc;
        if (!isPicker) {
            const start = FileService.lastPath || FileService.homeDir;
            currentPath = start;
            history = [start];
            historyIdx = 0;
            refreshCurrent();
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
        } else if (ctrl && event.key === Qt.Key_L && virtualMode === "") {
            pathField.text = currentPath;
            pathEditing = true;
            pathField.forceActiveFocus();
            pathField.selectAll();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_F) {
            searchField.forceActiveFocus();
            searchField.selectAll();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_H) {
            showHidden = !showHidden;
            FileService.setHiddenPref(showHidden);
            refreshCurrent();
            event.accepted = true;
        } else if (ctrl && shift && event.key === Qt.Key_N && virtualMode === "" && !isInTrash) {
            openInputModal("mkdir", "New Folder", "New Folder", "");
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_N && !isPicker && virtualMode === "" && !isInTrash) {
            openInputModal("mkfile", "New File", "untitled.txt", "");
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_A && (!isPicker || pickerMultiple)) {
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
                        Text { Layout.fillWidth: true; text: root.isPicker ? root.pickerTitle : "Files"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: root.isPicker ? root.pickerSubtitle : "Linux • Coreutils"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
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
                        }

                        AnimatedTextInput {
                            id: searchField
                            Layout.fillWidth: true
                            textColor: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: {
                                root.searchQuery = text;
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
                                visible: searchField.text === ""
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: root.isDeepSearch
                            width: deepLbl.implicitWidth + 8
                            height: 17; radius: 5
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
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
                            visible: searchField.text !== ""
                            width: 18; height: 18; radius: 6
                            color: clrSearchMouse.containsMouse ? Theme.cardHover : "transparent"
                            scale: clrSearchMouse.pressed ? 0.9 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            SvgIcon { anchors.centerIn: parent; sourceName: "close"; iconSize: 10; color: Theme.textSub }
                            MouseArea {
                                id: clrSearchMouse
                                anchors.fill: parent
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
                                Text { Layout.fillWidth: true; text: "Places"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
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
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans; font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: pMouse
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(modelData.path)
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
                                Text { Layout.fillWidth: true; text: "Library"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
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
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans; font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
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
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.key === "recent") root.loadRecent();
                                                else root.loadStarred();
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
                                SvgIcon { sourceName: "hard-drive"; iconSize: 14; color: rootNavItem.isActive ? Theme.accent : Theme.textSub }
                                Text {
                                    Layout.fillWidth: true
                                    text: "/ (Root)"
                                    color: rootNavItem.isActive ? Theme.text : Theme.textSub
                                    font.family: Theme.fontSans; font.pixelSize: 13
                                    font.weight: rootNavItem.isActive ? Font.DemiBold : Font.Normal
                                }
                            }
                            MouseArea {
                                id: rootMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.navigateTo("/")
                            }
                        }
                    }
                }

                // Transfer Progress Card
                Rectangle {
                    id: transferBox
                    visible: !root.isPicker && (root.transferActive || opacity > 0.01)
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
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: root.transferLabel; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight }
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

                        Text { Layout.fillWidth: true; text: root.transferSub; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; elide: Text.ElideRight }
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
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
                            Text { text: "PORTAL MODE"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                        }
                        Text {
                            Layout.fillWidth: true
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
                        enabled: root.virtualMode !== "" || root.currentPath !== "/"
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
                        height: 30; radius: 9
                        color: root.pathEditing ? Theme.surfaceRaised : Theme.cardBg
                        border.width: 1
                        border.color: root.pathEditing ? Theme.accent : Theme.borderSubtle
                        clip: true
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        MouseArea {
                            anchors.fill: parent
                            visible: !root.pathEditing && root.virtualMode === ""
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                pathField.text = root.currentPath;
                                root.pathEditing = true;
                                pathField.forceActiveFocus();
                                pathField.selectAll();
                            }
                        }

                        Row {
                            visible: !root.pathEditing
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            spacing: 2

                            Repeater {
                                model: root.breadcrumbSegments
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: 2

                                    Text {
                                        visible: index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "›"
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                    }

                                    Rectangle {
                                        height: 22
                                        width: Math.min(160, segText.implicitWidth + 12)
                                        radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: (modelData.clickable && segMouse.containsMouse) ? Theme.cardHover : "transparent"
                                        scale: (modelData.clickable && segMouse.pressed) ? 0.95 : 1.0
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                                        Text {
                                            id: segText
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, parent.width - 10)
                                            text: modelData.label
                                            color: index === root.breadcrumbSegments.length - 1 ? Theme.text : Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 12
                                            font.weight: index === root.breadcrumbSegments.length - 1 ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideMiddle
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
                        }

                        AnimatedTextInput {
                            id: pathField
                            visible: root.pathEditing
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            textColor: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            clip: true
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
                        iconName: "sort"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openSortMenu(sortBtn)
                    }

                    PillButton {
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
                        visible: root.isInTrash && !root.isPicker
                        iconName: "trash"; iconSize: 13
                        text: "Empty"
                        fontSize: 11; horizontalPadding: 9; verticalPadding: 5; radius: 8
                        danger: true
                        enabled: (root.currentItems || []).length > 0
                        onClicked: root.requestEmptyTrash()
                    }

                    PillButton {
                        visible: root.virtualMode === "" && !root.isInTrash
                        iconName: "folder-plus"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openInputModal("mkdir", "New Folder", "New Folder", "")
                    }

                    PillButton {
                        visible: !root.isPicker && root.virtualMode === "" && !root.isInTrash
                        iconName: "file-plus"; iconSize: 14
                        fixedWidth: 30; fixedHeight: 30; radius: 8; subtle: true
                        onClicked: root.openInputModal("mkfile", "New File", "untitled.txt", "")
                    }

                    // Segmented View Mode Control (Grid | List)
                    Rectangle {
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
                                    color: !root.isListView ? Theme.accent : Theme.textMuted
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
                                    color: root.isListView ? Theme.accent : Theme.textMuted
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
                    readonly property bool showClip: !root.isPicker && FileService.clipboardPaths.length > 0 && root.virtualMode === "" && !root.isInTrash
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
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8; spacing: 8
                        SvgIcon {
                            sourceName: FileService.clipboardMode === "cut" ? "scissors" : "copy"
                            iconSize: 14; color: Theme.accent
                        }
                        Text {
                            Layout.fillWidth: true
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

                // Animated Inline Archiver Bar
                Rectangle {
                    visible: Layout.preferredHeight > 1 || opacity > 0.01
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.archiverActive ? 164 : 0
                    opacity: root.archiverActive ? 1.0 : 0.0
                    radius: 12
                    color: Theme.surfaceRaised
                    border.width: root.archiverActive ? 1 : 0
                    border.color: Theme.borderSubtle
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 170 } }

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            SvgIcon { sourceName: "archive"; iconSize: 16; color: Theme.accent }
                            Text { Layout.fillWidth: true; text: root.archiverArchiveName + " — " + root.archiverStatus; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            PillButton {
                                text: "Extract Here"
                                iconName: "extract"; iconSize: 12
                                fontSize: 11; horizontalPadding: 10; verticalPadding: 4; radius: 8
                                active: true
                                onClicked: root.beginExtract(root.archiverArchivePath, root.archiverArchiveName, "")
                            }
                            PillButton {
                                iconName: "close"; iconSize: 12
                                fixedWidth: 26; fixedHeight: 26; radius: 7; subtle: true
                                onClicked: root.archiverActive = false
                            }
                        }

                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; spacing: 4
                            model: root.archiverEntries
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width; height: 26; radius: 6
                                color: Theme.cardBg
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    SvgIcon { sourceName: root.iconFor(modelData.type); iconSize: 13; color: root.iconColorFor(modelData.type) }
                                    Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                                    Text { text: modelData.meta; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                // Virtualized Grid / List File Viewport
                Item {
                    id: filesViewport
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    property real _selStartX: 0
                    property real _selStartY: 0
                    property bool _selMoved: false
                    property var _selBasePaths: []

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
                                const iy = row * ch - cy;
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
                            const iw = filesList.width - 6;
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
                        acceptedButtons: Qt.RightButton | Qt.LeftButton
                        onPressed: (mouse) => {
                            root.forceActiveFocus();
                            if (mouse.button === Qt.LeftButton && (!root.isPicker || root.pickerMultiple)) {
                                filesViewport._selStartX = mouse.x;
                                filesViewport._selStartY = mouse.y;
                                filesViewport._selMoved = false;
                                const additive = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
                                filesViewport._selBasePaths = additive ? root.selectedPaths.slice() : [];
                                marqueeRect.x = mouse.x;
                                marqueeRect.y = mouse.y;
                                marqueeRect.width = 0;
                                marqueeRect.height = 0;
                            }
                        }
                        onPositionChanged: (mouse) => {
                            if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return;
                            if (root.isPicker && !root.pickerMultiple) return;
                            const dist = Math.hypot(mouse.x - filesViewport._selStartX, mouse.y - filesViewport._selStartY);
                            if (dist > 6) {
                                filesViewport._selMoved = true;
                                marqueeRect.visible = true;
                                const rx = Math.min(filesViewport._selStartX, mouse.x);
                                const ry = Math.min(filesViewport._selStartY, mouse.y);
                                const rw = Math.abs(mouse.x - filesViewport._selStartX);
                                const rh = Math.abs(mouse.y - filesViewport._selStartY);
                                marqueeRect.x = rx;
                                marqueeRect.y = ry;
                                marqueeRect.width = rw;
                                marqueeRect.height = rh;
                                filesViewport.updateMarqueeSelection(rx, ry, rw, rh);
                            }
                        }
                        onReleased: (mouse) => {
                            marqueeRect.visible = false;
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
                        opacity: (!root.isLoading && root.visibleItems.length === 0) ? 1.0 : 0.0
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

                    // Virtualized Grid View (Balanced 4-col math + ScrollBar space)
                    GridView {
                        id: filesGrid
                        visible: !root.isListView
                        anchors.fill: parent
                        clip: true
                        interactive: false
                        reuseItems: true
                        cacheBuffer: 240
                        readonly property int cols: Math.max(2, Math.floor((width - 6) / 154))
                        cellWidth: Math.floor((width - 6) / cols)
                        cellHeight: 118
                        model: !root.isListView ? viewModel : emptyModel
                        onColsChanged: {
                            root._transitionsEnabled = false;
                            animEnableTimer.interval = 140;
                            animEnableTimer.restart();
                        }

                        WheelHandler {
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

                        add: root._transitionsEnabled ? gridAddTrans : null
                        remove: root._transitionsEnabled ? gridRemoveTrans : null
                        displaced: root._transitionsEnabled ? gridMoveTrans : null
                        move: root._transitionsEnabled ? gridMoveTrans : null

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

                            GridView.onReused: {
                                gridDelegate.opacity = 1.0;
                                gridDelegate.scale = 1.0;
                            }

                            Rectangle {
                                id: gridCard
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 6
                                anchors.bottomMargin: 10
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
                                    target: null
                                    acceptedButtons: Qt.LeftButton
                                    onActiveChanged: {
                                        if (root.shellState) root.shellState.externalFileDragging = active;
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
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 42; height: 42; radius: 11
                                        color: Qt.rgba(itemColor.r, itemColor.g, itemColor.b, 0.13)
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: root.iconFor(gridDelegate.type)
                                            iconSize: 22
                                            color: itemColor
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: gridDelegate.name
                                        color: Theme.text
                                        font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: gridDelegate.meta
                                        color: Theme.textSub
                                        font.family: Theme.fontSans; font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: gMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
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
                        visible: root.isListView
                        anchors.fill: parent
                        spacing: 4

                        // Column Header
                        Rectangle {
                            visible: root.visibleItems.length > 0
                            Layout.fillWidth: true
                            height: 24; radius: 6
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 16; spacing: 10

                                MouseArea {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("name")
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Text { text: "Name"; color: root.sortBy === "name" ? Theme.text : Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        Text { visible: root.sortBy === "name"; text: root.sortAsc ? "↑" : "↓"; color: Theme.accent; font.pixelSize: 10 }
                                    }
                                }

                                MouseArea {
                                    Layout.preferredWidth: 88; Layout.fillHeight: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("mtime")
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        Text { visible: root.sortBy === "mtime"; text: root.sortAsc ? "↑" : "↓"; color: Theme.accent; font.pixelSize: 10 }
                                        Text { text: "Modified"; color: root.sortBy === "mtime" ? Theme.text : Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold }
                                    }
                                }

                                MouseArea {
                                    Layout.preferredWidth: 72; Layout.fillHeight: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSortColumn("size")
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        Text { visible: root.sortBy === "size"; text: root.sortAsc ? "↑" : "↓"; color: Theme.accent; font.pixelSize: 10 }
                                        Text { text: "Size"; color: root.sortBy === "size" ? Theme.text : Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold }
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
                            reuseItems: true
                            cacheBuffer: 240
                            spacing: 3
                            model: root.isListView ? viewModel : emptyModel

                            WheelHandler {
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

                            add: root._transitionsEnabled ? listAddTrans : null
                            remove: root._transitionsEnabled ? listRemoveTrans : null
                            displaced: root._transitionsEnabled ? listMoveTrans : null
                            move: root._transitionsEnabled ? listMoveTrans : null

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

                            delegate: Rectangle {
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

                                width: Math.max(0, filesList.width - 6)
                                height: 36; radius: 8
                                opacity: isCut ? 0.46 : 1.0
                                color: isSel
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                    : (rowMouse.containsMouse ? Theme.cardHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035))
                                border.width: 1
                                border.color: isSel
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.52)
                                    : (rowMouse.containsMouse ? Theme.borderSubtle : "transparent")
                                scale: rowMouse.pressed ? 0.99 : 1.0

                                ListView.onReused: {
                                    listDelegate.opacity = listDelegate.isCut ? 0.46 : 1.0;
                                    listDelegate.scale = 1.0;
                                }

                                Drag.active: listDragHandler.active
                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.CopyAction
                                Drag.hotSpot: Qt.point(16, 16)
                                Drag.imageSource: Qt.resolvedUrl("../assets/icons/" + root.iconFor(listDelegate.type) + ".svg")
                                Drag.mimeData: root.buildDragMime(listDelegate.path)

                                Item {
                                    x: 0; y: 0; height: parent.height
                                    width: listDelegate.isSel ? parent.width : Math.min(parent.width - 176, 46 + listNameText.implicitWidth + 16)
                                    DragHandler {
                                        id: listDragHandler
                                        target: null
                                        acceptedButtons: Qt.LeftButton
                                        onActiveChanged: {
                                            if (root.shellState) root.shellState.externalFileDragging = active;
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

                                    SvgIcon {
                                        sourceName: root.iconFor(listDelegate.type)
                                        iconSize: 16
                                        color: itemColor
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
                                        font.family: Theme.fontSans; font.pixelSize: 11
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
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onPressed: (mouse) => {
                                        if (mouse.button === Qt.LeftButton && (!root.isPicker || root.pickerMultiple)) {
                                            const nameEnd = 46 + listNameText.implicitWidth + 16;
                                            if (mouse.x > nameEnd && !listDelegate.isSel) {
                                                mouse.accepted = false;
                                                return;
                                            }
                                        }
                                    }
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
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

                // Footer Divider
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Bottom Status Bar (Manager Mode)
                RowLayout {
                    visible: !root.isPicker
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: {
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
                                    visible: nameField.text === ""
                                    elide: Text.ElideRight
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
                                    text: root.activeFilterLabel
                                    color: Theme.text
                                    font.family: Theme.fontSans; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 12; color: Theme.textSub
                                    rotation: 90
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
                Text { Layout.fillWidth: true; text: "Enter password for " + root.passwordTargetName; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 8
                    color: Theme.cardBg; border.width: 1
                    border.color: passwordField.activeFocus ? Theme.accent : Theme.borderSubtle
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
                    visible: root.passwordError !== ""
                    text: root.passwordError
                    color: Theme.dangerText
                    font.family: Theme.fontSans; font.pixelSize: 11
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
                    visible: root.inputModalError !== ""
                    Layout.fillWidth: true
                    text: root.inputModalError
                    color: Theme.dangerText
                    font.family: Theme.fontSans; font.pixelSize: 11
                    elide: Text.ElideRight
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

            MouseArea { anchors.fill: parent; onClicked: (m) => { m.accepted = true; } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 8
                Text { text: root.confirmTitle; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold }
                Text { Layout.fillWidth: true; text: root.confirmLabel; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: root.confirmSub; color: (root.confirmMode === "permanent" || root.confirmMode === "empty_trash") ? Theme.dangerText : Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
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
                        Text { Layout.fillWidth: true; text: root.propsName; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: root.displayPath(root.propsPath); color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideMiddle }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 7

                    Text { text: "Type"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: root.propsData ? root.propsData.kind : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Size"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: root.propsData ? root.propsData.size : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Owner"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: root.propsData ? root.propsData.owner : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Permissions"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: root.propsData ? root.propsData.permissions : "..."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight }

                    Text { text: "Modified"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                    Text { Layout.fillWidth: true; text: root.propsData ? root.propsData.modified : "..."; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
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

    ContextMenu {
        id: ctxMenu
        onClosed: root.forceActiveFocus()
    }
}
