pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int tempCelsius: 27
    property string tempText: tempCelsius + "℃"
    property string cachePath: (Quickshell.env("HOME") || "/tmp") + "/.cache/paithosh/weather.json"
    property string latitude: Quickshell.env("PAITHOSH_LAT") || "10.8231"
    property string longitude: Quickshell.env("PAITHOSH_LON") || "106.6297"

    FileView {
        id: cacheReader
        path: root.cachePath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const obj = JSON.parse(cacheReader.text());
                if (obj && typeof obj.temp === "number") {
                    root.tempCelsius = Math.round(obj.temp);
                }
            } catch (e) {}
        }
    }

    Process {
        id: cacheWriter
        property string payload: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.cachePath, payload]
    }

    function saveCache(tempVal) {
        cacheWriter.payload = JSON.stringify({ temp: tempVal, updatedAt: Date.now() });
        cacheWriter.running = true;
    }

    function refresh() {
        const xhr = new XMLHttpRequest();
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(latitude)
            + "&longitude=" + encodeURIComponent(longitude)
            + "&current=temperature_2m";
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    if (data && data.current && typeof data.current.temperature_2m === "number") {
                        const t = Math.round(data.current.temperature_2m);
                        root.tempCelsius = t;
                        root.saveCache(t);
                    }
                } catch (e) {}
            }
        };
        xhr.send();
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
