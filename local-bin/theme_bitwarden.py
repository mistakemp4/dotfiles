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


def rgba(hex_color, alpha):
    r, g, b = rgb(hex_color)
    return f"rgb({r} {g} {b} / {alpha})"


hex_vars = {
    "--color-bg-primary": c["surface"],
    "--color-bg-secondary": c["surface_variant"],
    "--color-bg-tertiary": c["surface_container_low"],
    "--color-bg-quaternary": c["surface_container"],
    "--color-sidenav-background": c["surface_container_low"],
    "--color-admin-sidenav-background": c["surface_container_low"],
    "--color-sidenav-active-item": c["surface_container_high"],
    "--color-sidenav-item-hover": c["surface_container_high"],
    "--color-admin-sidenav-active-item": c["surface_container_high"],
    "--color-admin-sidenav-item-hover": c["surface_container_high"],
    "--color-sidenav-text": c["on_surface"],
    "--color-admin-sidenav-text": c["on_surface"],
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
    "--color-fg-body-subtle": c["on_surface_variant"],
    "--color-fg-disabled": c["outline"],
    "--color-fg-contrast": c["surface"], "--color-bg-contrast": c["on_surface"],
    "--color-bg-dark": c["surface_container_low"],
    "--color-bg-gray": c["outline_variant"],
    "--color-bg-disabled": c["surface_container_lowest"],
    "--color-bg-overlay": rgba(c["surface_container_lowest"], 0.65),
    "--color-border-base": c["surface_container"], "--color-border-light": c["surface_variant"],
    "--color-border-muted": c["surface_container_low"], "--color-border-strong": c["outline"],
    "--color-border-buffer": c["surface"],
    "--color-border-focus": c["primary"],
    "--color-hover-default": rgba(c["primary"], 0.1),
    "--color-transparent-hover": rgba(c["primary"], 0.05),
    # tailwind gray ramp, light (050) to dark (950)
    "--color-gray-050": c["on_surface"], "--color-gray-100": c["on_surface"],
    "--color-gray-200": c["on_surface_variant"], "--color-gray-300": c["on_surface_variant"],
    "--color-gray-400": c["on_surface_variant"], "--color-gray-500": c["outline"],
    "--color-gray-600": c["outline_variant"], "--color-gray-700": c["surface_container_highest"],
    "--color-gray-800": c["surface_container_high"], "--color-gray-900": c["surface_container_low"],
    "--color-gray-950": c["surface_container_lowest"],
    "--tw-ring-offset-color": c["surface"],
    "--tw-ring-color": rgba(c["primary"], 0.5),
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
    "--color-text-muted": rgb_str(c["on_surface_variant"]),
    "--color-primary-100": rgb_str(c["primary_container"]),
    "--color-primary-300": rgb_str(c["primary"]),
    "--color-primary-600": rgb_str(c["primary"]),
    "--color-primary-700": rgb_str(c["primary_fixed"]),
    "--color-secondary-100": rgb_str(c["surface_container"]),
    "--color-secondary-300": rgb_str(c["outline_variant"]),
    "--color-secondary-500": rgb_str(c["outline"]),
    "--color-secondary-600": rgb_str(c["on_surface_variant"]),
    "--color-secondary-700": rgb_str(c["on_surface_variant"]),
    "--color-info-100": rgb_str(c["primary_container"]),
    "--color-info-600": rgb_str(c["primary_fixed_dim"]),
    "--color-info-700": rgb_str(c["primary_fixed"]),
    "--color-danger-600": rgb_str(c["red"]),
    "--color-success-600": rgb_str(c["tertiary"]),
    "--color-warning-600": rgb_str(c["secondary"]),
}

# bitwarden's older "html.theme_dark ..." rules use fixed colors instead of variables,
# so each of those colors ("r,g,b") is swapped for a palette color
legacy_map = {
    "19,21,24": c["surface_container_lowest"],
    "21,24,30": c["surface"],
    "26,28,33": c["surface_container_low"],
    "31,36,46": c["surface_variant"],
    "36,39,46": c["surface_container"],
    "37,40,47": c["surface_container"],
    "39,43,50": c["surface_container"],
    "47,52,61": c["surface_container"],
    "60,66,78": c["surface_container_high"],
    "76,82,95": c["outline_variant"],
    "110,118,137": c["outline"],
    "110,120,138": c["outline"],
    "141,148,165": c["on_surface_variant"],
    "156,165,185": c["on_surface"],
    "168,176,193": c["on_surface_variant"],
    "186,192,206": c["on_surface_variant"],
    "255,255,255": c["on_surface"],
    "83,138,238": c["primary_fixed_dim"],
    "111,157,241": c["primary"],
    "164,176,198": c["primary_fixed_dim"],
    "82,224,124": c["tertiary"],
    "255,235,102": c["secondary"],
    "255,112,102": c["error"],
    "255,141,133": c["red"],
}

JS_TEMPLATE = r"""
(() => {
  const vars = __VARS__;
  const legacy = __LEGACY__;
  const font = __FONT__;
  const root = document.documentElement;
  for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v);

  const upsertStyle = (id, css) => {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('style');
      el.id = id;
      (document.head || root).appendChild(el);
    }
    el.textContent = css;
  };
  upsertStyle('noctalia-font-override', `* { font-family: '${font}' !important; }`);

  const PROPS = ['background-color', 'background', 'color', 'fill', 'outline-color', 'box-shadow',
    'border-color', 'border-top-color', 'border-bottom-color', 'border-left-color', 'border-right-color'];

  const parse = (tok) => {
    let r, g, b, a = 1;
    if (tok[0] === '#') {
      let h = tok.slice(1);
      if (h.length === 3 || h.length === 4) h = h.split('').map(x => x + x).join('');
      r = parseInt(h.slice(0, 2), 16); g = parseInt(h.slice(2, 4), 16); b = parseInt(h.slice(4, 6), 16);
      if (h.length === 8) a = parseInt(h.slice(6, 8), 16) / 255;
    } else {
      const n = tok.match(/[\d.]+/g);
      if (!n || n.length < 3) return null;
      [r, g, b] = n.slice(0, 3).map(Number);
      if (n.length > 3) a = Number(n[3]);
    }
    return { key: `${r},${g},${b}`, alpha: a };
  };

  const withAlpha = (hex, a) => {
    const h = hex.slice(1);
    return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`;
  };

  const remap = () => {
    const out = [];
    const walk = (rules) => {
      for (const r of rules) {
        if (r.cssRules && !r.selectorText) { walk(r.cssRules); continue; }
        if (!r.selectorText || !r.style || !r.selectorText.includes('theme_dark')) continue;
        const decls = [];
        for (const p of PROPS) {
          const v = r.style.getPropertyValue(p);
          if (!v || v.includes('var(')) continue;
          let changed = false;
          const nv = v.replace(/#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)/g, (tok) => {
            const c = parse(tok);
            if (!c || !(c.key in legacy)) return tok;
            changed = true;
            return c.alpha < 1 ? withAlpha(legacy[c.key], c.alpha) : legacy[c.key];
          });
          if (changed) decls.push(`${p}: ${nv} !important`);
        }
        if (decls.length) out.push(`${r.selectorText} { ${decls.join('; ')} }`);
      }
    };
    for (const s of document.styleSheets) {
      if (s.ownerNode && s.ownerNode.id && s.ownerNode.id.startsWith('noctalia-')) continue;
      try { walk(s.cssRules); } catch (e) {}
    }
    upsertStyle('noctalia-legacy-remap', out.join('\n'));
    return out.length;
  };

  const count = remap();
  // on a fresh page the stylesheets aren't loaded yet, so remap again once they are
  if (document.readyState !== 'complete') window.addEventListener('load', remap, { once: true });
  return `${Object.keys(vars).length} vars, ${count} legacy rules remapped`;
})()
"""

js = (JS_TEMPLATE
      .replace("__VARS__", json.dumps({**hex_vars, **rgb_vars}))
      .replace("__LEGACY__", json.dumps(legacy_map))
      .replace("__FONT__", json.dumps(FONT_FAMILY)))

cdp = CDP(get_ws_url(PORT))
print("applied:", cdp.evaluate(js))

# re-run on navigation (lock screen -> vault) so it survives reloads
cdp.call("Page.enable")
cdp.call("Page.addScriptToEvaluateOnNewDocument", {"source": js})

verify = cdp.evaluate(
    "[document.body, document.querySelector('.vault > .items'), document.querySelector('.vault .footer')]"
    ".map(e => e ? getComputedStyle(e).backgroundColor : 'n/a').join(' | ')"
)
print("verify (body | items | footer):", verify)
cdp.close()
