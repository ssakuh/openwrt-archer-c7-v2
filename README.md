# TP-Link Archer C7 v2 OpenWRT

## Description

This is a modified ath79 build based on other open source builds for this specific device:
- [nefty1029](https://github.com/nefty1029/openwrt-optimized-archer-c7-v2)
- [vurrut](https://github.com/vurrut/openwrt-optimized-archer-c7-v2)
- [shunjou](https://github.com/shunjou/openwrt-optimized-archer-c7-v2)
- [r00t](https://github.com/infinitnet/lede-ar71xx-optimized-archer-c7-v2) - [Discussion](https://forum.openwrt.org/t/1382)

Includes various patches from [gwlim](https://github.com/gwlim/mips74k-ar71xx-lede-patch) with a lighter package selection, as it has a flash storage of 16 MB.

Recommended to make a config backup and use `-n` with sysupgrade to not keep settings after upgrade. If not, then be sure to use the sed command to update the wireless radio paths before flashing to avoid creating duplicate radio entries.

## Usage

Tested sucessfully only under `amd64` architecture.

```shell
docker build --output=. .
```

Rename the built binary to a short name, i.e. `firmware.bin` and upgrade the system via TP-Link Web UI.

## Performance tuning

When the device is configured to NAT via PPPoE:

- Gigabit speeds can be achieved with the following configuration:
```shell
$ cat /etc/config/firewall
config defaults
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option synflood_protect '1'
	option drop_invalid '1'
	option flow_offloading '1'
	option flow_offloading_hw '1'
```

- Wireguard interfaces must be configured with a matching MTU:
```shell
$ cat /etc/config/network
...
config interface 'WireGuard'
	option proto 'wireguard'
	option private_key '$PRIVATE_KEY'
	option listen_port '$PORT'
	list addresses '$CIDR'
	option delegate '0'
	option mtu '1492'
```
This way, it can achieve around 50Mbps/35Mbps throughput.

Regardless of the WPA Daemon tested, `psk2` is the strongest encryption type that this device can handle. Maximum wireless performance has been achieved with the following configuration:
```shell
$ opkg install wpad-mini
$ cat /etc/config/wireless
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'pci0000:00/0000:00:00.0'
	option channel '140'
	option hwmode '11a'
	option band '5g'
	option htmode 'VHT80'
	option country 'DE'
	option cell_density '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid '$5_SSID'
	option encryption 'psk2'
	option key '$5_KEY'
	option ieee80211w '0'
	option wpa_disable_eapol_key_retries '1'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/ahb/18100000.wmac'
	option channel '9'
	option band '2g'
	option hwmode '11g'
	option htmode 'HT40'
	option country 'DE'
	option ldpc '0'
	option cell_density '0'
	option txpower '20'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option network 'lan'
	option mode 'ap'
	option ssid '$24_SSID'
	option encryption 'psk2'
	option key '$24_KEY'
	option ieee80211w '0'
	option wpa_disable_eapol_key_retries '1'

$ crontab -l
0 3 * * * wifi down && wifi up
```

## Known issues

- Ethernet port status LEDs can't be manually controlled
- You tell me!
