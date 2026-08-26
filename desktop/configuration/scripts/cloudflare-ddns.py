#!/usr/bin/env python3
"""Mirror the router's DDNS address into Cloudflare as A records.

This does NOT detect its own address, which is the usual way a DDNS client
works and would be wrong here: every packet this host sends leaves through
IVPN (rule 5209 routes anything not marked 0xca6c into the tunnel, and that
applies to root too), so asking any "what is my IP" service returns IVPN's
exit address. Binding to the physical interface does not help either. A stock
updater would cheerfully publish the VPN's address and break every name.

The router does know the real WAN address, and TP-Link's DDNS already
publishes it correctly. So the source of truth is that name, and this only
copies it across. What that buys is not redundancy but reachability: TP-Link's
NAMESERVERS are what Let's Encrypt cannot reliably query -- measured SERVFAIL
from LE on names that Google and Cloudflare both resolve fine -- and once the
address lives in Cloudflare's zone, validation never has to ask them anything.

Idempotent and quiet: it compares before it writes, so an unchanged address
costs one API read and no writes.
"""

import ipaddress
import json
import logging
import os
import socket
import sys
import urllib.error
import urllib.request

log = logging.getLogger("cloudflare-ddns")

API = "https://api.cloudflare.com/client/v4"

# The name the router keeps up to date. Read, never written.
SOURCE = os.environ.get("DDNS_SOURCE", "codebam.tplinkdns.com")
ZONE = os.environ.get("DDNS_ZONE", "codebam.ca")
# Comma-separated names within ZONE to keep pointed at SOURCE's address.
TARGETS = [t.strip() for t in os.environ.get("DDNS_TARGETS", "").split(",") if t.strip()]
# Optional escape hatch if the token lacks Zone:Read and cannot look the id up.
ZONE_ID = os.environ.get("DDNS_ZONE_ID", "")
TTL = int(os.environ.get("DDNS_TTL", "300"))


def token():
    creds = os.environ.get("CREDENTIALS_DIRECTORY")
    path = os.path.join(creds, "token") if creds else os.environ.get("DDNS_TOKEN_FILE")
    if not path:
        log.error("no credential directory and no DDNS_TOKEN_FILE; refusing to start")
        sys.exit(1)
    with open(path) as f:
        return f.read().strip()


def api(method, path, tok, body=None):
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        log.error("%s %s -> HTTP %s: %s", method, path, e.code, detail)
        return None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        log.error("%s %s -> %s", method, path, e)
        return None
    if not out.get("success"):
        log.error("%s %s -> %s", method, path, out.get("errors"))
        return None
    return out


def wan_address():
    """Resolve SOURCE to an IPv4 address, refusing anything implausible.

    A resolver failure must be a no-op, not a write: publishing a wrong or
    empty address is far worse than leaving a stale one, since a stale address
    is only wrong after the ISP changes it while a wrong one is wrong now.
    """
    try:
        infos = socket.getaddrinfo(SOURCE, None, socket.AF_INET)
    except socket.gaierror as e:
        log.error("cannot resolve %s: %s -- leaving records alone", SOURCE, e)
        return None
    addrs = {i[4][0] for i in infos}
    if len(addrs) != 1:
        log.error("%s resolved to %s; refusing to guess", SOURCE, sorted(addrs))
        return None
    addr = addrs.pop()
    ip = ipaddress.ip_address(addr)
    # A private, loopback or CGNAT answer means something is intercepting DNS
    # -- a captive portal, or the tailnet's own 100.64/10. Publishing it would
    # point the world at an address that cannot be reached from outside.
    if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
        log.error("%s resolved to non-public %s -- leaving records alone", SOURCE, addr)
        return None
    return addr


def zone_id(tok):
    if ZONE_ID:
        return ZONE_ID
    out = api("GET", f"/zones?name={ZONE}", tok)
    if not out or not out.get("result"):
        log.error("could not look up zone %s; grant the token Zone:Read or set "
                  "DDNS_ZONE_ID", ZONE)
        return None
    return out["result"][0]["id"]


def sync(tok, zid, name, addr):
    out = api("GET", f"/zones/{zid}/dns_records?name={name}", tok)
    if out is None:
        return False
    records = out.get("result", [])

    body = {"type": "A", "name": name, "content": addr, "ttl": TTL,
            # Grey cloud. Proxying would put Cloudflare's 100-second origin
            # timeout in front of an endpoint whose prompts can spend ~170s in
            # prefill before the first byte, which is a 524 for every large
            # request.
            "proxied": False}

    if not records:
        log.info("%s: creating A -> %s", name, addr)
        return api("POST", f"/zones/{zid}/dns_records", tok, body) is not None

    rec = records[0]
    if rec["type"] == "A" and rec["content"] == addr and not rec.get("proxied"):
        log.debug("%s: already %s", name, addr)
        return True

    # Covers the CNAME-to-A conversion as well as an address change: PUT
    # replaces the record wholesale, so the old type does not survive.
    log.info("%s: %s %s -> A %s", name, rec["type"], rec["content"], addr)
    return api("PUT", f"/zones/{zid}/dns_records/{rec['id']}", tok, body) is not None


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s",
                        stream=sys.stdout)
    if not TARGETS:
        log.error("DDNS_TARGETS is empty; nothing to do")
        return 1
    addr = wan_address()
    if addr is None:
        return 1
    tok = token()
    zid = zone_id(tok)
    if zid is None:
        return 1
    ok = True
    for name in TARGETS:
        ok = sync(tok, zid, name, addr) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
