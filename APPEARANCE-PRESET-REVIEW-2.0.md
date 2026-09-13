# Appearance option/preset review — September 13, 2026

New options: edge-to-edge drawing, independent left/right fades. Related controls
share rows; System title belongs to Titles & shape. Side borders and corner
rounding are suppressed in edge mode, preserving their saved values for return.
Fades affect only decoration, never title text or menu-item hit areas.

| Preset | Decision after option changes |
| --- | --- |
| Perch original | Keep the exact user-specified values. |
| Quiet | Keep undecorated text and hidden System heading; fading an absent decoration adds nothing. |
| Signal | Keep bold left rails; edge mode would remove its defining feature. |
| Soft tiles | Keep rounded full-section fills; edge mode would remove the card treatment. |
| Outline | Keep complete rounded frames and clear interiors; side borders are essential. |
| Ribbon | Revise to full-width title bands with both edges fading, paired horizontal rules and separate Light/Dark tint strengths. |
| Horizon | Add greyscale full-section washes with an overline, a fading right edge, normal title text and no icons. |

Eight palettes remain independent from these seven compositions. Every option
change requires another full built-in preset review; this is now in AGENTS.md
and the reusable settings-flow skill.

Verification: production offscreen renderer checks serialization, stable preset
identities, original preservation, edge-mode side/radius suppression and recovery,
and independent/batch theme edits. New preset title contrast is checked in both
themes against preview backgrounds. Preview images are visual evidence, not
native control-interaction acceptance. The existing appearance regression suite also passes in the nonpresenting renderer: isolated persistence/reopen, validation and corruption preservation, theme independence, preset saving/removal, and responsive preview bounds. Actual live settings were not changed.

Preview focus/backdrop refinement: all seven presets were retained after reviewing
both scopes in Light/Dark. This changes the inspection surface, not the saved
style options. Full System readings and neighboring colored rows remain in real
menu order; the fixed mid-tone backdrop reveals each menu edge independently
of the Settings window theme.
