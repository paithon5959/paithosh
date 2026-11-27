import QtQuick
import ".."

Item {
    id: root

    property string effect: "none" // "none" | "snow" | "rain" | "wind"
    property bool active: false
    property int intensity: 100
    property bool previewMode: false

    property string _renderedEffect: effect
    property real _fade: (active && effect !== "none") ? 1.0 : 0.0
    property var _particles: []

    clip: true
    opacity: _fade
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property int particleCount: {
        if (Theme.reduceMotion || !active || _renderedEffect === "none") return 0;
        let base = 0;
        if (_renderedEffect === "snow") base = previewMode ? 24 : 44;
        else if (_renderedEffect === "rain") base = previewMode ? 28 : 48;
        else if (_renderedEffect === "wind") base = previewMode ? 16 : 26;
        return Math.max(10, Math.min(68, Math.round(base * (intensity / 100.0))));
    }

    function _syncFade() {
        _fade = (active && effect !== "none" && effect === _renderedEffect) ? 1.0 : 0.0;
    }

    function _seedParticles() {
        const count = particleCount;
        if (count <= 0) {
            _particles = [];
            return;
        }
        let s = 1337;
        function rand() {
            s = (s * 1664525 + 1013904223) >>> 0;
            return s / 4294967296.0;
        }
        const list = [];
        for (let i = 0; i < count; ++i) {
            const depth = 0.35 + rand() * 0.65;
            list.push({
                nx: rand(),
                ny: rand(),
                depth: depth,
                phase: rand() * Math.PI * 2.0,
                speed: 0.78 + rand() * 0.44,
                isMote: (i % 10) >= 7
            });
        }
        _particles = list;
        _updatePositions(0.0);
        Qt.callLater(function() {
            root._updatePositions(0.0);
        });
    }

    function _updatePositions(dt) {
        const w = width;
        const h = height;
        if (w <= 0 || h <= 0) return;
        const list = _particles;
        const n = Math.min(list.length, rep.count);
        const eff = _renderedEffect;
        const speedMul = 0.7 + (intensity / 100.0) * 0.35;

        for (let i = 0; i < n; ++i) {
            const p = list[i];
            const item = rep.itemAt(i);
            if (!p || !item) continue;

            if (dt > 0) {
                p.phase += dt * (eff === "snow" ? 1.35 : 1.1);
                if (eff === "snow") {
                    const vy = (0.045 + p.depth * 0.085) * p.speed * speedMul;
                    const vx = Math.sin(p.phase) * (0.014 + p.depth * 0.012);
                    p.ny += vy * dt;
                    p.nx += vx * dt;
                    if (p.ny > 1.04) { p.ny = -0.04; p.nx = (p.nx + 0.37) % 1.0; }
                    if (p.nx < -0.04) p.nx += 1.08;
                    if (p.nx > 1.04) p.nx -= 1.08;
                } else if (eff === "rain") {
                    const vy = (0.68 + p.depth * 0.62) * p.speed * speedMul;
                    p.ny += vy * dt;
                    p.nx -= vy * 0.22 * dt;
                    if (p.ny > 1.08) { p.ny = -0.08; p.nx = (p.nx + 0.61) % 1.0; }
                    if (p.nx < -0.08) p.nx += 1.12;
                } else if (eff === "wind") {
                    const vx = (0.14 + p.depth * 0.22) * p.speed * speedMul;
                    p.nx += vx * dt;
                    p.ny += Math.sin(p.phase * 1.4) * 0.016 * dt;
                    if (p.nx > 1.12) { p.nx = -0.12; p.ny = (p.ny + 0.29) % 1.0; }
                    if (p.ny < 0.02) p.ny = 0.96;
                    if (p.ny > 0.98) p.ny = 0.04;
                }
            }

            item.x = p.nx * w;
            item.y = p.ny * h;
            if (eff === "snow") {
                item.opacity = 0.22 + p.depth * 0.48;
            } else if (eff === "rain") {
                item.opacity = 0.16 + p.depth * 0.30;
            } else if (eff === "wind") {
                const edgeFade = Math.max(0.0, Math.min(1.0, Math.sin(Math.max(0.0, Math.min(1.0, p.nx)) * Math.PI)));
                item.opacity = (p.isMote ? (0.14 + p.depth * 0.22) : (0.07 + p.depth * 0.16)) * edgeFade;
            }
        }
    }

    Component.onCompleted: {
        if (root.active && root._renderedEffect !== "none") {
            root._seedParticles();
        }
    }

    onEffectChanged: {
        if (effect === _renderedEffect) {
            _syncFade();
            return;
        }
        if (!active || _renderedEffect === "none") {
            swapTimer.stop();
            _renderedEffect = effect;
            _seedParticles();
            _syncFade();
        } else {
            _fade = 0.0;
            swapTimer.restart();
        }
    }

    onActiveChanged: {
        if (active) {
            if (_renderedEffect !== effect) {
                _renderedEffect = effect;
                _seedParticles();
            } else if (_particles.length !== particleCount) {
                _seedParticles();
            }
        }
        _syncFade();
    }

    onParticleCountChanged: {
        if (active && _renderedEffect !== "none") {
            _seedParticles();
        } else if (particleCount === 0) {
            _particles = [];
        }
    }

    onWidthChanged: _updatePositions(0.0)
    onHeightChanged: _updatePositions(0.0)

    Timer {
        id: swapTimer
        interval: 170
        repeat: false
        onTriggered: {
            root._renderedEffect = root.effect;
            root._seedParticles();
            root._syncFade();
        }
    }

    Repeater {
        id: rep
        model: root.particleCount

        delegate: Rectangle {
            required property int index
            readonly property var pData: (index >= 0 && index < root._particles.length) ? root._particles[index] : null
            readonly property real depth: pData ? pData.depth : 0.6
            readonly property bool isMote: pData ? pData.isMote : false
            readonly property string eff: root._renderedEffect

            color: Theme.text
            rotation: eff === "rain" ? 13 : 0
            antialiasing: eff === "snow" || (eff === "wind" && isMote)

            width: {
                if (eff === "snow") return (root.previewMode ? 2.0 : 2.6) + depth * (root.previewMode ? 2.4 : 3.2);
                if (eff === "rain") return 1.4;
                if (eff === "wind") return isMote ? (root.previewMode ? 2.2 : 3.0) : ((root.previewMode ? 22 : 34) + depth * (root.previewMode ? 24 : 44));
                return 0;
            }
            height: {
                if (eff === "snow") return width;
                if (eff === "rain") return (root.previewMode ? 10 : 16) + depth * (root.previewMode ? 10 : 18);
                if (eff === "wind") return isMote ? width : 1.4;
                return 0;
            }
            radius: (eff === "snow" || (eff === "wind" && isMote)) ? width / 2 : 1
            opacity: {
                if (eff === "snow") return 0.22 + depth * 0.48;
                if (eff === "rain") return 0.16 + depth * 0.30;
                return 0.15;
            }
        }
    }

    FrameAnimation {
        running: !Theme.reduceMotion && root.active && root.visible && root.opacity > 0.01 && root._renderedEffect !== "none" && root.width > 0 && root.height > 0
        onTriggered: root._updatePositions(Math.min(0.05, frameTime))
    }
}
