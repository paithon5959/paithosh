import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import ".."
import "common"
import "../services"

FocusScope {
    id: root
    required property var shellState

    implicitWidth: 880
    implicitHeight: 540

    // Local view state
    property bool libraryOpen: true
    property bool genresOpen: true
    property bool isListView: false
    property bool hintCopied: false
    property bool linkCopied: false
    property string prevSectionBeforeCreator: "discover"
    property string prevSectionBeforeSettings: "discover"
    property bool _settingsLoaded: MixcloudService.activeSection === "settings"

    // Paste Mixcloud URL modal state (root-hoisted)
    property bool urlModalOpen: false
    property bool urlModalBusy: false
    property string urlModalError: ""

    // Mix Details modal state (root-hoisted)
    property bool detailModalOpen: false
    property var detailTrack: null
    property string detailDescription: ""
    property bool detailLoading: false
    property bool detailLinkCopied: false

    readonly property bool anyModalOpen: urlModalOpen || detailModalOpen

    readonly property var activeListItems: {
        const sec = MixcloudService.activeSection;
        if (sec === "queue") return MixcloudService.queue || [];
        if (sec === "favorites") return MixcloudService.favorites || [];
        if (sec === "recent") return MixcloudService.recent || [];
        return MixcloudService.feedItems || [];
    }

    readonly property bool isFeedSection: {
        const s = MixcloudService.activeSection;
        return s === "discover" || s === "search" || s === "creator";
    }

    readonly property string sectionTitle: {
        const s = MixcloudService.activeSection;
        if (s === "settings") return "Music Settings";
        if (s === "queue") return "Up Next Queue";
        if (s === "favorites") return "Favorites";
        if (s === "recent") return "Recently Played";
        if (s === "search") return "Search • \"" + MixcloudService.searchQuery + "\"";
        if (s === "creator") return MixcloudService.creatorName || MixcloudService.creatorUsername || "Creator";
        return MixcloudService.genreLabel(MixcloudService.activeGenre);
    }

    Connections {
        target: MixcloudService
        function onActiveSectionChanged() {
            if (MixcloudService.activeSection === "settings") {
                root._settingsLoaded = true;
            }
        }
    }

    function openSettingsSection(tab) {
        if (MixcloudService.activeSection !== "settings") {
            root.prevSectionBeforeSettings = MixcloudService.activeSection || "discover";
        }
        if (tab && tab !== "") {
            MixcloudService.settingsTab = tab;
        }
        root._settingsLoaded = true;
        MixcloudService.activeSection = "settings";
    }

    readonly property string activeBannerText: {
        if (MixcloudService.errorMessage !== "") return MixcloudService.errorMessage;
        if (MixcloudService.feedError !== "") return MixcloudService.feedError;
        return "";
    }

    readonly property bool showDepsBanner: MixcloudService.depsChecked && !MixcloudService.depsReady
    readonly property bool showErrorBanner: activeBannerText !== ""

    Component.onCompleted: {
        isListView = MixcloudService.prefListView;
        MixcloudService.ensureBackend();
        if (MixcloudService.feedItems.length === 0 && !MixcloudService.feedLoading && MixcloudService.activeSection !== "settings") {
            MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
        }
    }

    Timer {
        id: copyResetTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.hintCopied = false;
            root.linkCopied = false;
            root.detailLinkCopied = false;
        }
    }

    function openUrlModal() {
        urlModalError = "";
        urlModalBusy = false;
        urlInput.text = "";
        urlModalOpen = true;
        Qt.callLater(() => { if (urlInput) urlInput.forceActiveFocus(); });
    }

    function closeUrlModal() {
        urlModalOpen = false;
        urlModalBusy = false;
        urlModalError = "";
        root.forceActiveFocus();
    }

    function triggerUrlShake(msg) {
        urlModalError = msg || "Invalid Mixcloud URL";
        urlShakeAnim.restart();
    }

    function submitUrlModal(playNow) {
        if (urlModalBusy) return;
        const raw = urlInput.text.trim();
        if (raw === "") {
            triggerUrlShake("Paste a Mixcloud show URL first");
            return;
        }
        urlModalBusy = true;
        urlModalError = "";
        MixcloudService.resolveAndFetchUrl(raw, (ok, item, err) => {
            urlModalBusy = false;
            if (!ok || !item) {
                triggerUrlShake(err || "Could not load Mixcloud show");
                return;
            }
            closeUrlModal();
            if (playNow) {
                MixcloudService.playTrack(item, null);
            } else {
                MixcloudService.enqueueTrack(item);
            }
        });
    }

    function openDetailModal(track) {
        if (!track) return;
        detailTrack = track;
        detailDescription = "";
        detailLinkCopied = false;
        detailLoading = true;
        detailModalOpen = true;
        detailOverlay.forceActiveFocus();
        const targetKey = track.key;
        MixcloudService.fetchShowDetail(targetKey, (ok, raw) => {
            if (!root.detailTrack || root.detailTrack.key !== targetKey) return;
            root.detailLoading = false;
            if (ok && raw && typeof raw.description === "string") {
                root.detailDescription = raw.description.trim();
            }
        });
    }

    function closeDetailModal() {
        detailModalOpen = false;
        root.forceActiveFocus();
    }

    function openCreatorSection(username, displayName) {
        if (!username) return;
        if (MixcloudService.activeSection !== "creator") {
            prevSectionBeforeCreator = MixcloudService.activeSection;
        }
        MixcloudService.loadCreator(username, displayName, false);
    }

    function submitSidebarSearch() {
        const q = searchField.text.trim();
        if (q === "") {
            MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
            return;
        }
        if (q.toLowerCase().indexOf("mixcloud.com/") !== -1) {
            MixcloudService.resolveAndFetchUrl(q, (ok, item, err) => {
                if (ok && item) {
                    searchField.text = "";
                    MixcloudService.playTrack(item, null);
                } else {
                    MixcloudService.feedError = err || "Invalid Mixcloud URL";
                }
            });
            return;
        }
        MixcloudService.searchShows(q, false);
    }

    function openTrackContextMenu(srcItem, mouse, track, indexInList) {
        if (!track) return;
        const pt = srcItem.mapToItem(root, mouse.x, mouse.y);
        const isFav = MixcloudService.isFavorite(track.key);
        const inQueueSec = MixcloudService.activeSection === "queue";
        const items = [
            {
                text: "Play Now",
                iconName: "play",
                action: () => inQueueSec
                    ? MixcloudService.playQueueAt(indexInList)
                    : MixcloudService.playTrack(track, root.activeListItems)
            },
            {
                text: "Play Next",
                iconName: "next",
                action: () => MixcloudService.playNextInQueue(track)
            },
            {
                text: inQueueSec ? "Remove from Queue" : "Add to Queue",
                iconName: inQueueSec ? "minus" : "plus",
                danger: inQueueSec,
                action: () => inQueueSec
                    ? MixcloudService.removeQueueAt(indexInList)
                    : MixcloudService.enqueueTrack(track)
            },
            { separator: true },
            {
                text: "Browse " + (track.artist || "Creator"),
                iconName: "globe",
                enabled: (track.username || "") !== "",
                action: () => root.openCreatorSection(track.username, track.artist)
            },
            {
                text: isFav ? "Remove Favorite" : "Add to Favorites",
                iconName: "star",
                action: () => MixcloudService.toggleFavorite(track)
            },
            {
                text: "Mix Details",
                iconName: "info",
                action: () => root.openDetailModal(track)
            },
            { separator: true },
            {
                text: "Copy Mixcloud Link",
                iconName: "link",
                action: () => FileService.copyToClipboard(track.url)
            },
            {
                text: "Open in Browser",
                iconName: "external-link",
                action: () => Quickshell.execDetached(["xdg-open", track.url])
            }
        ];
        ctxMenu.menuWidth = 228;
        ctxMenu.openAt(pt.x, pt.y, items);
    }

    Keys.onPressed: (event) => {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

        if (event.key === Qt.Key_Escape) {
            if (ctxMenu.isOpen) {
                ctxMenu.close();
                event.accepted = true;
                return;
            }
            if (urlModalOpen) {
                closeUrlModal();
                event.accepted = true;
                return;
            }
            if (detailModalOpen) {
                closeDetailModal();
                event.accepted = true;
                return;
            }
            if (searchField.activeFocus || searchField.text !== "") {
                searchField.text = "";
                root.forceActiveFocus();
                if (MixcloudService.activeSection === "search") {
                    MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                }
                event.accepted = true;
                return;
            }
            if (MixcloudService.activeSection === "settings") {
                const back = prevSectionBeforeSettings || "discover";
                if (back === "discover") {
                    MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                } else {
                    MixcloudService.activeSection = back;
                }
                event.accepted = true;
                return;
            }
            if (MixcloudService.activeSection === "creator") {
                const back = prevSectionBeforeCreator || "discover";
                if (back === "discover") {
                    MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                } else {
                    MixcloudService.activeSection = back;
                }
                event.accepted = true;
                return;
            }
            event.accepted = false;
            return;
        }

        if (anyModalOpen || ctxMenu.isOpen) return;

        if (ctrl && event.key === Qt.Key_F) {
            searchField.forceActiveFocus();
            searchField.selectAll();
            event.accepted = true;
            return;
        }
        if (ctrl && event.key === Qt.Key_L) {
            openUrlModal();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_F5 || (ctrl && event.key === Qt.Key_R)) {
            if (isFeedSection) MixcloudService.refreshFeed();
            event.accepted = true;
            return;
        }

        if (searchField.activeFocus || (settingsLoader.item && settingsLoader.item.inputFocused)) return;

        if (event.key === Qt.Key_Space) {
            MixcloudService.togglePlay();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            MixcloudService.seekTo(MixcloudService.position - 15);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            MixcloudService.seekTo(MixcloudService.position + 15);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            MixcloudService.setVolume(MixcloudService.volume + 5);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            MixcloudService.setVolume(MixcloudService.volume - 5);
            event.accepted = true;
        } else if (event.key === Qt.Key_M) {
            MixcloudService.toggleMute();
            event.accepted = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        // Left Navigation Sidebar (224px, Theme.pillBg)
        // ============================================================
        Rectangle {
            Layout.preferredWidth: 224
            Layout.fillHeight: true
            color: Theme.pillBg
            clip: true

            ThemeGradientFill {
                anchors.fill: parent
                enabled: Theme.shellGradientEnabled
                color1: Theme.pillBg
                colorMid: Theme.pillBgMid
                color2: Theme.pillBg2
                cornerRadius: 0
            }

            // 1px Right Divider
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: Theme.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // App Identity Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "music"
                            iconSize: 16
                            color: Theme.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Music"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Mixcloud • Stream"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                // Sidebar Search Box (AnimatedTextInput)
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 9
                    clip: true
                    color: searchField.activeFocus ? Theme.surfaceRaised : Theme.cardBg
                    border.width: 1
                    border.color: searchField.activeFocus ? Theme.accent : Theme.borderSubtle

                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 7
                        spacing: 6

                        SvgIcon {
                            sourceName: "search"
                            iconSize: 13
                            color: searchField.activeFocus ? Theme.accent : Theme.textMuted
                        }

                        AnimatedTextInput {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            textColor: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            selectByMouse: true
                            Keys.onReturnPressed: root.submitSidebarSearch()
                            Keys.onEscapePressed: (event) => {
                                if (text !== "") {
                                    text = "";
                                }
                                root.forceActiveFocus();
                                event.accepted = true;
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Search mixes or URL..."
                                color: Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                visible: searchField.text === ""
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: searchField.text !== ""
                            width: 18
                            height: 18
                            radius: 6
                            color: clrMouse.containsMouse ? Theme.cardHover : "transparent"
                            scale: clrMouse.pressed ? 0.90 : 1.0

                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: "close"
                                iconSize: 10
                                color: Theme.textSub
                            }

                            MouseArea {
                                id: clrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchField.text = "";
                                    root.forceActiveFocus();
                                    if (MixcloudService.activeSection === "search") {
                                        MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Collapsible Tree Navigation
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

                        // Library Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 8
                            color: libHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            scale: libHeadMouse.pressed ? 0.98 : 1.0

                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                SvgIcon { sourceName: "music"; iconSize: 14; color: Theme.textSub }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "Library"
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
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
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.libraryOpen = !root.libraryOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.libraryOpen ? libSubCol.implicitHeight : 0
                            opacity: root.libraryOpen ? 1.0 : 0.0
                            clip: true

                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 1
                                x: 16
                                y: 2
                                height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: libSubCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 22
                                spacing: 2

                                Repeater {
                                    model: [
                                        { key: "discover", label: "Discover", icon: "sparkles", count: 0 },
                                        { key: "queue", label: "Queue", icon: "list", count: MixcloudService.queue.length },
                                        { key: "favorites", label: "Favorites", icon: "star", count: MixcloudService.favorites.length },
                                        { key: "recent", label: "Recent", icon: "clock", count: MixcloudService.recent.length }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: MixcloudService.activeSection === modelData.key
                                        Layout.fillWidth: true
                                        height: 26
                                        radius: 7
                                        clip: true
                                        color: isActive ? Theme.cardHover : (libRowMouse.containsMouse ? Theme.cardBg : "transparent")
                                        scale: libRowMouse.pressed ? 0.98 : 1.0

                                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                        Rectangle {
                                            width: 3
                                            height: isActive ? 15 : 6
                                            radius: 2
                                            anchors.left: parent.left
                                            anchors.leftMargin: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 11
                                            anchors.rightMargin: 8
                                            spacing: 7

                                            SvgIcon {
                                                sourceName: modelData.icon
                                                iconSize: 13
                                                color: isActive ? Theme.accent : Theme.textMuted
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: modelData.count > 0
                                                text: String(modelData.count)
                                                color: isActive ? Theme.text : Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        MouseArea {
                                            id: libRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.key === "discover") {
                                                    MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                                                } else {
                                                    MixcloudService.activeSection = modelData.key;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Genres Header
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            height: 28
                            radius: 8
                            color: genHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            scale: genHeadMouse.pressed ? 0.98 : 1.0

                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                SvgIcon { sourceName: "globe"; iconSize: 14; color: Theme.textSub }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "Genres"
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 13
                                    color: Theme.textMuted
                                    rotation: root.genresOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                id: genHeadMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.genresOpen = !root.genresOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.genresOpen ? genSubCol.implicitHeight : 0
                            opacity: root.genresOpen ? 1.0 : 0.0
                            clip: true

                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 1
                                x: 16
                                y: 2
                                height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: genSubCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 22
                                spacing: 2

                                Repeater {
                                    model: MixcloudService.genres
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: MixcloudService.activeSection === "discover" && MixcloudService.activeGenre === modelData.slug
                                        Layout.fillWidth: true
                                        height: 26
                                        radius: 7
                                        clip: true
                                        color: isActive ? Theme.cardHover : (gRowMouse.containsMouse ? Theme.cardBg : "transparent")
                                        scale: gRowMouse.pressed ? 0.98 : 1.0

                                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                        Rectangle {
                                            width: 3
                                            height: isActive ? 15 : 6
                                            radius: 2
                                            anchors.left: parent.left
                                            anchors.leftMargin: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 11
                                            anchors.rightMargin: 8
                                            spacing: 7

                                            Rectangle {
                                                width: 5
                                                height: 5
                                                radius: 2.5
                                                color: isActive ? Theme.accent : Theme.textMuted
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.label
                                                color: isActive ? Theme.text : Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                font.weight: isActive ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: gRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: MixcloudService.loadDiscover(modelData.slug, MixcloudService.sortMode, false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Pinned Sidebar Settings Navigation Row
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                Rectangle {
                    id: settingsNavRow
                    readonly property bool isActive: MixcloudService.activeSection === "settings"
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    clip: true
                    color: isActive ? Theme.cardHover : (settingsNavMouse.containsMouse ? Theme.cardBg : "transparent")
                    scale: settingsNavMouse.pressed ? 0.98 : 1.0

                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    Rectangle {
                        width: 3
                        height: settingsNavRow.isActive ? 15 : 6
                        radius: 2
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent
                        opacity: settingsNavRow.isActive ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 9
                        spacing: 8

                        SvgIcon {
                            sourceName: "settings"
                            iconSize: 14
                            color: settingsNavRow.isActive ? Theme.accent : Theme.textSub
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Settings"
                            color: settingsNavRow.isActive ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: settingsNavRow.isActive ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: MixcloudService.isMixing
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        id: settingsNavMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openSettingsSection("")
                    }
                }

                // Bottom Sidebar Utility Card (Paste URL + Engine Status)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: sideBottomCol.implicitHeight + 16
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    ColumnLayout {
                        id: sideBottomCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 7

                        PillButton {
                            text: "Paste URL"
                            iconName: "link"
                            iconSize: 12
                            fontSize: 11
                            fillWidth: true
                            fixedHeight: 28
                            radius: 8
                            onClicked: root.openUrlModal()
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                color: !MixcloudService.depsChecked
                                    ? Theme.textMuted
                                    : (MixcloudService.depsReady ? Theme.ok : Theme.warn)
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: !MixcloudService.depsChecked
                                    ? "Checking audio..."
                                    : (MixcloudService.depsReady ? "mpv • yt-dlp ready" : "Missing audio tools")
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ============================================================
        // Right Workspace (inherits Theme.surfaceBg)
        // ============================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Top Toolbar (46px)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: "transparent"

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.borderSubtle
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    PillButton {
                        visible: MixcloudService.activeSection === "creator" || MixcloudService.activeSection === "settings"
                        iconName: "arrow-left"
                        iconSize: 13
                        fixedWidth: 30
                        fixedHeight: 30
                        radius: 8
                        onClicked: {
                            const back = (MixcloudService.activeSection === "settings" ? root.prevSectionBeforeSettings : root.prevSectionBeforeCreator) || "discover";
                            if (back === "discover") {
                                MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false);
                            } else {
                                MixcloudService.activeSection = back;
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.sectionTitle
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: MixcloudService.activeSection !== "settings"
                        height: 22
                        width: countLbl.implicitWidth + 14
                        radius: 11
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        Text {
                            id: countLbl
                            anchors.centerIn: parent
                            text: String(root.activeListItems.length) + " mixes"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    // Concentric Popular / Latest Segmented Control (r=9 track, 2px pad, r=7 thumb)
                    Rectangle {
                        visible: MixcloudService.activeSection === "discover"
                        width: 136
                        height: 30
                        radius: 9
                        color: Theme.cardBg
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        Rectangle {
                            x: MixcloudService.sortMode === "latest" ? (parent.width / 2 + 1) : 2
                            y: 2
                            width: parent.width / 2 - 3
                            height: parent.height - 4
                            radius: 7
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Behavior on x { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 2

                            Repeater {
                                model: [
                                    { key: "popular", label: "Popular" },
                                    { key: "latest", label: "Latest" }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool isSel: MixcloudService.sortMode === modelData.key
                                    width: (parent.width) / 2
                                    height: parent.height
                                    scale: segMouse.pressed ? 0.95 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: isSel ? Theme.text : Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: isSel ? Font.DemiBold : Font.Normal
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                    }

                                    MouseArea {
                                        id: segMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (MixcloudService.sortMode !== modelData.key) {
                                                MixcloudService.loadDiscover(MixcloudService.activeGenre, modelData.key, false);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // View Toggle (Grid / List)
                    PillButton {
                        visible: MixcloudService.activeSection !== "settings"
                        iconName: root.isListView ? "grid" : "list"
                        iconSize: 14
                        fixedWidth: 30
                        fixedHeight: 30
                        radius: 8
                        onClicked: {
                            root.isListView = !root.isListView;
                            MixcloudService.setPrefListView(root.isListView);
                        }
                    }

                    // Refresh Feed
                    Item {
                        visible: root.isFeedSection
                        width: 30
                        height: 30

                        PillButton {
                            id: refreshBtn
                            anchors.fill: parent
                            iconName: ""
                            fixedWidth: 30
                            fixedHeight: 30
                            radius: 8
                            onClicked: MixcloudService.refreshFeed()
                        }

                        SvgIcon {
                            id: refreshIcon
                            anchors.centerIn: parent
                            sourceName: "refresh"
                            iconSize: 14
                            color: Theme.text
                            scale: refreshBtn.scale

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 760
                                loops: Animation.Infinite
                                running: MixcloudService.feedLoading
                                onRunningChanged: if (!running) refreshIcon.rotation = 0
                            }
                        }
                    }

                    // Clear Queue
                    PillButton {
                        visible: MixcloudService.activeSection === "queue" && MixcloudService.queue.length > 0
                        text: "Clear"
                        iconName: "trash"
                        iconSize: 12
                        danger: true
                        fixedHeight: 30
                        horizontalPadding: 10
                        radius: 8
                        onClicked: MixcloudService.clearQueue()
                    }

                    // Quit Music App (saves playback position, stops mpv, closes view)
                    PillButton {
                        text: "Quit"
                        iconName: "power"
                        iconSize: 12
                        danger: true
                        subtle: true
                        fixedHeight: 30
                        horizontalPadding: 10
                        radius: 8
                        onClicked: {
                            MixcloudService.quitApp();
                            if (root.shellState) {
                                if (root.shellState.detachedApp === "music") {
                                    root.shellState.closeDetachedApp();
                                }
                                if (root.shellState.islandApp === "music") {
                                    root.shellState.islandApp = "";
                                }
                            }
                        }
                    }
                }
            }

            // Semantic Missing Dependency Banner (Animated height + opacity)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.showDepsBanner ? (depsCard.implicitHeight + 12) : 0
                opacity: root.showDepsBanner ? 1.0 : 0.0
                clip: true
                visible: Layout.preferredHeight > 1 || opacity > 0.01

                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: depsCard
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 10; bottomMargin: 2 }
                    implicitHeight: depsRow.implicitHeight + 16
                    radius: 11
                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.42)
                    clip: true

                    RowLayout {
                        id: depsRow
                        anchors.fill: parent
                        anchors.margins: 8
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 10

                        SvgIcon { sourceName: "alert-triangle"; iconSize: 16; color: Theme.warn }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    const missing = [];
                                    if (!MixcloudService.hasMpv) missing.push("mpv");
                                    if (!MixcloudService.hasYtDlp) missing.push("yt-dlp");
                                    return "Missing " + missing.join(" & ") + " for Mixcloud audio playback";
                                }
                                color: Theme.warn
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: MixcloudService.installHint
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        PillButton {
                            text: root.hintCopied ? "Copied!" : "Copy"
                            iconName: root.hintCopied ? "check" : "copy"
                            iconSize: 12
                            fontSize: 11
                            fixedHeight: 28
                            radius: 8
                            onClicked: {
                                FileService.copyToClipboard(MixcloudService.installHint);
                                root.hintCopied = true;
                                copyResetTimer.restart();
                            }
                        }

                        PillButton {
                            text: "Recheck"
                            iconName: "refresh"
                            iconSize: 12
                            fontSize: 11
                            fixedHeight: 28
                            radius: 8
                            onClicked: MixcloudService.recheckDeps()
                        }
                    }
                }
            }

            // Semantic Error Banner (Animated height + opacity)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.showErrorBanner ? (errCard.implicitHeight + 10) : 0
                opacity: root.showErrorBanner ? 1.0 : 0.0
                clip: true
                visible: Layout.preferredHeight > 1 || opacity > 0.01

                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: errCard
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 8; bottomMargin: 2 }
                    implicitHeight: errRow.implicitHeight + 14
                    radius: 11
                    color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.40)
                    clip: true

                    RowLayout {
                        id: errRow
                        anchors.fill: parent
                        anchors.margins: 7
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8

                        SvgIcon { sourceName: "alert-triangle"; iconSize: 15; color: Theme.dangerText }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.activeBannerText
                            color: Theme.dangerText
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        PillButton {
                            text: "Retry"
                            iconName: "refresh"
                            iconSize: 12
                            fontSize: 11
                            fixedHeight: 26
                            radius: 7
                            onClicked: {
                                if (MixcloudService.errorMessage !== "" && MixcloudService.currentTrack) {
                                    MixcloudService.playTrack(MixcloudService.currentTrack, null);
                                } else {
                                    MixcloudService.refreshFeed();
                                }
                            }
                        }

                        PillButton {
                            iconName: "close"
                            iconSize: 11
                            fixedWidth: 26
                            fixedHeight: 26
                            radius: 7
                            onClicked: {
                                MixcloudService.errorMessage = "";
                                MixcloudService.feedError = "";
                            }
                        }
                    }
                }
            }

            // Main Content Viewport
            Item {
                id: viewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Loading Overlay (animated)
                Item {
                    anchors.fill: parent
                    opacity: (MixcloudService.activeSection !== "settings" && root.isFeedSection && MixcloudService.feedLoading && root.activeListItems.length === 0) ? 1.0 : 0.0
                    visible: opacity > 0.01
                    z: 2
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10

                        SvgIcon {
                            id: loadSpin
                            Layout.alignment: Qt.AlignHCenter
                            sourceName: "refresh"
                            iconSize: 22
                            color: Theme.accent
                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 800
                                loops: Animation.Infinite
                                running: MixcloudService.feedLoading
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Loading Mixcloud shows..."
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                        }
                    }
                }

                // Empty State (animated)
                Item {
                    anchors.fill: parent
                    opacity: (MixcloudService.activeSection !== "settings" && root.activeListItems.length === 0 && !(root.isFeedSection && MixcloudService.feedLoading)) ? 1.0 : 0.0
                    visible: opacity > 0.01
                    z: 2
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(340, parent.width - 48)
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 48
                            height: 48
                            radius: 14
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Theme.borderSubtle

                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: MixcloudService.activeSection === "favorites" ? "star" : (MixcloudService.activeSection === "recent" ? "clock" : "music")
                                iconSize: 20
                                color: Theme.textSub
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: {
                                const s = MixcloudService.activeSection;
                                if (s === "queue") return "Queue is empty";
                                if (s === "favorites") return "No favorites yet";
                                if (s === "recent") return "No recently played mixes";
                                if (s === "search") return "No matching Mixcloud shows";
                                return "No mixes loaded";
                            }
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: {
                                const s = MixcloudService.activeSection;
                                if (s === "queue") return "Play a mix from Discover or paste a Mixcloud URL to build your queue.";
                                if (s === "favorites") return "Star any DJ set or show to keep it ready here.";
                                if (s === "recent") return "Shows you play will appear here automatically.";
                                return "Try another genre, search term, or paste a direct Mixcloud link.";
                            }
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            PillButton {
                                visible: MixcloudService.activeSection !== "discover"
                                text: "Browse Discover"
                                iconName: "sparkles"
                                active: true
                                onClicked: MixcloudService.loadDiscover(MixcloudService.activeGenre, MixcloudService.sortMode, false)
                            }

                            PillButton {
                                text: "Paste URL"
                                iconName: "link"
                                onClicked: root.openUrlModal()
                            }
                        }
                    }
                }

                // Grid View (reuseItems: true)
                GridView {
                    id: mixGrid
                    anchors.fill: parent
                    anchors.margins: 12
                    anchors.bottomMargin: 8
                    visible: MixcloudService.activeSection !== "settings" && !root.isListView && root.activeListItems.length > 0
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property int cols: Math.max(2, Math.floor(width / 172))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: 204
                    model: root.activeListItems

                    ScrollBar.vertical: ScrollBar {
                        policy: mixGrid.contentHeight > mixGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                        }
                    }

                    footer: Item {
                        width: mixGrid.width
                        height: (root.isFeedSection && MixcloudService.nextPageUrl !== "") ? 48 : 4

                        PillButton {
                            anchors.centerIn: parent
                            visible: root.isFeedSection && MixcloudService.nextPageUrl !== ""
                            text: MixcloudService.feedLoadingMore ? "Loading..." : "Load More"
                            iconName: "refresh"
                            enabled: !MixcloudService.feedLoadingMore
                            onClicked: MixcloudService.loadMore()
                        }
                    }

                    delegate: Item {
                        id: gridCell
                        required property var modelData
                        required property int index
                        width: mixGrid.cellWidth
                        height: mixGrid.cellHeight

                        readonly property bool isCurrent: MixcloudService.currentTrack !== null && MixcloudService.currentTrack.key === modelData.key
                        readonly property bool isPlayingHere: isCurrent && MixcloudService.isPlaying

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 12
                            clip: true
                            color: isCurrent
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                : (gCardMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                            border.width: isCurrent ? 1.5 : 1
                            border.color: isCurrent
                                ? Theme.accent
                                : (gCardMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle)
                            scale: gCardMouse.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            MouseArea {
                                id: gCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        root.openTrackContextMenu(gridCell, mouse, modelData, index);
                                    } else if (isCurrent) {
                                        MixcloudService.togglePlay();
                                    } else if (MixcloudService.activeSection === "queue") {
                                        MixcloudService.playQueueAt(index);
                                    } else {
                                        MixcloudService.playTrack(modelData, root.activeListItems);
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 7

                                // Cover Artwork (r=8)
                                ClippingRectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: Theme.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.artLarge || modelData.artSmall || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: "music"
                                        iconSize: 26
                                        color: Theme.textMuted
                                        visible: !(modelData.artLarge || modelData.artSmall)
                                    }

                                    // Hover / Playing Overlay Pill
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 7
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: Theme.accent
                                        opacity: (gCardMouse.containsMouse || isCurrent) ? 1.0 : 0.0
                                        scale: (gCardMouse.containsMouse || isCurrent) ? 1.0 : 0.78

                                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: isPlayingHere ? "media-pause" : "media-play"
                                            iconSize: 15
                                            color: Theme.accentFg
                                        }
                                    }

                                    // Duration Mono Chip
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 7
                                        height: 20
                                        width: durBadgeLbl.implicitWidth + 10
                                        radius: 6
                                        color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.84)
                                        border.width: 1
                                        border.color: Theme.borderSubtle
                                        visible: modelData.duration > 0

                                        Text {
                                            id: durBadgeLbl
                                            anchors.centerIn: parent
                                            text: MixcloudService.formatDuration(modelData.duration)
                                            color: Theme.text
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                // Title
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.name || "Untitled"
                                    color: isCurrent ? Theme.accent : Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }

                                // Creator + Plays
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: modelData.artist || "Unknown"
                                        color: djLinkMouse.containsMouse ? Theme.accent : Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        MouseArea {
                                            id: djLinkMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openCreatorSection(modelData.username, modelData.artist)
                                        }
                                    }

                                    Text {
                                        visible: modelData.plays > 0
                                        text: MixcloudService.formatCount(modelData.plays)
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }

                // List View (reuseItems: true)
                ListView {
                    id: mixList
                    anchors.fill: parent
                    anchors.margins: 12
                    anchors.bottomMargin: 8
                    visible: MixcloudService.activeSection !== "settings" && root.isListView && root.activeListItems.length > 0
                    clip: true
                    reuseItems: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.activeListItems

                    ScrollBar.vertical: ScrollBar {
                        policy: mixList.contentHeight > mixList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                        }
                    }

                    footer: Item {
                        width: mixList.width
                        height: (root.isFeedSection && MixcloudService.nextPageUrl !== "") ? 48 : 4

                        PillButton {
                            anchors.centerIn: parent
                            visible: root.isFeedSection && MixcloudService.nextPageUrl !== ""
                            text: MixcloudService.feedLoadingMore ? "Loading..." : "Load More"
                            iconName: "refresh"
                            enabled: !MixcloudService.feedLoadingMore
                            onClicked: MixcloudService.loadMore()
                        }
                    }

                    delegate: Rectangle {
                        id: listRow
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: MixcloudService.currentTrack !== null && MixcloudService.currentTrack.key === modelData.key
                        readonly property bool isPlayingHere: isCurrent && MixcloudService.isPlaying
                        readonly property bool isFav: MixcloudService.isFavorite(modelData.key)

                        width: mixList.width - 6
                        height: 54
                        radius: 8
                        clip: true
                        color: isCurrent
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            : (rowMouse.containsMouse ? Theme.cardHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035))
                        border.width: 1
                        border.color: isCurrent
                            ? Theme.accent
                            : (rowMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle)
                        scale: rowMouse.pressed ? 0.98 : 1.0

                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    root.openTrackContextMenu(listRow, mouse, modelData, index);
                                } else if (isCurrent) {
                                    MixcloudService.togglePlay();
                                } else if (MixcloudService.activeSection === "queue") {
                                    MixcloudService.playQueueAt(index);
                                } else {
                                    MixcloudService.playTrack(modelData, root.activeListItems);
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            ClippingRectangle {
                                width: 38
                                height: 38
                                radius: 7
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Image {
                                    anchors.fill: parent
                                    source: modelData.artSmall || modelData.artLarge || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: isPlayingHere ? "media-pause" : (rowMouse.containsMouse || isCurrent ? "media-play" : "music")
                                    iconSize: 14
                                    color: isCurrent ? Theme.accent : Theme.text
                                    visible: !(modelData.artSmall || modelData.artLarge) || rowMouse.containsMouse || isCurrent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.name || "Untitled"
                                    color: isCurrent ? Theme.accent : Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: {
                                        const tagsStr = (modelData.tags && modelData.tags.length > 0) ? (" • " + modelData.tags.slice(0, 2).join(", ")) : "";
                                        return (modelData.artist || "Unknown") + tagsStr;
                                    }
                                    color: Theme.textSub
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                visible: modelData.plays > 0
                                text: MixcloudService.formatCount(modelData.plays) + " plays"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }

                            Text {
                                text: MixcloudService.formatDuration(modelData.duration)
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }

                            PillButton {
                                iconName: isFav ? "media-heart-filled" : "media-heart"
                                iconSize: 13
                                subtle: !isFav
                                active: isFav
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 7
                                onClicked: MixcloudService.toggleFavorite(modelData)
                            }

                            PillButton {
                                iconName: MixcloudService.activeSection === "queue" ? "minus" : "plus"
                                iconSize: 13
                                subtle: true
                                danger: MixcloudService.activeSection === "queue"
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 7
                                onClicked: {
                                    if (MixcloudService.activeSection === "queue") {
                                        MixcloudService.removeQueueAt(index);
                                    } else {
                                        MixcloudService.enqueueTrack(modelData);
                                    }
                                }
                            }
                        }
                    }
                }

                // Lazy-loaded Music Settings Page (Audio & EQ, Mix, Ducking, Playback, Data)
                Loader {
                    id: settingsLoader
                    anchors.fill: parent
                    active: MixcloudService.activeSection === "settings" || root._settingsLoaded
                    opacity: MixcloudService.activeSection === "settings" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    z: 3
                    clip: true
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    sourceComponent: Component {
                        MusicSettingsPage {
                            shellState: root.shellState
                            menuHost: root
                            selectMenu: ctxMenu
                        }
                    }
                }
            }

            // ============================================================
            // Docked Now-Playing Transport Bar (h: 84, Theme.surfaceRaised)
            // ============================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                color: Theme.surfaceRaised
                clip: true

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1
                    color: Theme.borderSubtle
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 9
                    anchors.bottomMargin: 10
                    spacing: 7

                    // Row 1: Scrub Timeline with Flanking Mono Timestamps
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            readonly property real shownPos: scrubWrap.dragging
                                ? (scrubWrap.dragRatio * MixcloudService.effectiveDuration)
                                : MixcloudService.position
                            text: MixcloudService.formatDuration(shownPos)
                            color: scrubWrap.dragging ? Theme.accent : Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Item {
                            id: scrubWrap
                            Layout.fillWidth: true
                            height: 14

                            property bool dragging: false
                            property real dragRatio: 0.0
                            readonly property real shownRatio: dragging ? dragRatio : MixcloudService.progress
                            readonly property bool interactive: MixcloudService.hasTrack && MixcloudService.effectiveDuration > 0
                            readonly property bool expanded: interactive && (scrubMouse.containsMouse || dragging)

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: scrubWrap.expanded ? 6 : 4
                                radius: height / 2
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                                clip: true

                                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: parent.radius
                                    color: Theme.accent
                                    width: Math.max(0, Math.min(parent.width, parent.width * scrubWrap.shownRatio))
                                }
                            }

                            Rectangle {
                                id: scrubHandle
                                width: 12
                                height: 12
                                radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(parent.width - width, parent.width * scrubWrap.shownRatio - width / 2))
                                color: Theme.accent
                                border.width: 2
                                border.color: Theme.surfaceRaised
                                scale: scrubWrap.expanded ? (scrubMouse.pressed ? 1.18 : 1.0) : 0.01
                                opacity: scrubWrap.expanded ? 1.0 : 0.0

                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: scrubMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: scrubWrap.interactive
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onPressed: (mouse) => {
                                    scrubWrap.dragging = true;
                                    scrubWrap.dragRatio = Math.max(0, Math.min(1, mouse.x / Math.max(1, width)));
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed) return;
                                    scrubWrap.dragRatio = Math.max(0, Math.min(1, mouse.x / Math.max(1, width)));
                                }
                                onReleased: {
                                    if (scrubWrap.dragging) {
                                        const target = scrubWrap.dragRatio;
                                        scrubWrap.dragging = false;
                                        MixcloudService.seekFraction(target);
                                    }
                                }
                                onCanceled: scrubWrap.dragging = false
                            }
                        }

                        Text {
                            text: MixcloudService.formatDuration(MixcloudService.effectiveDuration)
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }

                    // Row 2: Balanced 3-Zone Transport Controls Row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14

                        // Left: Artwork + Track Info + Live Ducking Indicator
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 240
                            spacing: 10

                            ClippingRectangle {
                                width: 42
                                height: 42
                                radius: 9
                                color: Theme.cardBg
                                border.width: 1
                                border.color: MixcloudService.isDucking
                                    ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.55)
                                    : Theme.borderSubtle
                                Behavior on border.color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                Image {
                                    anchors.fill: parent
                                    source: MixcloudService.currentTrack ? (MixcloudService.currentTrack.artSmall || MixcloudService.currentTrack.artLarge) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: MixcloudService.currentTrack !== null && (MixcloudService.currentTrack.artSmall || MixcloudService.currentTrack.artLarge) !== ""
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "music"
                                    iconSize: 17
                                    color: Theme.textSub
                                    visible: !MixcloudService.currentTrack || ((MixcloudService.currentTrack.artSmall || MixcloudService.currentTrack.artLarge) === "")
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                height: nowCol.implicitHeight
                                scale: nowMouse.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                ColumnLayout {
                                    id: nowCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: MixcloudService.currentTrack ? MixcloudService.currentTrack.name : "Nothing Playing"
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Rectangle {
                                            visible: MixcloudService.isDucking
                                            height: 16
                                            width: duckBadgeLbl.implicitWidth + 10
                                            radius: 5
                                            color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.16)
                                            border.width: 1
                                            border.color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.42)
                                            clip: true

                                            Text {
                                                id: duckBadgeLbl
                                                anchors.centerIn: parent
                                                text: "Ducking"
                                                color: Theme.info
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Rectangle {
                                            visible: MixcloudService.isMixing
                                            height: 16
                                            width: mixBadgeLbl.implicitWidth + 10
                                            radius: 5
                                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                            border.width: 1
                                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                            clip: true
                                            scale: mixBadgeMouse.pressed ? 0.94 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                            Text {
                                                id: mixBadgeLbl
                                                anchors.centerIn: parent
                                                text: MixcloudService.mixStage === "blending"
                                                    ? ("Mix " + Math.round(MixcloudService.mixProgress * 100) + "%")
                                                    : (MixcloudService.mixStage === "analyzing"
                                                        ? "Analyzing"
                                                        : (MixcloudService.mixStage === "syncing"
                                                            ? "Syncing"
                                                            : (MixcloudService.mixStage === "swapping" ? "Swapping" : "Cueing")))
                                                color: Theme.accent
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }

                                            MouseArea {
                                                id: mixBadgeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.openSettingsSection("mix")
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: {
                                                if (!MixcloudService.currentTrack) return "Choose a Mixcloud set to start";
                                                if (MixcloudService.playbackState === "resolving") return "Resolving stream...";
                                                if (MixcloudService.playbackState === "buffering") return "Buffering audio...";
                                                if (MixcloudService.playbackState === "error") return "Playback error • Retry";
                                                if (MixcloudService.isDucking && MixcloudService.duckSource !== "") {
                                                    return MixcloudService.duckSource + " • " + (MixcloudService.currentTrack.artist || "Mixcloud");
                                                }
                                                return MixcloudService.currentTrack.artist || "Mixcloud";
                                            }
                                            color: MixcloudService.playbackState === "error"
                                                ? Theme.dangerText
                                                : (MixcloudService.isBusy ? Theme.accent : Theme.textSub)
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: nowMouse
                                    anchors.fill: parent
                                    enabled: MixcloudService.hasTrack
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.openDetailModal(MixcloudService.currentTrack)
                                }
                            }
                        }

                        // Center: Crisp Transport Cluster (Custom Media SVGs)
                        RowLayout {
                            Layout.alignment: Qt.AlignCenter
                            spacing: 6

                            PillButton {
                                iconName: "media-shuffle"
                                iconSize: 14
                                subtle: !MixcloudService.shuffle
                                active: MixcloudService.shuffle
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.toggleShuffle()
                            }

                            PillButton {
                                iconName: "media-prev"
                                iconSize: 15
                                subtle: true
                                fixedWidth: 30
                                fixedHeight: 30
                                radius: 9
                                enabled: MixcloudService.hasTrack
                                onClicked: MixcloudService.previous()
                            }

                            Item {
                                width: 36
                                height: 36

                                PillButton {
                                    id: playBtn
                                    anchors.fill: parent
                                    iconName: MixcloudService.isBusy ? "" : (MixcloudService.isPlaying ? "media-pause" : "media-play")
                                    iconSize: 16
                                    active: true
                                    fixedWidth: 36
                                    fixedHeight: 36
                                    radius: 18
                                    onClicked: MixcloudService.togglePlay()
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    visible: MixcloudService.isBusy
                                    sourceName: "refresh"
                                    iconSize: 15
                                    color: Theme.accentFg
                                    scale: playBtn.scale
                                    RotationAnimation on rotation {
                                        from: 0
                                        to: 360
                                        duration: 720
                                        loops: Animation.Infinite
                                        running: MixcloudService.isBusy
                                    }
                                }
                            }

                            PillButton {
                                iconName: "media-next"
                                iconSize: 15
                                subtle: true
                                fixedWidth: 30
                                fixedHeight: 30
                                radius: 9
                                enabled: MixcloudService.queue.length > 0
                                onClicked: MixcloudService.next()
                            }

                            PillButton {
                                iconName: MixcloudService.repeatMode === "one" ? "media-repeat-one" : "media-repeat"
                                iconSize: 14
                                subtle: MixcloudService.repeatMode === "off"
                                active: MixcloudService.repeatMode !== "off"
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.cycleRepeat()
                            }
                        }

                        // Right: Favorite + Auto-Duck + Volume Cluster
                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 6

                            PillButton {
                                readonly property bool curFav: MixcloudService.currentTrack !== null && MixcloudService.isFavorite(MixcloudService.currentTrack.key)
                                iconName: curFav ? "media-heart-filled" : "media-heart"
                                iconSize: 14
                                subtle: !curFav
                                active: curFav
                                enabled: MixcloudService.hasTrack
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 8
                                onClicked: if (MixcloudService.currentTrack) MixcloudService.toggleFavorite(MixcloudService.currentTrack)
                            }

                            // Compact Mix Now Trigger / Cancel Button
                            Rectangle {
                                id: mixBtn
                                readonly property bool canMix: MixcloudService.isMixing || (MixcloudService.hasTrack && MixcloudService.peekNextQueueEntry() !== null)
                                width: 28
                                height: 28
                                radius: 8
                                clip: true
                                opacity: canMix ? 1.0 : 0.38
                                color: MixcloudService.isMixing
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                    : ((canMix && mixBtnMouse.containsMouse) ? Theme.cardHover : Theme.cardBg)
                                border.width: (MixcloudService.isMixing || (canMix && mixBtnMouse.containsMouse)) ? 1 : 0
                                border.color: MixcloudService.isMixing
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                    : Theme.borderSubtle
                                scale: (canMix && mixBtnMouse.pressed) ? 0.93 : 1.0

                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "layers"
                                    iconSize: 14
                                    color: MixcloudService.isMixing
                                        ? Theme.accent
                                        : ((mixBtn.canMix && mixBtnMouse.containsMouse) ? Theme.text : Theme.textSub)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }

                                MouseArea {
                                    id: mixBtnMouse
                                    anchors.fill: parent
                                    enabled: mixBtn.canMix
                                    hoverEnabled: mixBtn.canMix
                                    cursorShape: mixBtn.canMix ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (MixcloudService.isMixing) MixcloudService.cancelMix();
                                        else MixcloudService.mixNow();
                                    }
                                }
                            }

                            // Auto-Ducking Toggle (highlights in Theme.info while actively ducking)
                            Rectangle {
                                id: duckBtn
                                width: 28
                                height: 28
                                radius: 8
                                clip: true
                                color: MixcloudService.isDucking
                                    ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.20)
                                    : (MixcloudService.autoDuckEnabled
                                        ? (duckBtnMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                        : (duckBtnMouse.containsMouse ? Theme.cardBg : "transparent"))
                                border.width: (MixcloudService.isDucking || MixcloudService.autoDuckEnabled || duckBtnMouse.containsMouse) ? 1 : 0
                                border.color: MixcloudService.isDucking
                                    ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.55)
                                    : (MixcloudService.autoDuckEnabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle)
                                scale: duckBtnMouse.pressed ? 0.93 : 1.0

                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "media-duck"
                                    iconSize: 14
                                    color: MixcloudService.isDucking
                                        ? Theme.info
                                        : (MixcloudService.autoDuckEnabled ? Theme.accent : Theme.textMuted)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }

                                MouseArea {
                                    id: duckBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MixcloudService.toggleAutoDuck()
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 16
                                color: Theme.borderSubtle
                            }

                            PillButton {
                                iconName: (MixcloudService.muted || MixcloudService.volume === 0)
                                    ? "media-vol-mute"
                                    : (MixcloudService.volume < 50 ? "media-vol-low" : "media-vol-high")
                                iconSize: 14
                                subtle: true
                                fixedWidth: 28
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.toggleMute()
                            }

                            // Slim Volume Slider (64px, h: 4 -> 6 on hover, handle 12x12)
                            Item {
                                id: volSlider
                                width: 64
                                height: 18

                                readonly property real volRatio: MixcloudService.muted ? 0 : (MixcloudService.volume / 100.0)
                                readonly property bool hovered: volMouse.containsMouse || volMouse.pressed

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: volSlider.hovered ? 6 : 4
                                    radius: height / 2
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                                    clip: true

                                    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        radius: parent.radius
                                        color: MixcloudService.muted
                                            ? Theme.textMuted
                                            : (MixcloudService.isDucking ? Theme.info : Theme.accent)
                                        width: Math.max(0, Math.min(parent.width, parent.width * volSlider.volRatio))
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * volSlider.volRatio - width / 2))
                                    color: MixcloudService.isDucking ? Theme.info : Theme.accent
                                    border.width: 2
                                    border.color: Theme.surfaceRaised
                                    scale: volMouse.pressed ? 1.18 : (volMouse.containsMouse ? 1.0 : 0.78)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: volMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    function applyX(mx) {
                                        const pct = Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100);
                                        MixcloudService.setVolume(pct);
                                    }
                                    onPressed: (m) => applyX(m.x)
                                    onPositionChanged: (m) => { if (pressed) applyX(m.x); }
                                }
                            }

                            Text {
                                Layout.preferredWidth: 30
                                horizontalAlignment: Text.AlignRight
                                text: MixcloudService.muted ? "Mute" : (MixcloudService.volume + "%")
                                color: MixcloudService.isDucking ? Theme.info : Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // Root-Hoisted Modal 1: Paste Mixcloud URL (z: 82, r: 14)
    // ============================================================
    Rectangle {
        id: urlOverlay
        anchors.fill: parent
        z: 82
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: root.urlModalOpen ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: root.urlModalOpen
            onClicked: root.closeUrlModal()
        }

        Rectangle {
            id: urlDialog
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 32)
            implicitHeight: urlCol.implicitHeight + 36
            radius: 14
            clip: true
            color: Theme.surfaceBg
            border.width: 1
            border.color: Theme.borderSubtle
            scale: root.urlModalOpen ? 1.0 : 0.94

            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

            SequentialAnimation {
                id: urlShakeAnim
                NumberAnimation { target: urlDialog; property: "anchors.horizontalCenterOffset"; to: -8; duration: 45 }
                NumberAnimation { target: urlDialog; property: "anchors.horizontalCenterOffset"; to: 8; duration: 45 }
                NumberAnimation { target: urlDialog; property: "anchors.horizontalCenterOffset"; to: -6; duration: 45 }
                NumberAnimation { target: urlDialog; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: (m) => m.accepted = true
            }

            ColumnLayout {
                id: urlCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 9
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle
                        SvgIcon { anchors.centerIn: parent; sourceName: "link"; iconSize: 15; color: Theme.accent }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Open Mixcloud URL"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Paste a Mixcloud show link to stream or queue"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    PillButton {
                        iconName: "close"
                        iconSize: 12
                        subtle: true
                        fixedWidth: 28
                        fixedHeight: 28
                        radius: 8
                        onClicked: root.closeUrlModal()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 10
                    clip: true
                    color: Theme.pillBg
                    border.width: 1
                    border.color: root.urlModalError !== ""
                        ? Theme.danger
                        : (urlInput.activeFocus ? Theme.accent : Theme.borderSubtle)
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    AnimatedTextInput {
                        id: urlInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        textColor: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        onTextChanged: if (root.urlModalError !== "") root.urlModalError = ""
                        Keys.onReturnPressed: root.submitUrlModal(true)
                        Keys.onEscapePressed: root.closeUrlModal()

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "https://www.mixcloud.com/creator/show-name/"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            visible: urlInput.text === ""
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    visible: root.urlModalError !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.urlModalError
                    color: Theme.dangerText
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    PillButton {
                        text: "Cancel"
                        subtle: true
                        onClicked: root.closeUrlModal()
                    }

                    PillButton {
                        text: "Add to Queue"
                        iconName: "plus"
                        enabled: !root.urlModalBusy
                        onClicked: root.submitUrlModal(false)
                    }

                    PillButton {
                        text: root.urlModalBusy ? "Resolving..." : "Play Now"
                        iconName: "play"
                        active: true
                        enabled: !root.urlModalBusy
                        onClicked: root.submitUrlModal(true)
                    }
                }
            }
        }
    }

    // ============================================================
    // Root-Hoisted Modal 2: Mix Details (z: 82, r: 14)
    // ============================================================
    FocusScope {
        id: detailOverlay
        anchors.fill: parent
        z: 82
        visible: detailBackdrop.opacity > 0.01

        Keys.onEscapePressed: root.closeDetailModal()

        Rectangle {
            id: detailBackdrop
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.58)
            opacity: root.detailModalOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                enabled: root.detailModalOpen
                onClicked: root.closeDetailModal()
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(500, parent.width - 32)
                height: Math.min(440, parent.height - 32)
                radius: 14
                clip: true
                color: Theme.surfaceBg
                border.width: 1
                border.color: Theme.borderSubtle
                scale: root.detailModalOpen ? 1.0 : 0.94
                Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (m) => m.accepted = true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ClippingRectangle {
                            width: 68
                            height: 68
                            radius: 10
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Image {
                                anchors.fill: parent
                                source: root.detailTrack ? (root.detailTrack.artLarge || root.detailTrack.artSmall) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.detailTrack ? root.detailTrack.name : ""
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.detailTrack ? ("by " + root.detailTrack.artist) : ""
                                color: detailDjMouse.containsMouse ? Theme.accent : Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    id: detailDjMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const tr = root.detailTrack;
                                        root.closeDetailModal();
                                        if (tr && tr.username) root.openCreatorSection(tr.username, tr.artist);
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.detailTrack
                                    ? (MixcloudService.formatDuration(root.detailTrack.duration)
                                       + " • " + MixcloudService.formatCount(root.detailTrack.plays) + " plays"
                                       + " • " + MixcloudService.formatCount(root.detailTrack.favorites) + " favs")
                                    : ""
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        PillButton {
                            Layout.alignment: Qt.AlignTop
                            iconName: "close"
                            iconSize: 12
                            subtle: true
                            fixedWidth: 28
                            fixedHeight: 28
                            radius: 8
                            onClicked: root.closeDetailModal()
                        }
                    }

                    // Tags Flow
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.detailTrack && root.detailTrack.tags && root.detailTrack.tags.length > 0

                        Repeater {
                            model: root.detailTrack ? (root.detailTrack.tags || []) : []
                            delegate: Rectangle {
                                required property string modelData
                                height: 22
                                width: tagLbl.implicitWidth + 14
                                radius: 11
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    id: tagLbl
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.textSub
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    // Description Body
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: Theme.pillBg
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        Flickable {
                            id: descFlick
                            anchors.fill: parent
                            anchors.margins: 12
                            contentWidth: width
                            contentHeight: descTxt.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            ScrollBar.vertical: ScrollBar {
                                policy: descFlick.contentHeight > descFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                width: 4
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                                }
                            }

                            Text {
                                id: descTxt
                                width: descFlick.width
                                wrapMode: Text.WordWrap
                                text: root.detailLoading
                                    ? "Loading show notes..."
                                    : (root.detailDescription !== "" ? root.detailDescription : "No show description provided by creator.")
                                color: root.detailDescription !== "" ? Theme.textSub : Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }
                    }

                    // Footer Actions
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        PillButton {
                            text: root.detailLinkCopied ? "Copied!" : "Copy URL"
                            iconName: root.detailLinkCopied ? "check" : "link"
                            onClicked: {
                                if (root.detailTrack) {
                                    FileService.copyToClipboard(root.detailTrack.url);
                                    root.detailLinkCopied = true;
                                    copyResetTimer.restart();
                                }
                            }
                        }

                        PillButton {
                            text: "Browser"
                            iconName: "external-link"
                            onClicked: if (root.detailTrack) Quickshell.execDetached(["xdg-open", root.detailTrack.url])
                        }

                        Item { Layout.fillWidth: true }

                        PillButton {
                            text: "Queue"
                            iconName: "plus"
                            onClicked: {
                                if (root.detailTrack) MixcloudService.enqueueTrack(root.detailTrack);
                            }
                        }

                        PillButton {
                            text: "Play"
                            iconName: "play"
                            active: true
                            onClicked: {
                                const tr = root.detailTrack;
                                root.closeDetailModal();
                                if (tr) MixcloudService.playTrack(tr, null);
                            }
                        }
                    }
                }
            }
        }
    }

    // Root-Hoisted ContextMenu (z: 90)
    ContextMenu {
        id: ctxMenu
        onClosed: root.forceActiveFocus()
    }
}
