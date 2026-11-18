pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled

    readonly property string activeSsid: {
        const devs = Networking.devices ? Networking.devices.values : [];
        if (devs) {
            for (let i = 0; i < devs.length; ++i) {
                const dev = devs[i];
                if (dev && dev.type === DeviceType.Wifi && dev.networks && dev.networks.values) {
                    const nets = dev.networks.values;
                    for (let j = 0; j < nets.length; ++j) {
                        if (nets[j] && nets[j].connected) {
                            return nets[j].name || "Connected";
                        }
                    }
                }
            }
        }
        return wifiEnabled ? "Disconnected" : "Off";
    }

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled;
    }
}
