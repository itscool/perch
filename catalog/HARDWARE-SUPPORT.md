# Perch 1.1 hardware catalog

Reviewed 2026-09-07. These are exact identity/layout and input-code records, **not a list of hardware certified in Perch**. There are 93 monitor entries (some are alternate identities of one model) and 28 keyboard profiles (some are layout variants). Catalogs are bounded in size, are read once, and add no polling or input-event work.

## How support is determined

- Monitor: prefer an existing user mapping; then an exact documented model mapping; then reported input capabilities; manual configuration and explicit compatibility testing are fallback paths. A successful write is not proof that the screen changed.
- The standard input-source query and capabilities do not provide a reliable per-port list of connected computers. Perch keeps the user's selected cycle list. No input is silently skipped as disconnected.
- Discovery preserves codes, labels, order and selection. Newly discovered ports are unchecked. Generic USB-C codes are not invented. Exact retail names are extracted from bounded capabilities replies when present; generic names still require model selection.
- Keyboard: exact vendor/product/name/transport and required descriptor usages must match. User-learned layouts override bundled layouts. Actual event-source attribution is checked separately; unknown sources pass through unchanged.
- Stock QMK/Keychron layouts do not prove host control of firmware Fn layers. VIA/custom firmware changes require setup. Receiver product IDs are not paired keyboard IDs, so direct Bluetooth profiles do not match a receiver blindly.

## Monitor records

DDCControl inputsource overrides are preferred over their generic capabilities, including Samsung's different write codes. The C49RG9x record marks input control as write-only: cycling requires explicit last-command fallback, and Perch does not treat its readback as switch verification. Each database entry retains its source URL. The DDCControl data license is bundled in `ddccontrol-COPYING.txt`. LG model reports can be partial; only explicitly reported ports are included. The local owner confirmed 27UN850-W USB-C **209**, not 210; this does not certify every cable or direction.

| Model / identity | Inputs (decimal command codes) |
|---|---|
| ASUS TUF VG27AQ | HDMI 1 = 17, HDMI 2 = 18, DisplayPort = 15 |
| ASUS VP28U | HDMI 1 = 17, HDMI 2 = 18, DisplayPort 1 = 15 |
| BenQ GW2480 | VGA = 1, DisplayPort = 15, HDMI = 17 |
| BenQ GW2283 | VGA = 1, HDMI 1 = 17, HDMI 2 = 18 |
| Dell U2720Q | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2720QM | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2723QE (HDMI HDR) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2723QE (HDMI) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2723QE (DisplayPort1) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U3223QE (HDMI HDR) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U3223QE (DP HDR) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2718 (HDMI) | Mini DisplayPort = 16, DisplayPort = 15, HDMI = 17 |
| Dell U2718 (DP/mDP) | Mini DisplayPort = 16, DisplayPort = 15, HDMI = 17 |
| LG UltraGear 27GL850 | DisplayPort 1 = 15, HDMI 1 = 17, HDMI 2 = 18 |
| LG HDR 4K (shared GSM7706 identity) | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 210 |
| LG 27UN850-W / 27UN850-WY | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 209 |
| LG 27UP850-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 209 |
| LG 27UP85NP-W | DisplayPort = 208, USB-C = 209 |
| LG 32UD99-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 224, USB-C = 192 |
| LG 29UM69G | HDMI 1 = 144, DisplayPort = 192, USB-C = 224 |
| LG 40WP95C-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 209 |
| ASUS MG28U | DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18, HDMI 3 = 19 |
| Acer P226HQV | VGA = 1, DVI = 3 |
| Acer B196L | VGA = 1, DVI = 3, DisplayPort = 15 |
| Acer Nitro XV273K | DisplayPort 1 = 15, DisplayPort 2 = 16, HDMI 1 = 17 |
| ACER VG270U P | DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| Acer KA242Y | VGA = 1, HDMI = 17 |
| Acer Predator XB273U | DisplayPort 1 = 15, HDMI 1 = 17, HDMI 2 = 18 |
| AOC 2260 | VGA = 1, HDMI = 3, DisplayPort = 4 |
| AOC 2269 | VGA = 1, HDMI 1 = 3, HDMI 2 = 4 |
| AOC 2343 | VGA = 1, DVI = 3 |
| AOC 2401 | VGA = 1, DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| AOC Q3279VWF | VGA = 1, DVI = 3, HDMI = 17, DisplayPort = 15 |
| BenQ GL2460 | VGA = 1, DVI = 3, HDMI = 17 |
| BENQ XL2411P | DVI = 3, DisplayPort = 15, HDMI = 17 |
| BenQ BL2410 | VGA = 1, DVI = 3, DisplayPort = 15 |
| Dell Ultrasharp u3011 | VGA = 1, DVI 1 = 3, DVI 2 = 4, Component = 12, DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| Dell Ultrasharp u3011 | VGA = 1, DVI 1 = 3, DVI 2 = 4, Component = 12, DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| DELL S2718D | HDMI = 17, USB-C = 27 |
| Dell U2518D | DisplayPort = 15, Mini DisplayPort = 16, HDMI = 17 |
| Dell UltraSharp U2719D | DisplayPort = 15, Mini DisplayPort = 16, HDMI = 17 |
| DELL S2721DGFA | HDMI 1 = 17, HDMI 2 = 18, DisplayPort = 15 |
| Dell U2721DE | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U4021QW | USB-C = 25, DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| Dell P3223DE (USB-C) | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell Pro Plus P3225QE | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2412M (DVI) | VGA = 1, DVI = 3, DisplayPort = 15 |
| Dell U2414H (HDMI 1) | DisplayPort = 15, Mini DisplayPort = 16, HDMI 1 = 17, HDMI 2 = 18 |
| Dell U3415W (DP) | DisplayPort = 15, Mini DisplayPort = 16, HDMI = 17, HDMI / MHL = 18 |
| Dell U2415 (DisplayPort1) | DisplayPort 1 = 15, DisplayPort 2 = 16, HDMI 1 = 17, HDMI 2 = 18 |
| Dell P2415Q | Mini DisplayPort = 16, DisplayPort = 15, HDMI / MHL = 17 |
| Dell P2417H (DisplayPort) | VGA = 1, DisplayPort = 15, HDMI = 17 |
| Dell U3818DW (DisplayPort) | HDMI 1 = 17, HDMI 2 = 18, DisplayPort = 15, USB-C = 27 |
| Dell U3219Q | HDMI 1 = 17, DisplayPort = 15, USB-C = 27 |
| Dell U3219Q | HDMI 1 = 17, DisplayPort = 15, USB-C = 27 |
| Dell U2520D | USB-C = 27, DisplayPort = 15, HDMI = 17 |
| Dell U2715H (HDMI 2) | DisplayPort = 15, Mini DisplayPort = 16, HDMI 1 = 17, HDMI 2 = 18 |
| Dell U2515H | DisplayPort = 15, Mini DisplayPort = 16, HDMI 1 = 17, HDMI 2 = 18 |
| HP 27h 737K9AA (DisplayPort) | VGA = 1, HDMI = 17, DisplayPort = 15 |
| Iiyama PLE2483H | DVI 1 = 3, HDMI 1 = 17, VGA 1 = 1 |
| Iiyama X2483HSU | DVI 1 = 3, HDMI 1 = 17, VGA 1 = 1 |
| iiyama PL2791Q | DVI = 3, DisplayPort = 15, HDMI = 17 |
| Iiyama GB3461WQSU (HDMI) | HDMI 1 = 17, HDMI 2 = 18, DisplayPort 1 = 15, DisplayPort 2 = 16 |
| Iiyama GB3466WQSU (DP) | HDMI 1 = 17, HDMI 2 = 18, DisplayPort 1 = 15, DisplayPort 2 = 16 |
| Iiyama PL3494WQ | DisplayPort = 15, USB-C = 16, HDMI = 17 |
| Philips 221P6Q | VGA = 1, DVI = 3, DisplayPort = 15 |
| Philips BDM3270QP | VGA = 1, DVI = 3, DisplayPort = 15, HDMI = 17 |
| Samsung C27HG70 | HDMI 1 = 5, HDMI 2 = 6, DisplayPort = 9 |
| C49RG9x | DisplayPort 2 = 3, HDMI = 6, DisplayPort 1 = 9 |
| Samsung Odyssey G5 | DisplayPort = 9, HDMI = 6 |
| Sony INZONE M9 (SDM-U27M90) | DisplayPort 1 = 15, DisplayPort 2 = 16, HDMI 1 = 17, HDMI 2 = 18 |
| ViewSonic VG2253 | VGA = 1, DisplayPort = 15, Mini DisplayPort = 16, HDMI = 17 |
| LG 27BN88Q-B | HDMI 1 = 144, DisplayPort = 208 |
| LG 27UK500-B | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 27UL550-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 27US500-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 29WN600 | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 29U531A | HDMI 1 = 144, DisplayPort = 208, USB-C = 209 |
| LG 32GP750-B | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 32GP850-B | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 34WN750-B | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 38BR85QC | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 209 |
| LG 40U990A-W | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208 |
| LG 45GX950A-B | HDMI 1 = 144, HDMI 2 = 145, DisplayPort = 208, USB-C = 209 |

| AOC 24G2 / 24G2U / 24B2XDAM | VGA = 1, DisplayPort = 15, HDMI 1 = 17, HDMI 2 = 18 |
| Dell P2416D | VGA = 1, DisplayPort = 15, HDMI 1 = 17 |
| Dell 2408WFP (DVI) | VGA = 1, DVI 1 = 3, DVI 2 = 4, Composite = 5, S-Video = 7, Component = 12 |
| Dell 2007FP (DVI) | VGA = 1, DVI = 3, Composite = 5, S-Video = 7 |
| Dell U2410f | VGA = 1, DVI 1 = 3, DVI 2 = 4, Composite = 5, Component = 12, DisplayPort = 15, HDMI = 17 |
| Dell Ultrasharp u2410 (Rev A02) | VGA = 1, DVI 1 = 3, DVI 2 = 4, DisplayPort = 15, HDMI = 17, Component = 12, Composite = 5 |
| Dell S2316M (DVI) | VGA = 1, DVI = 3 |
| ViewSonic VSCBD44 | VGA = 1, HDMI = 17 |
| LC-Power M34 Curved Gaming Monitor | DisplayPort = 7, HDMI 1 = 5, HDMI 2 = 18, HDMI 3 = 19 |

## Keyboard records

QMK identity and stock keymap facts are sourced at revision `08c662f286ddfd12a985f57b584b02eca5af0ae6`; the source URLs are embedded per profile. No firmware is installed. The upstream firmware is GPL-2.0-or-later; distribution license review remains part of 1.2. Logitech facts retain their Solaar/manufacturer links.

| Layout | Transport | Vendor:product | Navigation keys in stock layout |
|---|---|---|---|
| Logitech MX Keys | Bluetooth, Bluetooth Low Energy | 046d:b35b | Home, End, Page Up, Page Down |
| Logitech Craft | Bluetooth, Bluetooth Low Energy | 046d:b350 | Home, End, Page Up, Page Down |
| Logitech G915 TKL | USB | 046d:c343 | Home, End, Page Up, Page Down |
| Logitech G213 | USB | 046d:c336 | Home, End, Page Up, Page Down |
| Logitech G512 | USB | 046d:c33c | Home, End, Page Up, Page Down |
| Logitech G815 | USB | 046d:c33f | Home, End, Page Up, Page Down |
| Logitech K845 | USB | 046d:c341 | Home, End, Page Up, Page Down |
| Logitech MX Keys S | Bluetooth, Bluetooth Low Energy | 046d:b378 | Home, End, Page Up, Page Down |
| Keychron V3 ansi | USB | 3434:0330 | Home, End, Page Up, Page Down |
| Keychron V3 ansi encoder | USB | 3434:0331 | Home, End, Page Up, Page Down |
| Keychron V3 iso | USB | 3434:0332 | Home, End, Page Up, Page Down |
| Keychron V3 iso encoder | USB | 3434:0333 | Home, End, Page Up, Page Down |
| Keychron V5 ansi | USB | 3434:0350 | Home, End, Page Up, Page Down |
| Keychron V5 ansi encoder | USB | 3434:0351 | Home, End |
| Keychron V5 iso | USB | 3434:0352 | Home, End, Page Up, Page Down |
| Keychron V5 iso encoder | USB | 3434:0353 | Home, End |
| Keychron V6 ansi | USB | 3434:0360 | Home, End, Page Up, Page Down |
| Keychron V6 ansi encoder | USB | 3434:0361 | Home, End, Page Up, Page Down |
| Keychron V6 iso | USB | 3434:0362 | Home, End, Page Up, Page Down |
| Keychron V6 iso encoder | USB | 3434:0363 | Home, End, Page Up, Page Down |
| Keychron Q5 ansi | USB | 3434:0150 | Home, End, Page Up, Page Down |
| Keychron Q5 ansi encoder | USB | 3434:0151 | Home, End |
| Keychron Q5 iso | USB | 3434:0152 | Home, End, Page Up, Page Down |
| Keychron Q5 iso encoder | USB | 3434:0153 | Home, End |
| Keychron Q6 ansi | USB | 3434:0160 | Home, End, Page Up, Page Down |
| Keychron Q6 ansi encoder | USB | 3434:0161 | Home, End, Page Up, Page Down |
| Keychron Q6 iso | USB | 3434:0162 | Home, End, Page Up, Page Down |
| Keychron Q6 iso encoder | USB | 3434:0163 | Home, End, Page Up, Page Down |

## Deliberately not assumed

Q3 descriptors lacking an explicit product string, Bluetooth/receiver variants without exact descriptors, theoretical LG firmware compatibility without a model code report, and ambiguous generic entries are not expanded into automatic matches. More profiles can be added with concrete evidence; entry counts are not a support guarantee.

## Remaining physical verification

Automated fixtures cover malformed/missing replies, saved-map preservation, model matching, write-code overrides, explicit single-command tests and cancellation, keyboard transport boundaries and descriptor requirements. They cannot certify real display switching or keyboard delivery. Confirm both monitor directions, reconnect/restart, and external navigation versus built-in Fn+arrows using Perch. New monitor writes occur only on user action.

LG's public OnScreen Control documentation and the source-linked LG side-channel findings were reviewed. No reliable universal retail-model or connected-input query was established. The proprietary application was not installed or run, and its implementation is not claimed as inspected.

Follow-up: [static LG package inspection](LG-IDENTITY-RESEARCH.md) found proprietary ID reads and a 27UN850 firmware-model entry. The earlier uninspected-app limitation above is superseded; live identification remains unverified.

## Additional control transports

The 23 MSI version/identity input profiles in `msi-input-profiles.json` are separate from the 93 DDC records. A native USB backend checks this allowlist per operation. Native USB MCCS and NEC TCP/serial input control are also implemented, with explicit connection setup. Their physical hardware validation remains outstanding; packet, routing and UI tests use fixtures. See `MONITOR-INPUTS.md`.
