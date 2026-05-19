#!/usr/bin/env bash
set -euo pipefail

# === Split tunnel: default via wg0, RU (ipset) via WAN, keep SSH stable ===
# Uses:
# - ipset "ru" (dst match) -> fwmark 0x1 -> main (WAN)
# - everything else -> table "vpn" -> wg0
# - SSH safety: inbound ssh on ens3 gets mark+connmark so replies stay on WAN
# - DNS: systemd-resolved prefers wg0 (DefaultRoute on wg0 only)

WAN_IF="eth0"
WAN_GW="10.131.0.1"
WG_IF="wg0"
WG_ENDPOINT="188.253.22.148"

TABLE_NAME="vpn"
TABLE_ID="200"
MARK_HEX="0x1"

IPSET_NAME="ru"

# For safety while testing remotely: auto-rollback after N seconds (0 disables)
ROLLBACK_AFTER_SECONDS="${ROLLBACK_AFTER_SECONDS:-0}"

need_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root"; exit 1; }; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_rt_table() {
  local rt="/etc/iproute2/rt_tables"
  grep -Eq "^[[:space:]]*${TABLE_ID}[[:space:]]+${TABLE_NAME}[[:space:]]*$" "$rt" || \
    echo "${TABLE_ID} ${TABLE_NAME}" >> "$rt"
}

flush_route_cache() { ip route flush cache >/dev/null 2>&1 || true; }

 Optional rollback if you screw up SSH during changes
arm_rollback() {
  local sec="$1"
  [[ "$sec" == "0" ]] && return 0
  ( sleep "$sec"
    ip rule del pref 200 >/dev/null 2>&1 || true
    flush_route_cache
  ) >/dev/null 2>&1 &
  echo "Rollback armed: will remove pref 200 in ${sec}s (env ROLLBACK_AFTER_SECONDS=0 to disable)."
}

ensure_ipset() {
  have_cmd ipset || { echo "ipset not installed"; exit 1; }
  ipset create "$IPSET_NAME" hash:net family inet -exist
  # NOTE: You must populate it yourself, e.g.:
  # ipset add ru 5.8.0.0/13 -exist
}

ensure_policy_routing() {
  ensure_rt_table

  # Table vpn: default via wg0
  ip route replace default dev "$WG_IF" table "$TABLE_NAME" || true

  # Ensure WireGuard endpoint ALWAYS via WAN (avoid recursion)
  ip route replace "${WG_ENDPOINT}/32" via "$WAN_GW" dev "$WAN_IF" || true

  # ip rules
  ip rule add pref 40 to 172.16.0.0/12 lookup main # docker net fix
  ip rule add pref 41 to 127.0.0.0/8 lookup main # docker net fix
  
  #ip rule add pref 42 to 172.16.0.0/12 lookup main
  #ip rule add pref 43 to 10.0.0.0/8 lookup main
  #ip rule add pref 44 to 192.168.0.0/16 lookup main
  
  ip rule add pref 50 to $WG_ENDPOINT/32 lookup main
  ip rule del pref 100 >/dev/null 2>&1 || true
  ip rule del pref 200 >/dev/null 2>&1 || true
  ip rule add pref 100 fwmark "$MARK_HEX" lookup main
  ip rule add pref 200 lookup "$TABLE_NAME"

  flush_route_cache
}

iptables_ensure_chain() {
  local table="$1" chain="$2"
  iptables -t "$table" -N "$chain" >/dev/null 2>&1 || true
  iptables -t "$table" -F "$chain"
}

iptables_ensure_jump() {
  local table="$1" hook="$2" chain="$3"
  iptables -t "$table" -D "$hook" -j "$chain" >/dev/null 2>&1 || true
  iptables -t "$table" -A "$hook" -j "$chain"
}

ensure_iptables_mangle() {
  have_cmd iptables || { echo "iptables not installed"; exit 1; }

  # Chains
  iptables_ensure_chain mangle SPLIT_OUT
  iptables_ensure_chain mangle SPLIT_PRE

  # Hook them
  iptables_ensure_jump mangle OUTPUT SPLIT_OUT
  iptables_ensure_jump mangle PREROUTING SPLIT_PRE

  # OUTPUT: restore connmark for established (symmetry)
  iptables -t mangle -A SPLIT_OUT -m conntrack --ctstate ESTABLISHED,RELATED \
    -j CONNMARK --restore-mark
  iptables -t mangle -A SPLIT_OUT -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

  # OUTPUT: WG endpoint must stay on WAN
  iptables -t mangle -A SPLIT_OUT -d "${WG_ENDPOINT}/32" -j MARK --set-mark "$MARK_HEX"
  iptables -t mangle -A SPLIT_OUT -d "${WG_ENDPOINT}/32" -j CONNMARK --save-mark

  # OUTPUT: RU destinations -> WAN (mark + persist)
  iptables -t mangle -A SPLIT_OUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$MARK_HEX"
  iptables -t mangle -A SPLIT_OUT -m set --match-set "$IPSET_NAME" dst -j CONNMARK --save-mark

  # PREROUTING: restore connmark for established (symmetry)
  iptables -t mangle -A SPLIT_PRE -m conntrack --ctstate ESTABLISHED,RELATED \
    -j CONNMARK --restore-mark
  iptables -t mangle -A SPLIT_PRE -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

  # PREROUTING: SSH safety — if SSH enters via WAN, force replies via WAN
  iptables -t mangle -A SPLIT_PRE -i "$WAN_IF" -p tcp --dport 22 -j MARK --set-mark "$MARK_HEX"
  iptables -t mangle -A SPLIT_PRE -i "$WAN_IF" -p tcp --dport 22 -j CONNMARK --save-mark
  
  iptables -t nat -I POSTROUTING 1 -m mark --mark $MARK_HEX -o $WAN_IF -j MASQUERADE
  
  # mark docker traffic to RU ipset
  # restore mark for established
  iptables -t mangle -C PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED \
    -j CONNMARK --restore-mark 2>/dev/null || \
  iptables -t mangle -A PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED \
    -j CONNMARK --restore-mark
  
  # mark docker bridges (all 172.16/12)
  iptables -t mangle -C PREROUTING -s 172.16.0.0/12 \
    -m set --match-set ru dst \
    -j MARK --set-mark 0x1 2>/dev/null || \
  iptables -t mangle -A PREROUTING -s 172.16.0.0/12 \
    -m set --match-set ru dst \
    -j MARK --set-mark 0x1

  iptables -t mangle -C PREROUTING -s 172.16.0.0/12 \
    -m set --match-set ru dst \
    -j CONNMARK --save-mark 2>/dev/null || \
  iptables -t mangle -A PREROUTING -s 172.16.0.0/12 \
    -m set --match-set ru dst \
    -j CONNMARK --save-mark
    
  # Fix incoming connections for $WAN_IF
  iptables -t mangle -A PREROUTING -i $WAN_IF -j CONNMARK --set-mark 0x1
  iptables -t mangle -A OUTPUT -m connmark --mark 0x1 -j MARK --set-mark 0x1

}

ensure_resolved_dns() {
  # Make DNS use wg0 as default-route only; keep ens3 DNS around but not default.
  if have_cmd resolvectl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    resolvectl default-route "$WAN_IF" false || true
    resolvectl default-route "$WG_IF" true || true

    # Set wg0 DNS + route all domains to wg0 resolver
    resolvectl dns "$WG_IF" 1.1.1.1 1.0.0.1 || true
    resolvectl domain "$WG_IF" "~." || true

    systemctl restart systemd-resolved || true
  fi
}

show_status() {
  echo
  echo "=== ip rule ==="
  ip rule show || true
  echo
  echo "=== table vpn ==="
  ip route show table "$TABLE_NAME" || true
  echo
  echo "=== route checks ==="
  ip route get 8.8.8.8 || true
  ip route get 8.8.8.8 mark "$MARK_HEX" || true
  ip route get "$WG_ENDPOINT" || true
  echo
  echo "=== mangle rules (summary) ==="
  iptables -t mangle -S | sed -n '1,200p' || true
  echo
  echo "Tip: populate ipset '${IPSET_NAME}' with RU nets; right now it may be empty."
}
main() {
  need_root
  arm_rollback "$ROLLBACK_AFTER_SECONDS"

  # If wg0 is down, this setup will still apply but default-vpn won't work.
  # We'll proceed anyway.
  ensure_ipset
  ensure_iptables_mangle
  ensure_policy_routing
  ensure_resolved_dns
  show_status
}

main "$@"
sudo ./update-ruips.sh && sudo ./load-custom-domains.sh && sudo ./refresh-ru-ips.sh

