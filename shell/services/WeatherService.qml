pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int tempCelsius: 27
    property string tempText: tempCelsius + "℃"
    property string locationName: "Local"
    property int humidityPct: 0
    property int windKmh: 0
    property int weatherCode: 0
    property bool isDay: true
    property bool loading: false
    property var dailyForecast: []

    readonly property var currentMeta: weatherMeta(weatherCode, isDay)
    readonly property string conditionText: currentMeta.label
    readonly property string conditionIcon: currentMeta.icon

    property string cachePath: (Quickshell.env("HOME") || "/tmp") + "/.cache/paithosh/weather.json"
    // PAITHOSH_LAT/LON override; otherwise located by IP on each refresh
    readonly property bool manualLoc: !!(Quickshell.env("PAITHOSH_LAT") && Quickshell.env("PAITHOSH_LON"))
    property string latitude: Quickshell.env("PAITHOSH_LAT") || "10.8231"
    property string longitude: Quickshell.env("PAITHOSH_LON") || "106.6297"

    function weatherMeta(code, dayFlag) {
        const c = Number(code) || 0;
        const day = (dayFlag === undefined) ? true : !!dayFlag;
        if (c === 0) return { icon: day ? "sun" : "moon", label: day ? "Clear" : "Clear Night" };
        if (c === 1 || c === 2) return { icon: day ? "sun" : "moon", label: "Partly Cloudy" };
        if (c === 3 || c === 45 || c === 48) return { icon: "cloud", label: c === 3 ? "Overcast" : "Foggy" };
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return { icon: "cloud-rain", label: c >= 61 ? "Rain" : "Drizzle" };
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return { icon: "snowflake", label: "Snow" };
        if (c >= 95 && c <= 99) return { icon: "bolt", label: "Thunderstorm" };
        return { icon: "wind", label: "Breezy" };
    }

    function formatDayLabel(isoDate, idx) {
        if (idx === 0) return "Today";
        const parts = String(isoDate || "").split("-");
        if (parts.length !== 3) return "";
        const dt = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        return names[dt.getDay()] || "";
    }

    FileView {
        id: cacheReader
        path: root.cachePath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const obj = JSON.parse(cacheReader.text());
                if (!obj) return;
                if (typeof obj.temp === "number") root.tempCelsius = Math.round(obj.temp);
                if (typeof obj.locationName === "string" && obj.locationName !== "") root.locationName = obj.locationName;
                if (typeof obj.humidityPct === "number") root.humidityPct = Math.round(obj.humidityPct);
                if (typeof obj.windKmh === "number") root.windKmh = Math.round(obj.windKmh);
                if (typeof obj.weatherCode === "number") root.weatherCode = obj.weatherCode;
                if (typeof obj.isDay === "boolean") root.isDay = obj.isDay;
                if (Array.isArray(obj.dailyForecast)) root.dailyForecast = obj.dailyForecast;
            } catch (e) {}
        }
    }

    Process {
        id: cacheWriter
        property string payload: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.cachePath, payload]
    }

    function saveCache() {
        cacheWriter.payload = JSON.stringify({
            temp: root.tempCelsius,
            locationName: root.locationName,
            humidityPct: root.humidityPct,
            windKmh: root.windKmh,
            weatherCode: root.weatherCode,
            isDay: root.isDay,
            dailyForecast: root.dailyForecast,
            updatedAt: Date.now()
        });
        cacheWriter.running = true;
    }

    function refresh() {
        root.loading = true;
        if (manualLoc) { fetchWeather(); return; }
        const g = new XMLHttpRequest();
        g.open("GET", "https://ipwho.is/");
        g.onreadystatechange = function() {
            if (g.readyState !== XMLHttpRequest.DONE) return;
            try {
                const d = JSON.parse(g.responseText);
                if (d && d.success !== false && typeof d.latitude === "number") {
                    root.latitude = String(d.latitude);
                    root.longitude = String(d.longitude);
                    const loc = d.city || d.region || d.country || "";
                    if (loc !== "") root.locationName = loc;
                }
            } catch (e) {}
            root.fetchWeather();
        };
        g.send();
    }

    function fetchWeather() {
        const xhr = new XMLHttpRequest();
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(latitude)
            + "&longitude=" + encodeURIComponent(longitude)
            + "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=7";
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    if (data && data.current) {
                        const c = data.current;
                        if (typeof c.temperature_2m === "number") root.tempCelsius = Math.round(c.temperature_2m);
                        if (typeof c.relative_humidity_2m === "number") root.humidityPct = Math.round(c.relative_humidity_2m);
                        if (typeof c.wind_speed_10m === "number") root.windKmh = Math.round(c.wind_speed_10m);
                        if (typeof c.weather_code === "number") root.weatherCode = c.weather_code;
                        if (typeof c.is_day === "number") root.isDay = c.is_day === 1;
                    }
                    if (data && data.daily && Array.isArray(data.daily.time)) {
                        const d = data.daily;
                        const list = [];
                        const count = Math.min(7, d.time.length);
                        for (let i = 0; i < count; i++) {
                            const code = Array.isArray(d.weather_code) ? (d.weather_code[i] || 0) : 0;
                            const meta = root.weatherMeta(code, true);
                            list.push({
                                dayLabel: root.formatDayLabel(d.time[i], i),
                                icon: meta.icon,
                                condition: meta.label,
                                tempMax: Array.isArray(d.temperature_2m_max) ? Math.round(d.temperature_2m_max[i]) : root.tempCelsius,
                                tempMin: Array.isArray(d.temperature_2m_min) ? Math.round(d.temperature_2m_min[i]) : root.tempCelsius,
                                rainPct: Array.isArray(d.precipitation_probability_max) ? Math.round(d.precipitation_probability_max[i] || 0) : 0
                            });
                        }
                        root.dailyForecast = list;
                    }
                    root.saveCache();
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

    Timer {
        interval: 2000
        running: true
        repeat: false
        onTriggered: root.refresh()
    }
}
