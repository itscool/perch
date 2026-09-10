# Dependency and release-material review

September 10, 2026. Scope: the current Apple-silicon/macOS 26 Perch build,
its bundled code/data, installation/recovery guidance and final artifact hashes.
This review does not certify hardware support or close lifecycle/accessibility QA.

## Findings and disposition

1. **Fixed: missing BoringSSL notice.** swift-certificates depends on _CryptoExtras;
   CryptoExtras unconditionally includes CCryptoBoringSSL, also on macOS. Checking
   only Crypto's platform-conditional dependencies would miss it. Added the full
   license from the exact BoringSSL revision recorded by swift-crypto, and a
   machine-checked bundled attribution. This does not copy or install a new library.
2. **Fixed: MSI catalog notice/provenance gap.** Added msigd's full GPL v2 text,
   attribution, an explicit description of the converted editable JSON subset and
   a pinned review snapshot. The original extraction revision was not recorded;
   the review does not invent one. Perch distributes the editable JSON source.
   DDCControl-derived JSON likewise carries its license, source permalinks and
   modification notice. No GPL monitor driver program is linked into Perch.
3. **Approved owner release decision: LG table (September 10).** Scott approved
   retaining and distributing the exact table, recorded by SHA-256 in
   publication-decisions.json. This closes the project gate without claiming
   legal clearance. The following analysis preserves the underlying uncertainty. Exact installer agreement now
   inspected: see [LG-LICENSE-REVIEW.md](LG-LICENSE-REVIEW.md). It contains
   distribution restrictions and no express grant for our extracted table;
   factual-data status and contract applicability remain distinct questions.
   The 162 extracted firmware-family
   records come from proprietary OnScreen Control 7.20. The original artifact hash
   and method are recorded. Follow-up research documents a preliminary factual/
   interoperability basis for retaining the data, with compilation and contract
   applicability still unresolved; it is not a legal clearance. General
   LG website/service terms do not establish the precise license for that artifact
   and were not treated as proof either way. The owner elected retention/distribution on the documented basis. No runtime data or monitor
   behavior was removed during this review. Functional facts and protocol
   compatibility are not automatically copyrighted expression; this review does
   not make that legal determination or silently choose Perch's overall license.
4. **Fixed: release material omissions.** Support/recovery, release notes, combined
   attribution, full notices and a dependency inventory now ship as signed app
   resources. The main README's obsolete removal guidance is replaced by the
   current safety-preserving procedure. Documentation uses actual current actions.
5. **Fixed: checksum publication gap.** Previously, publishing checked artifact
   hashes from its receipt but did not validate SHA256SUMS itself or require a
   complete artifact set. The new check verifies all three expected files and the
   exact manifest, rejects symlinks and detects changed/omitted artifacts. Final
   generation happens after notarization/stapling, not against a provisional DMG.
6. **Fixed: build provenance gap.** The release source snapshot now includes
   runtime catalogs and the bundled release documents/licenses; changes to those
   inputs invalidate a prior candidate just like code changes.

## Provenance and license evidence

Release/dependencies.json pins every included license text by SHA-256 and records
origins/revisions. Package.resolved revisions match clean local checkouts for
swift-certificates 1.16.0, swift-asn1 1.4.0 and swift-crypto 4.0.0. Sparkle 2.9.6
uses its verified upstream archive and full combined license. The modified m1ddc
adapter preserves its MIT license and documents changes. NEC's MIT SDK is a
protocol reference; its notice is included without bundling the SDK.

The BoringSSL license was retrieved from:
https://github.com/google/boringssl/blob/0226f30467f540a3f62ef48d453f93927da199b6/LICENSE

MSI review snapshot and license:
https://github.com/couriersud/msigd/tree/737a84fcfeb487226309e0cd585a05a08db6014a
https://github.com/couriersud/msigd/blob/737a84fcfeb487226309e0cd585a05a08db6014a/LICENSE

DDCControl database and terms:
https://github.com/ddccontrol/ddccontrol-db/tree/1c7c3f1603332574d48b68e46dcf3d46e788de12
https://github.com/ddccontrol/ddccontrol-db/blob/1c7c3f1603332574d48b68e46dcf3d46e788de12/COPYING

NEC reference terms:
https://github.com/NECDisplaySolutions/necpdsdk/blob/0175ffdb989119df2d64d970f903509c27f35d1e/LICENSE.rst

LG provenance: catalog/LG-IDENTITY-RESEARCH.md and lg-firmware-families.json.
No proprietary LG executable is redistributed. The underlying legal uncertainty is documented separately from the owner's
approved publication decision.

The build-only dmgbuild 1.6.7 environment does not ship. Its runtime dependencies
(ds_store/mac_alias) remain build tools. Apple system frameworks/tools and fonts
are not bundled. Perch generates its own icon/installer drawing. Catalog maintenance
and the distinction between research, descriptor match and physical acceptance
are documented in catalog/NOTICE.md.

## Verification and remaining boundaries

Tools/check-release-assets.py passed on an isolated app-resource fixture: all 22
resources match, missing/truncated notices fail, unresolved review fails public
release, and invalid/changed checksum receipts are rejected. Existing staged
submission/failure tests still pass. No UI, live permissions, hardware, power,
helper installation or external publication was exercised.

A fresh signed candidate is required because the added notices/documents change
bundled resources. The earlier 1.2.89 candidate cannot be published with these
new build inputs. Final archive hashes still depend on notarization and stapling.
The catalog decision above is separate from Keychain authorization, Apple
notarization credentials and hardware/lifecycle QA; completing one does not close
the others.

Final candidate validation: 1.2.91 built with Developer ID/hardened runtime and
secure timestamps, without compiler warnings. All 22 signed resources matched
the review inventory. Publication checking correctly refused the unresolved LG
entry. Native macOS shasum accepted the generated checksum format on disposable
fixtures. A read-only existing license destination is covered by a passing
replacement regression. The installed 1.2.87 app was not replaced; candidate
notarization and public artifact checksum values remain pending.
