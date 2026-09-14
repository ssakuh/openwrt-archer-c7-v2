# Archer C7 v2 Build — Hardening + Perf TODO

> Local-only file. Do NOT commit (untracked). Created 2026-09-13, updated 2026-09-13.
> Source state: passing build, OpenWrt 25.12.5, kernel 6.12.94, sysupgrade 8.5M / factory 16M padded.
> Dropped per owner: #01 open-WiFi default (intentional), #02 world-regdb 33dBm hack (intentional), #18 source pinning (not needed), cosign/SBOM in #21 (not needed), mandatory password in #08 (fine with no pass).

## How to use
- Work one item at a time, verify on device + rebuild.
- Commit repo changes separately; never `git add TODO.md`.

## Status 2026-09-13 — REBUILD OK (native arm64, no gcc-14), disk cleaned
- BUILD 2026-09-13 21:56 native arm64: SUCCESS 1837s, sysupgrade 8.5M (8913187B) factory 16M padded (16252928B), initramfs 8.0M, kernel 6.12.94, r33051-f5dae5ece4, sha sysupgrade 887f6b32..., factory f198d68d... (prev build same size, hash diff only timestamp/order). `file` binwalk: factory + squashfs xz 6073428B, 1378 inodes, block 262144B. `config.buildinfo` identical to prev (0dc3c452). Disk: deleted old 64G datadisk (~38G actual) + 20G disk, freed 41G, host now 54G free, colima fresh 20G rootDisk, Build Cache 0B.
- DONE in tree (uncommitted): TODO-06,07,08,09,10,11(fix),14(verify),19,20(doc),21,22,24 — all verified 21:56 build: `shellcheck -S warning` clean, `sh -n` OK, patches 24/24 apply in Docker (built), `sysupgrade`/`factory` binwalk OK.
- NEEDS DEVICE (after flash): TODO-03,04,05,12,13,15,16,17 — ready to flash `bin-new/targets/ath79/generic/*sysupgrade.bin` (or `bin/...` after sync).

---

### TODO-03 — SQM (CAKE) vs flow offload [DECIDED, DONE in tree]
Decision (A): default `flow_offloading=1`, SQM disabled by default (OpenWrt default).
`099-enable-flow-offloading.patch` now also sets `synflood_protect=1`, `drop_invalid=1` + comment warning that offload bypasses CAKE. `README` documents flip.
Device test after flash:
```sh
uci get firewall.@defaults[0].flow_offloading # expect 1
nft list ruleset | grep -i flow
# enable SQM -> must set flow_offloading 0 first:
# uci set firewall.@defaults[0].flow_offloading=0; uci commit; /etc/init.d/firewall restart
tc -s qdisc # CAKE only effective when offload=0
```

### TODO-04 — conntrack/RAM [DONE in tree, VERIFY on device]
Changed `files/etc/sysctl.conf`: `nf_conntrack_max 65536->16384` (OpenWrt default for 128M), `rmem/wmem_max 2M->512k`, `tcp_rmem/wmem max ->512k`, `somaxconn 4096->1024`, `backlog/syn_backlog 16384->2048`, added `tcp_loose=0`, `checksum=1`.
Verify under load after flash:
```sh
cat /proc/meminfo | grep -E 'MemTotal|MemFree|Slab|SUnreclaim'
cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max
wc -l /proc/net/nf_conntrack; dmesg | grep -iE 'oom|table full'
# load: iperf3 -P 20, torrent 500+ conns; watch free + count, need >20M free
```

### TODO-05 — ag71xx DMA-unmap removals [PLAN, NEEDS DEVICE]
Kept `060-ring-reorder` (good). Unmap removals (`059-*`) still in tree pending proof.
Device test:
```sh
dmesg | grep -iE 'dma|cache|ag71xx|ath9k'
iperf3 -t 300 both dirs + md5sum file transfer, no corruption
# optional test build with CONFIG_DMA_API_DEBUG=y, watch warnings
```
If any corruption/warning, revert `059-ag71xx-DMA-unmap-*.patch` + `059-remove-dma-no-op-from-ath9k.patch`, keep reorder + debug-strip.

### TODO-06 — Harden `wan-addr` / `wlan-kick` / `leds` [DONE, VERIFIED LOCALLY]
`set -eu`, quoting, MAC regex, pid-is-udhcpc, `/dev/urandom` + U/L bits, `ip` over `ifconfig`, dynamic `hostapd.*`, sysfs guards. `sh -n` + `shellcheck -S warning` clean, `randmac` uppercase + injection rejected.
Device test: `wan-addr randmac`, `mac get/set`, `wlan-kick list`, `leds on/off`.

### TODO-07 — `rc.local` [DONE]
Removed `phy1` hardcode + boot `iwinfo scan &`. Now tries `phy0/phy1` best-effort with guards. Device test: `logread | grep rc.local`, `iw phy phy0/phy1 info`.

### TODO-08 — uhttpd [DONE]
`099-uhttpd-config.patch` now only `max_requests 3->2`. Removed re-added `.php` handler + `index.php`. `redirect_https=1` + TLS1.3-only kept in `100-tls13-only.patch` (server-only, client `uclient-fetch/opkg` unaffected).
Device test: `uhttpd -h`, LuCI https + http→https, `uclient-fetch https://downloads.openwrt.org/...`.

### TODO-09 — `sysctl.conf` [DONE]
Added `dmesg_restrict`, `perf_event_paranoid=2`, `unprivileged_bpf_disabled=2`, `mmap_min_addr`, `protected_symlinks/hardlinks`, `ipv6 redirects/source_route=0`, `tcp_loose/checksum`. Device test: `sysctl -a | grep -E 'dmesg|perf|bpf|protected|tcp_loose'`.

### TODO-10 — Firewall [DONE]
Baked `synflood_protect/drop_invalid` + offload note into patch. `bcp38` not installed (needs package) — covered by `drop_invalid` for now.
Device test: `uci show firewall`, `nft list ruleset | grep -E 'invalid|synflood|flow'`.

### TODO-11 — `-O2 -march=74kc` + lzma fix [FIX DONE, BENCH NEEDS DEVICE]
Fixed triplicated `Wa,...` dup in `005-lzma-mips74kc-optimize.patch` (now single `-Wa,-32 -Wa,-march=74kc -Wa,--trap`).
Bench after flash: compare size, `iperf3 NAT`, `openssl speed chacha20`, boot time vs stock `-Os`.

### TODO-12 — `mips_24kc` vs `74kc` ABI [NEEDS DEVICE]
`001` forces `24kc=-march=74kc` but feeds are `mips_24kc`. Built-ins fast, external opkg generic. Device test: `opkg update && opkg install htop`, `cat /proc/cpuinfo`, confirm no illegal-instruction.

### TODO-13 — `HZ=250`, `WQ_POWER_EFFICIENT=n`, `JUMP_LABEL=y` [NEEDS DEVICE]
In `008-generic-kernel-options.patch`. Test `ping -f`, SQM latency, `cat /proc/interrupts | grep timer`.

### TODO-14 — Crypto/TLS [VERIFIED, DONE]
mbedTLS kept for 16M size (correct). `081-openssl-threads` retained as no-op (harmless, future-proof). `100-tls13-only` only touches server path — safe. Device test above.

### TODO-15 — Size budget [NEEDS DEVICE]
sysupgrade 8.5M leaves small overlay. Device test: `df -h /overlay`, `free`, decide to trim `dnsmasq-full` options / `ipv6only` if tight.

### TODO-16 — WiFi [NEEDS DEVICE]
Validate `014-skb_orphan` on 6.12/ct, `dynack`, try `802.11w=1/2` vs `0`, `iperf` over 2.4/5G.

### TODO-17 — musl ASM port [NEEDS DEVICE]
`045` 2017 port assumes 32B lines (QCA9558 64B?). Keep pending microbench vs stock musl.

### TODO-19 — Dockerfile [DONE]
Reordered `feeds update/install` before `COPY` (patch edits no longer bust feeds), added `ccache` + `dl`/`ccache` cache mounts, `CONFIG_CCACHE=y`. Kept `install -a` (minimal list would drop LuCI deps — do only after green build).

### TODO-20 — Minimal feeds [DEFERRED, documented]
Kept `-a` for safety. Future: test `install sqm-scripts luci-app-sqm ...` + deps in a branch build.

### TODO-21 — Workflow [DONE]
`permissions: contents:write` only, `concurrency`, `timeout 120`, lint step, releases immutable (only on `tags/v*`, no `release delete/tag -d/push :refs/tags`).

### TODO-22 — Survivability [DONE]
Deleted dead `uci-defaults/nfsd-disable` (no nfsd in image), added `files/etc/sysupgrade.conf` for custom files.

### TODO-23 — Smoke + QEMU (see verdict below)
QEMU `ath79/QCA9558` has no machine model — wont-boot, use binwalk + device tests above.

### TODO-24 — README [DONE]
Fixed size, factory `-eu/-us`, removed bogus `flow_offloading_hw`, clarified `wpad-basic-mbedtls` shipped.

---
WONTFIX: #01, #02, #18.
