# Third-party components in Perch

Reviewed September 10, 2026. Full license texts and notices are in
Perch.app/Contents/Resources. dependencies.json lists pinned versions, revisions
and the license-file checksums verified by the build.

| Component | Version / revision | Distribution and terms |
| --- | --- | --- |
| Sparkle | 2.9.6 | Embedded framework/helpers. Sparkle-LICENSE.txt includes MIT and the bundled bsdiff, sais-lite, Ed25519 and verifier notices. |
| m1ddc routing adapter | 04d949794102eb8df01ad3681afff6464a3eede2 | Selected Objective-C sources, MIT; m1ddc-LICENSE.txt. Perch modifies enumeration checks, temporary-object cleanup and the 16-display bound. |
| swift-certificates | 1.16.0 | Static X509 library, Apache-2.0; LICENSE and NOTICE included. |
| swift-asn1 | 1.4.0 | Static ASN.1 support, Apache-2.0; LICENSE and NOTICE included. |
| swift-crypto | 4.0.0 | Static Crypto/CryptoExtras support, Apache-2.0; LICENSE and NOTICE included. |
| BoringSSL | 0226f30467f540a3f62ef48d453f93927da199b6 | Transitive CryptoExtras dependency, including on macOS. BoringSSL-LICENSE.txt contains its full upstream terms. Swift Crypto supplies renamed/prefixed vendored sources. |
| DDCControl database | 1c7c3f1603332574d48b68e46dcf3d46e788de12 | Selected, modified JSON input records; GNU GPL v2. Full license and editable data included. |
| msigd data | Review snapshot 737a84fcfeb487226309e0cd585a05a08db6014a | Selected firmware/input facts in JSON; GNU GPL v2 for imported records. Full license included. No msigd executable/HID library included. |
| NEC PD SDK reference | 0175ffdb989119df2d64d970f903509c27f35d1e | Protocol reference, MIT notice included. Perch implements its own restricted transport; no Python SDK is bundled. |

catalog-NOTICE.md describes data changes, editable source locations and the
unresolved redistribution review for LG's extracted firmware-family table.
Adding a copyright notice alone does not resolve that review.

Apple frameworks, CryptoKit, eslogger and macOS system tools are supplied by macOS;
Perch does not redistribute them. The build-only Python dmgbuild tool (1.6.7,
MIT) and its Python dependencies are not inside Perch or the disk image. Build
fonts use macOS system rendering; no font file is redistributed. The bird icon
and installer artwork are generated from Perch's own vector drawing code.

Sources:
- https://github.com/sparkle-project/Sparkle/tree/2.9.6
- https://github.com/waydabber/m1ddc/tree/04d949794102eb8df01ad3681afff6464a3eede2
- https://github.com/apple/swift-certificates/tree/1.16.0
- https://github.com/apple/swift-asn1/tree/1.4.0
- https://github.com/apple/swift-crypto/tree/4.0.0
- https://github.com/google/boringssl/tree/0226f30467f540a3f62ef48d453f93927da199b6
