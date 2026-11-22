# gl-mt5000-openwrt

A **clean, minimal** build of **official OpenWrt `main`** (Linux **kernel 6.18**)
for the **GL.iNet GL-MT5000 (Brume 3)** — with the RTL8371C ("RTL8366UB") switch
driven by the in-tree **DSA** driver and **MediaTek PPE hardware flow offload**.

This is *vanilla upstream OpenWrt `main` + the not-yet-merged device-support PR*.
It is **not** a GL.iNet firmware fork, and it carries no proxy stack, themes, or
external feeds.

## What the build does

1. Clones official `openwrt/openwrt` at branch `main` (latest upstream OpenWrt
   SNAPSHOT, currently Linux kernel **6.18**).
2. Grafts the full GL-MT5000 commit series from OpenWrt PR
   [#24237](https://github.com/openwrt/openwrt/pull/24237) (automatically skipped
   once merged upstream):
   - In-tree kernel 6.18 Realtek RTL8366UB MDIO DSA switch driver
     (`CONFIG_NET_DSA_REALTEK_RTL8366UB=y`) and dedicated 802.1Q DSA tagger
     (`CONFIG_NET_DSA_TAG_RTL8366UB_8021Q=y`) — no out-of-tree SDK package.
   - MediaTek `mtk_eth_soc` fix restricting native MTK special-tag bits to MTK
     DSA switches.
   - MediaTek PPE hardware flow-offload support for the RTL8366UB 802.1Q DSA
     tagger (standalone ports, VLAN-unaware bridges, and VLAN-filtering bridges).
   - GL-MT5000 DTS (`mt7987a-glinet-gl-mt5000.dts`), image recipe
     (`sysupgrade.bin` + `factory.bin`), `board.d/02_network` (`lan1 lan2` /
     `eth1`), and eMMC `platform.sh` upgrade + `platform_copy_config` support.
3. Builds a minimal image: LuCI + `kmod-nft-offload` +
   `ethtool`/`ip-full`/`tcpdump`/`iperf3` for validation.

All of that is driven by `scripts/diy.sh` and `config/mt5000.config`.

## Build it

GitHub → **Actions** → **Build GL-MT5000 OpenWrt (DSA)** → **Run workflow**.
When it finishes, download the **`gl-mt5000-firmware`** artifact (kept 14 days).
It contains:
- `openwrt-mediatek-filogic-glinet_gl-mt5000-squashfs-sysupgrade.bin` — flash/upgrade image
- `openwrt-mediatek-filogic-glinet_gl-mt5000-squashfs-factory.bin` — factory image
- `...-initramfs-kernel.bin` — RAM-boot kernel for safe serial/U-Boot testing
- `resolved.config`, `.manifest`, `config.buildinfo` — what was actually built

## Install / recovery

- **Flash:** upload the `sysupgrade.bin` on the GL stock firmware upgrade page
  (uncheck "keep settings"), or `sysupgrade -n <image>` over SSH.
- **Recovery:** GL U-Boot failsafe — power on holding reset until the LED
  flashes, browse to `192.168.1.1`, upload stock GL firmware.
  See <https://docs.gl-inet.com/router/en/4/faq/debrick/>.

## Status / caveats

- OpenWrt PR [#24237](https://github.com/openwrt/openwrt/pull/24237) is still
  open upstream; once merged into `openwrt/openwrt` `main`, `scripts/diy.sh`
  will automatically detect the upstream recipe and skip grafting.
- Because this tracks `openwrt/openwrt` `main` (SNAPSHOT), upstream kernel
  6.18 patch refreshes or `filogic` changes can occasionally cause drift until
  PR #24237 is rebased or merged.

## Layout

```
.github/workflows/build.yml   cloud build (GitHub Actions, OpenWrt main / kernel 6.18)
scripts/diy.sh                graft PR #24237 + sanity gates + first-boot defaults
config/mt5000.config          lean seed .config
```
