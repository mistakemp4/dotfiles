#!/usr/bin/env python3
import re
import sys
from pathlib import Path

DEFAULTS = Path("/usr/share/fontforge/pixmaps/resources")
OUT = Path(__file__).resolve().parents[1] / "config/noctalia/templates/fontforge.resource"

KEY_RULES = [
    (r"(View|DebugView|Splash)\.Background$|^Gdraw\.Background$", "surface"),
    (r"GScrollBarThumb\.Box\.(Normal|Disabled)Foreground$", "outline"),
    (r"GScrollBarThumb\.Box\.", "outline_variant"),
    (r"GScrollBar\.Box\.", "surface_container"),
    (r"WarningForeground$|MissingLabelColor$|MissingBitmapColor$|CloseColor$|FrozenCol$", "error"),
    (r"DisabledForeground$", "outline"),
    (r"FontView\.SelectedFgColor$", "on_primary"),
    (r"FontView\.SelectedColor$|MetricsView\.SelectedGlyphColor$|GProgress\.FillColor$|ActiveBorder$|ActiveCol$"
     r"|On\.Box\.PressedBackground$|GDefaultButton\.Box\.Border(Brightest|Brighter|Darker|Darkest)$", "primary"),
    (r"ActiveBG$|GDefaultButton\.Box\.BorderOuterCol$", "primary_container"),
    (r"GlyphInfoColor$|HintingNeededColor$", "secondary"),
    (r"ShowAtt\.GlyphNameColor$|Histogram\.GraphColor$", "primary"),
    (r"ChangedColor$|KernLineColor$", "tertiary"),
    (r"Popup\.Background$|TitleBG$|GradientStartCol$", "surface_container_highest"),
    (r"(GButton|GMatrixEditButton)\.Box\.NormalBackground$", "surface_container_high"),
    (r"(GTextField|GList|GMenu|GGroup|GMatrixEdit)\.Box\.(Normal|Disabled)Background$", "surface_container_low"),
    (r"CVPaletteBackgroundColor$|MeasureToolWindowBackground$", "surface_container"),
    (r"Button3DEdgeDarkColor$", "surface_container_lowest"),
    (r"UnencodedLabelColor$", "on_surface_variant"),
    (r"SlotDivisionColor$|EmptySlotFgColor$|DividerColor$|TitleDivider$|RuleCol$|Button3DEdgeLightColor$", "outline_variant"),
    (r"CoordinateLineColor$|GuideOutlineColor$|ItalicCoordColor$|OriginLineColor$|SideBearingLineColor$"
     r"|AdvanceWidthColor$|ItalicAdvanceColor$|BitmapView\.(GuideColor|WidthGuideColor|GridColor|Reference(Border)?Color|BitmapColor)$", "outline"),
    (r"Foreground$|GlyphFGColor$|LabelColor$|TextColor$|GlyphColor$|ForegroundOutlineColor$|WidthColor$|GuideDragColor$"
     r"|TransformOriginColor$|MeasureToolLineColor$|OverviewColor$|SlotOutlineColor$|TitleFG$|CVPaletteForegroundColor$", "on_surface"),
]
HEX_ROLES = {
    "surface_container": "edeceb e5e4e3 e6e6e3 e6e3e3 e3e6e6 ffffff",
    "outline_variant": "f9f8f7 fcfbfa f1f0ef dddcdb dedede ededed",
    "outline": "908f8e adacab 757371 999996 b2b2b0 8f9199 999999 7d8080",
    "on_surface": "222222 000000",
    "primary": "88b2de 598ec6",
    "primary_container": "bcd2ea",
}
HEX_ROLE = {h: role for role, hexes in HEX_ROLES.items() for h in hexes.split()}

out, unmapped = [], []
for line in DEFAULTS.read_text().splitlines():
    m = re.match(r"^(\S+):\s*#([0-9a-fA-F]{6})\s*$", line)
    if not m:
        out.append(line)
        continue
    key, hex_ = m.group(1), m.group(2).lower()
    role = next((r for pat, r in KEY_RULES if re.search(pat, key)), None)
    if role is None and key.startswith("Gdraw."):
        role = HEX_ROLE.get(hex_)
    if role is None:
        if key.startswith("Gdraw."):
            unmapped.append(line)
        out.append(line)
        continue
    out.append(f"{key}: {{{{colors.{role}.default.hex}}}}")
OUT.write_text("\n".join(out) + "\n")
print(f"wrote {OUT}", file=sys.stderr)
for line in unmapped:
    print("unmapped:", line, file=sys.stderr)
