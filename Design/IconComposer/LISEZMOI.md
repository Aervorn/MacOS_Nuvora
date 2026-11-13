# Calques pour Icon Composer

Calques de l'icône de Nuvora pour Icon Composer (macOS 26), générés par `make_layers.py`.
Tous sur le même canevas de 1024 × 1024, à pleine taille : ils se superposent sans réglage.
L'icône elle-même est `Nuvora/AppIcon.icon` (à ouvrir dans Icon Composer pour l'ajuster).

| Fichier | Contenu | Dans l'icône |
|---|---|---|
| `1-fond.svg` | Dégradé presque blanc | Référence : fond d'Icon Composer en apparence claire (#FFFFFF → #E9ECFF) |
| `1-fond-sombre.svg` | Dégradé nuit | Référence : fond d'Icon Composer en apparence sombre (#262B45 → #11152A) |
| `2-n.svg` | Le N en ruban : bleu ciel, bleu, violet | Groupe « N » |
| `3-markdown.svg` | Pastille sombre « M↓ » (Markdown) | Groupe « Markdown », au-dessus |

Pas de coins arrondis, d'ombre ni de reflet : macOS les ajoute lui-même. Le fond change avec
l'apparence (clair / sombre) et macOS adapte aussi l'icône aux styles transparent et teinté.

`Design/Nuvora-icon.svg` et `Design/Nuvora-icon-dark.svg` sont l'icône complète, pour le README et le site.
