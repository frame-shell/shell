pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Current weather and a short forecast from wttr.in (no API key needed).
// Icons are Nerd Font weather glyphs.
Singleton {
    id: root

    property bool ready: false
    property string location: ""
    property int temp: 0
    property int feelsLike: 0
    property int high: 0
    property int low: 0
    property string description: ""
    property string icon: ""
    property int humidity: 0
    property int wind: 0
    property string windDir: ""
    property string sunrise: ""
    property string sunset: ""
    // [{ time, icon, temp }] for the next three 3-hour slots
    property var hours: []
    // [{ day, icon, high, low }] for tomorrow and the day after
    property var days: []

    function refresh() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", `https://wttr.in/${encodeURIComponent(Config.weatherLocation)}?format=j1`);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                console.warn(`weather: wttr.in answered ${xhr.status}`);
                return;
            }
            try {
                parse(JSON.parse(xhr.responseText));
            } catch (e) {
                console.warn(`weather: ${e}`);
            }
        };
        xhr.send();
    }

    function parse(data) {
        const now = data.current_condition[0];
        const today = data.weather[0];
        const area = data.nearest_area?.[0]?.areaName?.[0]?.value ?? "";

        location = (Config.weatherLocation || area).toLowerCase();
        temp = Number(now.temp_C);
        feelsLike = Number(now.FeelsLikeC);
        high = Number(today.maxtempC);
        low = Number(today.mintempC);
        description = (now.weatherDesc?.[0]?.value ?? "").trim().toLowerCase();
        humidity = Number(now.humidity);
        wind = Number(now.windspeedKmph);
        windDir = (now.winddir16Point ?? "").toLowerCase();
        sunrise = to24h(today.astronomy?.[0]?.sunrise);
        sunset = to24h(today.astronomy?.[0]?.sunset);
        icon = iconFor(now.weatherCode, isNight());

        // wttr.in gives 3-hour slots ("0", "300" … "2100"); continue into tomorrow
        const hourNow = new Date().getHours();
        const slots = [];
        data.weather.slice(0, 2).forEach((day, i) => day.hourly.forEach(h => {
            const hour = Number(h.time) / 100 + i * 24;
            if (hour > hourNow)
                slots.push({
                    time: `${String(hour % 24).padStart(2, "0")}:00`,
                    icon: iconFor(h.weatherCode, false),
                    temp: Number(h.tempC)
                });
        }));
        hours = slots.slice(0, 3);

        days = data.weather.slice(1, 3).map(day => ({
            day: new Date(day.date).toLocaleDateString(Qt.locale("en_GB"), "ddd").toLowerCase(),
            icon: iconFor(day.hourly?.[4]?.weatherCode ?? 113, false),
            high: Number(day.maxtempC),
            low: Number(day.mintempC)
        }));

        ready = true;
    }

    // "07:42 AM" → "07:42"
    function to24h(value) {
        const m = /(\d+):(\d+)\s*(AM|PM)/i.exec(value ?? "");
        if (!m)
            return value ?? "";
        let h = Number(m[1]) % 12;
        if (m[3].toUpperCase() === "PM")
            h += 12;
        return `${String(h).padStart(2, "0")}:${m[2]}`;
    }

    function isNight() {
        const now = Qt.formatTime(new Date(), "hh:mm");
        return sunrise !== "" && (now < sunrise || now > sunset);
    }

    // wttr.in / WWO weather codes → Nerd Font weather glyphs
    function iconFor(code, night) {
        const c = Number(code);
        if (c === 113)
            return night ? "" : "";
        if (c === 116)
            return night ? "" : "";
        if ([119, 122].includes(c))
            return "";
        if ([143, 248, 260].includes(c))
            return "";
        if ([200, 386, 389, 392, 395].includes(c))
            return "";
        if ([179, 182, 185, 281, 284, 311, 314, 317, 350, 362, 365, 374, 377].includes(c))
            return "";
        if ([227, 230, 323, 326, 329, 332, 335, 338, 368, 371].includes(c))
            return "";
        if ([176, 263, 266, 293, 296, 353].includes(c))
            return "";
        return "";
    }

    Timer {
        interval: Math.max(1, Config.weatherInterval) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
