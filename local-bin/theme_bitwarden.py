from cdp_client import get_ws_url, CDP
import json

url = get_ws_url(9333)
c = CDP(url)

# hex-formatted custom properties
hex_vars = {
    "--color-bg-primary": "#29141e",
    "--color-bg-secondary": "#371b28",
    "--color-bg-tertiary": "#1c0e15",
    "--color-bg-quaternary": "#452132",
    "--color-sidenav-background": "#221119",
    "--color-admin-sidenav-background": "#221119",
    "--color-fg-brand": "#e467a4",
    "--color-fg-brand-strong": "#f4bed8",
    "--color-fg-brand-soft": "#ec93be",
    "--color-border-brand": "#e467a4",
    "--color-border-brand-strong": "#f4bed8",
    "--color-border-brand-soft": "#85144b",
    "--color-bg-brand": "#e467a4",
    "--color-bg-brand-medium": "#85144b",
    "--color-bg-brand-soft": "#452132",
    "--color-bg-brand-strong": "#f4bed8",
    "--color-brand-050": "#f4bed8", "--color-brand-100": "#f4bed8",
    "--color-brand-200": "#ec93be", "--color-brand-300": "#ec93be",
    "--color-brand-400": "#e467a4", "--color-brand-500": "#e467a4",
    "--color-brand-600": "#e467a4", "--color-brand-700": "#c94d8a",
    "--color-brand-800": "#85144b", "--color-brand-900": "#5c0e33",
    "--color-brand-950": "#371b28",
    "--color-fg-success": "#96e9de", "--color-bg-success": "#166a5f",
    "--color-border-success": "#96e9de",
    "--color-fg-danger": "#fd4663", "--color-bg-danger": "#8f0118",
    "--color-border-danger": "#fd4663",
    "--color-fg-warning": "#e9e696", "--color-bg-warning": "#ccc966",
    "--color-border-warning": "#e9e696",
    "--color-fg-heading": "#f3f2f2", "--color-fg-body": "#f3f2f2",
    "--color-fg-contrast": "#29141e", "--color-bg-contrast": "#f3f2f2",
    "--color-border-base": "#452132", "--color-border-light": "#371b28",
    "--color-border-muted": "#221119", "--color-border-strong": "#716269",
    "--color-hover-default": "rgb(228 103 164 / 0.1)",
    "--color-transparent-hover": "rgb(228 103 164 / 0.05)",
}

# space-separated "R G B" formatted custom properties (used inside rgb(var(--x) / a))
rgb_vars = {
    "--color-background": "41 20 30",
    "--color-background-alt": "55 27 40",
    "--color-background-alt2": "34 17 25",
    "--color-background-alt3": "69 33 50",
    "--color-background-alt4": "41 20 30",
    "--color-text-main": "243 242 242",
    "--color-text-alt2": "243 242 242",
    "--color-text-contrast": "41 20 30",
    "--color-primary-300": "228 103 164",
    "--color-primary-600": "228 103 164",
    "--color-primary-700": "244 190 216",
    "--color-danger-600": "253 70 99",
    "--color-success-600": "150 233 222",
    "--color-warning-600": "233 230 150",
}

all_vars = {**hex_vars, **rgb_vars}
js = f"""
(() => {{
  const vars = {json.dumps(all_vars)};
  const root = document.documentElement;
  for (const [k, v] of Object.entries(vars)) {{
    root.style.setProperty(k, v);
  }}
  return Object.keys(vars).length;
}})()
"""
count = c.evaluate(js)
print(f"applied {count} overrides")

# also register the same script to auto-run on every future navigation
# within this page (e.g. lock screen -> vault), so it survives reloads
c.call("Page.enable")
c.call("Page.addScriptToEvaluateOnNewDocument", {"source": js})

# verify a couple actually stuck
verify = c.evaluate(
    "getComputedStyle(document.documentElement).getPropertyValue('--color-bg-primary').trim()"
    " + ' / ' + getComputedStyle(document.documentElement).getPropertyValue('--color-background').trim()"
)
print("verify:", verify)
c.close()
