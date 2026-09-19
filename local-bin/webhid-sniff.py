
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cdp_client import CDP, get_ws_url

HOOK = r"""
(() => {
  if (window.__hidHooked) return;
  // no HIDDevice outside a secure context; mark it so the tool can say why
  if (typeof HIDDevice === "undefined") {
    window.__hidUnavailable = true;
    return;
  }
  window.__hidHooked = true;
  window.__hidLog = [];

  const hex = (v) => {
    const b = v instanceof DataView
      ? new Uint8Array(v.buffer, v.byteOffset, v.byteLength)
      : new Uint8Array(v);
    return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join(" ");
  };
  const push = (dir, what, detail) =>
    window.__hidLog.push({ t: Date.now(), dir, what, ...detail });

  const D = HIDDevice.prototype;
  const origSend = D.sendReport;
  const origFeat = D.sendFeatureReport;
  const origRecv = D.receiveFeatureReport;
  const origOpen = D.open;

  D.sendReport = function (id, data) {
    push("out", "sendReport", { id, hex: hex(data) });
    return origSend.call(this, id, data);
  };
  D.sendFeatureReport = function (id, data) {
    push("out", "sendFeatureReport", { id, hex: hex(data) });
    return origFeat.call(this, id, data);
  };
  D.receiveFeatureReport = function (id) {
    return origRecv.call(this, id).then((v) => {
      push("in", "receiveFeatureReport", { id, hex: hex(v) });
      return v;
    });
  };
  D.open = function () {
    const c = this.collections && this.collections[0];
    push("--", "open", {
      product: this.productName,
      vendorId: this.vendorId,
      productId: this.productId,
      usagePage: c && c.usagePage,
      usage: c && c.usage,
    });
    this.addEventListener("inputreport", (e) => {
      push("in", "inputreport", { id: e.reportId, hex: hex(e.data) });
    });
    return origOpen.call(this);
  };

  if (navigator.hid) {
    const origReq = navigator.hid.requestDevice.bind(navigator.hid);
    navigator.hid.requestDevice = function (opts) {
      push("--", "requestDevice", { filters: JSON.stringify(opts && opts.filters) });
      return origReq(opts);
    };
  }
})();
"""

def drain(cdp):
    raw = cdp.evaluate("JSON.stringify((window.__hidLog||[]).splice(0))")
    return json.loads(raw) if raw else []

def render(entry):
    stamp = time.strftime("%H:%M:%S", time.localtime(entry["t"] / 1000))
    what = entry["what"]
    if what in ("open", "requestDevice"):
        detail = {k: v for k, v in entry.items() if k not in ("t", "dir", "what")}
        return f"{stamp} {entry['dir']} {what:20} {detail}"
    return f"{stamp} {entry['dir']} {what:20} id={entry.get('id')} {entry.get('hex','')}"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9333, help="remote debugging port")
    parser.add_argument("--title", help="only attach to a page whose title contains this")
    parser.add_argument("--out", type=Path, help="also append the log here as JSONL")
    parser.add_argument("--reload", action="store_true",
                        help="reload the page so the hook lands before its own scripts")
    args = parser.parse_args()

    try:
        cdp = CDP(get_ws_url(args.port, args.title))
    except OSError as e:
        sys.exit(f"cannot reach the debugging port {args.port}: {e}\n"
                 f"start the browser with --remote-debugging-port={args.port}")

    cdp.call("Page.enable")
    cdp.call("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK})
    cdp.evaluate(HOOK)
    if args.reload:
        cdp.call("Page.reload")
        time.sleep(2)
        cdp.evaluate(HOOK)

    if cdp.evaluate("window.__hidUnavailable === true"):
        sys.exit("this page has no WebHID: it must be https (or localhost), "
                 "and the browser must not be headless")
    if not cdp.evaluate("window.__hidHooked === true"):
        sys.exit("hook did not install -- is the right page attached? try --title")

    print(f"hooked on port {args.port}. drive the page; ctrl-c to stop.\n")
    out = args.out.open("a") if args.out else None
    try:
        while True:
            for entry in drain(cdp):
                print(render(entry), flush=True)
                if out:
                    out.write(json.dumps(entry) + "\n")
                    out.flush()
            time.sleep(0.3)
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        if out:
            out.close()
        cdp.close()

if __name__ == "__main__":
    main()
