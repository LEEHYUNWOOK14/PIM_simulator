# Thermal model sources

This directory records inputs for an **architectural, non-signoff** model.

- HotSpot: architectural compact thermal solver, pinned at `f18831e48cef5d62580585cca0d7fab6c71bc3cc` — https://github.com/uvahotspot/HotSpot
- 3D-ICE: transient thermal simulation for 3D ICs, pinned at `4953952a1ef6d38807ff307212a6f15e5b2ef935` — https://github.com/esl-epfl/3d-ice
- HBM stack geometry: JSTS HBM modeling study (32 um silicon die, 15 um gap) — https://jsts.org/jsts/XmlViewer/f436715
- Silicon conductivity context: NIST Monograph 131 — https://nvlpubs.nist.gov/nistpubs/Legacy/MONO/nbsmonograph131.pdf
- Copper conductivity context: NIST thermal-conductivity reference — https://www.nist.gov/publications/thermal-conductivity-aluminum-copper-iron-and-tungsten-temperatures-1-k-melting-point

Exact vendor package construction, material curves, boundary conditions, and calibrated power are unavailable. Every such input is marked estimated or illustrative in the JSON configuration.
