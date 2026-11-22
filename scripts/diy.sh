#!/usr/bin/env bash
# Graft the GL-MT5000 device support and in-tree kernel 6.18 RTL8366UB DSA +
# MediaTek PPE offload series (OpenWrt PR #24237) onto official OpenWrt main.
# Run with CWD = OpenWrt source root.
set -euo pipefail

KVER=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/mediatek/Makefile)
test -n "$KVER" || { echo ">> ERROR: failed to detect KERNEL_PATCHVER"; exit 1; }

BOARDD=target/linux/mediatek/filogic/base-files/etc/board.d/02_network
PLATSH=target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh
FILOGIC_MK=target/linux/mediatek/image/filogic.mk
KCFG="target/linux/mediatek/filogic/config-${KVER}"
DTS=target/linux/mediatek/dts/mt7987a-glinet-gl-mt5000.dts

# --- 1. Graft PR #24237 onto official OpenWrt main (if not yet merged) -----
if grep -q "glinet_gl-mt5000" "$FILOGIC_MK"; then
	echo ">> GL-MT5000 already present in upstream OpenWrt main (kernel ${KVER}); skipping graft"
else
	echo ">> Grafting GL-MT5000 + RTL8366UB DSA/PPE series (PR #24237) onto OpenWrt main (kernel ${KVER})"
	git config user.email build@local
	git config user.name mt5000-build
	git remote add glinet "${GL_DEVICE_COMMIT:-https://github.com/GLiNet-Tech/openwrt.git}" 2>/dev/null || true
	git fetch --filter=blob:none glinet mt5000

	# If invoked on a shallow clone, fetch enough history so merge-base succeeds.
	if ! BASE=$(git merge-base HEAD glinet/mt5000 2>/dev/null); then
		echo ">> Shallow clone detected; unshallowing commit graph for merge-base"
		git fetch --filter=blob:none --unshallow origin
		BASE=$(git merge-base HEAD glinet/mt5000)
	fi

	mapfile -t PR_COMMITS < <(git rev-list --reverse "${BASE}..glinet/mt5000")
	if [ "${#PR_COMMITS[@]}" -eq 0 ]; then
		echo ">> ERROR: no commits found in ${BASE}..glinet/mt5000"
		exit 1
	fi
	echo ">> Applying ${#PR_COMMITS[@]} commit(s) from PR #24237 (base ${BASE:0:12})"

	for sha in "${PR_COMMITS[@]}"; do
		subj=$(git log -1 --format='%h %s' "$sha")
		echo "   -> $subj"
		if ! git cherry-pick -n "$sha"; then
			# Upstream main frequently adds new boards adjacent to glinet,gl-mt5000
			# in board.d/02_network's ("lan1 lan2" eth1) case arm. Auto-resolve ONLY
			# that trivial additive conflict; fail loudly on any other conflict.
			mapfile -t UNMERGED < <(git diff --name-only --diff-filter=U)
			if [ "${#UNMERGED[@]}" -eq 1 ] && [ "${UNMERGED[0]}" = "$BOARDD" ]; then
				echo "   -> resolving additive board.d/02_network case-arm conflict"
				git checkout --ours "$BOARDD"
				if ! grep -q 'glinet,gl-mt5000' "$BOARDD"; then
					perl -0pi -e 's/^(\ttplink,tl-xdr6086\|\\)$/\tglinet,gl-mt5000|\\\n$1/m' "$BOARDD"
				fi
				git add "$BOARDD"
				rm -f .git/CHERRY_PICK_HEAD .git/MERGE_MSG
			else
				echo ">> ERROR: cherry-pick conflict on $subj:"
				git status -s
				git cherry-pick --abort 2>/dev/null || true
				exit 1
			fi
		fi
	done
	echo ">> graft OK"
fi

# --- 2. Sanity gates (each can actually fail) ------------------------------
test -f "$DTS" || { echo ">> ERROR: DTS missing ($DTS)"; exit 1; }
grep -q "realtek,rtl8366ub" "$DTS" || { echo ">> ERROR: rtl8366ub switch node missing from DTS"; exit 1; }
grep -q "glinet_gl-mt5000" "$FILOGIC_MK" || { echo ">> ERROR: device recipe missing from $FILOGIC_MK"; exit 1; }
grep -q "^CONFIG_NET_DSA_REALTEK_RTL8366UB=y" "$KCFG" || { echo ">> ERROR: CONFIG_NET_DSA_REALTEK_RTL8366UB=y missing from $KCFG"; exit 1; }
grep -q "glinet,gl-mt5000" "$BOARDD" || { echo ">> ERROR: glinet,gl-mt5000 missing from $BOARDD"; exit 1; }
sh -n "$BOARDD" || { echo ">> ERROR: $BOARDD has a shell syntax error"; exit 1; }
test "$(grep -c 'glinet,gl-mt5000' "$PLATSH")" -ge 2 || { echo ">> ERROR: glinet,gl-mt5000 missing from platform_do_upgrade or platform_copy_config in $PLATSH"; exit 1; }
sh -n "$PLATSH" || { echo ">> ERROR: $PLATSH has a shell syntax error"; exit 1; }

# --- 3. First-boot defaults ------------------------------------------------
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-gl-mt5000 <<'UCI'
#!/bin/sh
uci -q batch <<-EOF
	set system.@system[0].hostname='GL-MT5000'
	set system.@system[0].timezone='WET0WEST,M3.5.0/1,M10.5.0'
	set system.@system[0].zonename='Europe/Lisbon'
	commit system
EOF
exit 0
UCI

echo ">> diy.sh complete (OpenWrt main, kernel ${KVER})"
