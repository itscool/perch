# LG identification table: source-license investigation

Reviewed September 10, 2026 against Perch 819ec96 (2.0.92 candidate).
This is an engineering/provenance assessment, not a legal clearance opinion.

## Exact artifact, not general website terms

Retrieved the original [LG-hosted macOS OnScreen Control 7.20 archive](https://gscs-b2c.lge.com/downloadFile?fileId=o5c4WDQ8adFwdpgbJzDXFw),
referenced by the existing [LG support source](https://www.lge.co.kr/support/solutions-20153030707801).
The ZIP hash matches the September 7 extraction record:

- ZIP SHA-256: `d2891a3b1b5413d1d55ecb9da6182f374e6d2fb2151d3c56a1efcb7d341e68c0`
- `OSC_V7.20_signed.pkg` SHA-256: `9172474a03cc01f27c630c26120d4f2425d01ebc55a547f244747b9741e6a009`
- Installer `Resources/en.lproj/license.rtf` SHA-256: `8b032dc53fa50c7223c6d86b747fcc99070eaac0d7727aeac91c24bd616f3b1e`

Used archive extraction and `pkgutil --expand` only. No LG executable, installer
script or plugin was run, and nothing was installed. Converted the license RTF
to text locally for inspection. The archive/full agreement are research artifacts,
not new Perch resources or tracked third-party source files.

The installer agreement identifies OnScreen Control. Article 1 broadly defines
the covered software/materials; Article 2 grants limited installation/use rights.
Article 3 restricts copying, distribution and derivatives; subsection (d) restricts
reverse engineering subject to legally required exceptions. Article 4 reserves
ownership. These provisions supply no express permission to redistribute our
extracted table. Article 5 describes effectiveness from installation, whereas
the preamble also addresses use; merely finding these terms does not resolve
assent, enforceability or their application to factual interoperability data.

## Encryption does not resolve the issue

Encoding or encrypting the same table supplies no new permission and does not
change where its information came from. If Perch can recover/use the shipped
contents, the data still reaches the recipient. This is consistent with the
machine-readable-copy definition in [17 USC 101](https://www.copyright.gov/title17/92chap1.html#101).
Encryption may protect confidential data, but is not a distribution-license solution.

## Facts versus an extracted collection

The [US Copyright Office database guidance](https://www.copyright.gov/register/tx-databases.html)
excludes individual facts and purely mechanical organization from protection,
while explaining that original compilation authorship can be protected.
[17 USC 102(b) and 103(b)](https://www.copyright.gov/title17/92chap1.html#102)
separate methods/facts from protectable expression and compilation contributions.
These principles may support reuse of factual protocol information; they do not
by themselves establish the legal status of this entire extracted collection.
[17 USC 1201(f)](https://www.copyright.gov/title17/92chap12.html#1201)
provides a conditional interoperability exception, not blanket permission to
redistribute any reverse-engineered database. Applicable contracts/jurisdictions
remain separate questions for qualified legal review if retaining this source.

Do not equate an absent permissive license with proof that the individual
identifiers are copyrighted, or assume every hardware fact needs LG permission.
Likewise, do not claim the license gives an affirmative redistribution right.

## Actual Perch dependency and replacement scope

Static source/data inspection found:

- 162 extracted firmware-family records; eight entries link to four distinct
  operational profiles. The remaining entries only supply family-name labels.
- A separate catalog has 20 LG monitor profiles, including owner-confirmed
  USB-C code 209 for the local 27UN850-W. Public hardware reports also document
  that input code: [ddcutil LG switching research](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors).
- Current `DeskRuntime.refreshDisplays` uses `MonitorProfiles.match`;
  `DeskRuntime.inspect` merges monitor-reported inputs. Neither calls
  `LGFirmwareProfiles`. Its consumers are the older inspection/model-selection
  workflow and regression tests. Removing it would not directly remove the
  current Desk's switching transport or its separate LG profiles.
- An owner's observed raw ID and confirmed retail model/input are evidence we
  can record independently. The extracted firmware-family label is a different
  fact and must not be relabeled as independently established merely because
  the raw query was tested on hardware.

Recommended engineering path: replace the extracted family lookup with a small,
explicitly evidenced observation catalog (or omit that optional lookup), preserve
the separately sourced input profiles/control code and explicit mappings, and
keep manual identification for unknown devices. Add mappings from actual device
observations with consent and documented provenance; no background upload or
hardware experiment is implied. Do not merely reformat or encrypt all 162 rows
and call that an independent replacement.

Alternative if retaining all extracted rows matters: obtain written LG permission
covering the dataset/distribution, or qualified legal review establishing the
specific factual/interoperability basis. No request has been sent to LG.

## Disposition

The exact-license investigation is complete. The public-release issue remains
open pending a retention/removal decision and its implementation or clearance.
This pass did not remove monitor support, alter the catalog, change the signed
candidate, waive the publication check or rewrite repository history.
