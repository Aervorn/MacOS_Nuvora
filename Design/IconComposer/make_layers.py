"""Calques de l'icône de Nuvora pour Icon Composer (macOS 26).

Un N en ruban (bleu ciel → bleu → violet) et une pastille « M↓ » (Markdown), sur un fond clair
ou nuit selon l'apparence. Ce script écrit les calques ici, copie dans Nuvora/AppIcon.icon/Assets
ceux qu'utilise l'icône, écrit Nuvora/AppIcon.icon/icon.json (fond clair et fond sombre) et assemble
Design/Nuvora-icon.svg et Design/Nuvora-icon-dark.svg (icônes complètes, pour le README et le site).

    python3 Design/IconComposer/make_layers.py

Pour ajuster une forme ou une teinte, modifier les valeurs ci-dessous et relancer le script.
"""
import json
import shutil
from pathlib import Path

HERE = Path(__file__).parent
ICON = HERE.parent.parent / "Nuvora" / "AppIcon.icon"
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'

# Fond : presque blanc en clair, nuit en sombre
LIGHT_TOP, LIGHT_BOTTOM = "#FFFFFF", "#E9ECFF"
DARK_TOP, DARK_BOTTOM = "#262B45", "#11152A"

# Le N : jambe gauche (bleu ciel), diagonale (bleu → indigo), jambe droite (violet)
LEFT_TOP, LEFT_BOTTOM = "#2E97FF", "#22C1FF"
DIAG_START, DIAG_END = "#2E9BFF", "#4A46F2"
RIGHT_TOP, RIGHT_BOTTOM = "#A070FF", "#5A46F5"

# Pastille Markdown
BADGE_TOP, BADGE_BOTTOM = "#333D5E", "#1E2540"
BADGE_INK = "#FFFFFF"


def n_layer():
    return HEAD + f"""  <defs>
    <linearGradient id="left" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{LEFT_TOP}"/><stop offset="1" stop-color="{LEFT_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="diag" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="{DIAG_START}"/><stop offset="0.55" stop-color="#3566FA"/><stop offset="1" stop-color="{DIAG_END}"/>
    </linearGradient>
    <linearGradient id="right" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{RIGHT_TOP}"/><stop offset="1" stop-color="{RIGHT_BOTTOM}"/>
    </linearGradient>
  </defs>
  <!-- Jambe droite : sommet en pointe arrondie -->
  <path fill="url(#right)" d="M 664 440 C 664 318 742 212 822 204 C 846 202 860 216 860 240 L 860 760 C 860 790 840 806 812 806 L 664 806 Z"/>
  <!-- Jambe gauche : bas arrondi, qui remonte vers l'intérieur -->
  <path fill="url(#left)" d="M 158 400 C 158 300 214 236 296 234 L 364 420 L 364 640 C 364 742 300 806 214 812 C 180 814 158 796 158 762 Z"/>
  <!-- Diagonale : part du sommet arrondi de la jambe gauche et descend jusqu'au pied de la jambe droite -->
  <path fill="url(#diag)" d="M 158 400 C 158 296 222 234 310 234 C 372 234 414 258 452 306 L 860 806 L 664 806 L 364 438 L 364 404 L 158 404 Z"/>
</svg>
"""


def badge_layer():
    # Pastille en bas à droite, avec la marque Markdown : un M et une flèche vers le bas
    x, y, w, h, r = 606, 598, 318, 262, 62
    m_left, m_top, m_bottom = x + 58, y + 74, y + h - 74
    m_w, stroke = 100, 25
    ax = x + w - 82   # axe de la flèche
    m = (f"M {m_left} {m_bottom} L {m_left} {m_top} L {m_left + m_w / 2} {m_top + 62} "
         f"L {m_left + m_w} {m_top} L {m_left + m_w} {m_bottom}")
    arrow = (f"M {ax} {m_top} L {ax} {m_bottom - 14} M {ax - 42} {m_bottom - 50} L {ax} {m_bottom - 8} "
             f"L {ax + 42} {m_bottom - 50}")
    return HEAD + f"""  <defs>
    <linearGradient id="badge" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BADGE_TOP}"/><stop offset="1" stop-color="{BADGE_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#badge)"/>
  <rect x="{x + 1.5}" y="{y + 1.5}" width="{w - 3}" height="{h - 3}" rx="{r - 1.5}" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="3"/>
  <g fill="none" stroke="{BADGE_INK}" stroke-width="{stroke}" stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="6">
    <path d="{m}"/>
    <path d="{arrow}"/>
  </g>
</svg>
"""


def background(top, bottom):
    return HEAD + f"""  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
</svg>
"""


LAYERS = {
    # Fond : référence seulement (dans l'icône, c'est le dégradé de fond d'Icon Composer)
    "1-fond.svg": background(LIGHT_TOP, LIGHT_BOTTOM),
    "1-fond-sombre.svg": background(DARK_TOP, DARK_BOTTOM),
    "2-n.svg": n_layer(),
    "3-markdown.svg": badge_layer(),
}


def hex_to_p3(hex_color):
    """Couleur hexadécimale en « display-p3:r,g,b,a » (approximation sRGB)."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},1.00000"


ICON_JSON = {
    # Fond clair par défaut, fond nuit en apparence sombre (macOS gère aussi les styles transparent et teinté)
    "fill-specializations": [
        {"value": {"linear-gradient": [hex_to_p3(LIGHT_TOP), hex_to_p3(LIGHT_BOTTOM)]}},
        {"appearance": "dark", "value": {"linear-gradient": [hex_to_p3(DARK_TOP), hex_to_p3(DARK_BOTTOM)]}},
    ],
    "groups": [
        {
            "layers": [{"image-name": "3-markdown.svg", "name": "3-markdown"}],
            "name": "Markdown",
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0.5},
        },
        {
            "layers": [{"image-name": "2-n.svg", "name": "2-n"}],
            "name": "N",
            "shadow": {"kind": "neutral", "opacity": 0.4},
            "translucency": {"enabled": True, "value": 0.15},
        },
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}


def composite(fond, dark):
    """Icône complète en un seul SVG (README, site) : calques superposés, coins arrondis comme sur macOS."""
    def inner(svg, suffix):
        body = svg.split("\n", 1)[1].rsplit("</svg>", 1)[0]
        # Chaque calque garde ses propres dégradés : identifiants rendus uniques
        for name in ["bg", "left", "diag", "right", "badge"]:
            body = body.replace(f'id="{name}"', f'id="{name}{suffix}"').replace(f"url(#{name})", f"url(#{name}{suffix})")
        return body

    shadow = ('  <filter id="soft" x="-20%" y="-20%" width="140%" height="150%">'
              '<feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#1B1F5C" '
              f'flood-opacity="{0.45 if dark else 0.28}"/></filter>\n')
    return (HEAD + '  <clipPath id="squircle"><rect width="1024" height="1024" rx="229"/></clipPath>\n' + shadow
            + '  <g clip-path="url(#squircle)">\n' + inner(LAYERS[fond], "0")
            + '  <g filter="url(#soft)">\n' + inner(LAYERS["2-n.svg"], "1") + "  </g>\n"
            + '  <g filter="url(#soft)">\n' + inner(LAYERS["3-markdown.svg"], "2") + "  </g>\n"
            + "  </g>\n</svg>\n")


if __name__ == "__main__":
    assets = ICON / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    for old in assets.glob("*.svg"):
        old.unlink()
    for old in ["2-liens.svg", "3-cartes.svg"]:
        (HERE / old).unlink(missing_ok=True)
    for name, svg in LAYERS.items():
        (HERE / name).write_text(svg, encoding="utf-8")
        if not name.startswith("1-fond"):
            shutil.copy(HERE / name, assets / name)
    (ICON / "icon.json").write_text(json.dumps(ICON_JSON, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (HERE.parent / "Nuvora-icon.svg").write_text(composite("1-fond.svg", False), encoding="utf-8")
    (HERE.parent / "Nuvora-icon-dark.svg").write_text(composite("1-fond-sombre.svg", True), encoding="utf-8")
    print("Calques écrits dans", HERE)
    print("Icône :", ICON)
