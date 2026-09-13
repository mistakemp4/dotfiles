import json
import sys
import urllib.request
from pathlib import Path

from cdp_client import get_ws_url, CDP

PORT = 9333
COLORS = Path.home() / ".cache/noctalia/bitwarden-colors.json"
FONT_FAMILY = "FOT-Skip Std"

try:
    urllib.request.urlopen(f"http://localhost:{PORT}/json", timeout=2)
except OSError:
    print("bitwarden isn't running with the debug port, nothing to theme")
    sys.exit(0)

if not COLORS.exists():
    print(f"no rendered colors at {COLORS}, run: noctalia msg templates-apply")
    sys.exit(1)

c = json.loads(COLORS.read_text())


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def darken(hex_color, amount):
    return "#" + "".join(f"{round(v * (1 - amount)):02x}" for v in rgb(hex_color))


def rgb_str(hex_color):
    return " ".join(str(v) for v in rgb(hex_color))


r, g, b = rgb(c["primary"])

hex_vars = {
    "--color-bg-primary": c["surface"],
    "--color-bg-secondary": c["surface_variant"],
    "--color-bg-tertiary": c["surface_container_low"],
    "--color-bg-quaternary": c["surface_container"],
    "--color-sidenav-background": c["surface_container_low"],
    "--color-admin-sidenav-background": c["surface_container_low"],
    "--color-fg-brand": c["primary"],
    "--color-fg-brand-strong": c["primary_fixed"],
    "--color-fg-brand-soft": c["primary_fixed_dim"],
    "--color-border-brand": c["primary"],
    "--color-border-brand-strong": c["primary_fixed"],
    "--color-border-brand-soft": c["primary_container"],
    "--color-bg-brand": c["primary"],
    "--color-bg-brand-medium": c["primary_container"],
    "--color-bg-brand-soft": c["surface_container"],
    "--color-bg-brand-strong": c["primary_fixed"],
    "--color-brand-050": c["primary_fixed"], "--color-brand-100": c["primary_fixed"],
    "--color-brand-200": c["primary_fixed_dim"], "--color-brand-300": c["primary_fixed_dim"],
    "--color-brand-400": c["primary"], "--color-brand-500": c["primary"],
    "--color-brand-600": c["primary"], "--color-brand-700": c["inverse_primary"],
    "--color-brand-800": c["primary_container"], "--color-brand-900": darken(c["primary_container"], 0.35),
    "--color-brand-950": c["surface_variant"],
    "--color-fg-success": c["tertiary"], "--color-bg-success": c["tertiary_container"],
    "--color-border-success": c["tertiary"],
    "--color-fg-danger": c["red"], "--color-bg-danger": c["error"],
    "--color-border-danger": c["red"],
    "--color-fg-warning": c["secondary"], "--color-bg-warning": c["secondary_container"],
    "--color-border-warning": c["secondary"],
    "--color-fg-heading": c["on_surface"], "--color-fg-body": c["on_surface"],
    "--color-fg-contrast": c["surface"], "--color-bg-contrast": c["on_surface"],
    "--color-border-base": c["surface_container"], "--color-border-light": c["surface_variant"],
    "--color-border-muted": c["surface_container_low"], "--color-border-strong": c["outline"],
    "--color-hover-default": f"rgb({r} {g} {b} / 0.1)",
    "--color-transparent-hover": f"rgb({r} {g} {b} / 0.05)",
}

# space-separated "R G B" values, used inside rgb(var(--x) / a)
rgb_vars = {
    "--color-background": rgb_str(c["surface"]),
    "--color-background-alt": rgb_str(c["surface_variant"]),
    "--color-background-alt2": rgb_str(c["surface_container_low"]),
    "--color-background-alt3": rgb_str(c["surface_container"]),
    "--color-background-alt4": rgb_str(c["surface"]),
    "--color-text-main": rgb_str(c["on_surface"]),
    "--color-text-alt2": rgb_str(c["on_surface"]),
    "--color-text-contrast": rgb_str(c["surface"]),
    "--color-primary-300": rgb_str(c["primary"]),
    "--color-primary-600": rgb_str(c["primary"]),
    "--color-primary-700": rgb_str(c["primary_fixed"]),
    "--color-danger-600": rgb_str(c["red"]),
    "--color-success-600": rgb_str(c["tertiary"]),
    "--color-warning-600": rgb_str(c["secondary"]),
}

all_vars = {**hex_vars, **rgb_vars}
js = f"""
(() => {{
  const vars = {json.dumps(all_vars)};
  const root = document.documentElement;
  for (const [k, v] of Object.entries(vars)) {{
    root.style.setProperty(k, v);
  }}

  const styleId = 'noctalia-font-override';
  if (!document.getElementById(styleId)) {{
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = `* {{ font-family: '{FONT_FAMILY}' !important; }}`;
    document.head.appendChild(style);
  }}

  return Object.keys(vars).length;
}})()
"""

cdp = CDP(get_ws_url(PORT))
print(f"applied {cdp.evaluate(js)} overrides")

# re-run on navigation (lock screen -> vault) so it survives reloads
cdp.call("Page.enable")
cdp.call("Page.addScriptToEvaluateOnNewDocument", {"source": js})

verify = cdp.evaluate(
    "getComputedStyle(document.documentElement).getPropertyValue('--color-bg-primary').trim()"
    " + ' / ' + getComputedStyle(document.documentElement).getPropertyValue('--color-fg-brand').trim()"
)
print("verify:", verify)
cdp.close()
