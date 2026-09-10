# LG identification table: source-license investigation

Reviewed September 10, 2026; source investigation began against Perch 819ec96
(2.0.92 candidate). Follow-up research and Desk integration are recorded below.
This is an engineering/provenance assessment, not a legal clearance opinion.

Assessment: retain the table while resolving the specific release question.
There is a credible factual/interoperability argument for keeping it; the earlier
replace/omit recommendation was too categorical. Public related research exists,
but this search did not find a full independently licensed replacement.

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

## Who else publishes related information?

There is substantial independent public LG research, but this search did not find
an independently published, clearly licensed equivalent of all 162 numeric
firmware-ID-to-family mappings. This is a bounded search result, not proof that
nobody else possesses the data.

| Primary source | Available information | Relation to our table |
| --- | --- | --- |
| [ddcutil LG input switching wiki](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors) | Model-specific input codes and device reports, including USB-C variants | Supports operational profiles; not a complete firmware-ID decoder |
| [shinyquagsire23 LG MStar research](https://gist.github.com/shinyquagsire23/7ddd17d1569acb21920683866570cb35) | Documents extended-ID opcode A1, possible EF identity, and model-name paths on researched hardware | Independently corroborates additional identity mechanisms, not all numeric mappings |
| [David Zech's firmware research](https://blog.davidzech.com/discovering-a-revoked-lg-monitor-firmware-file-22b2252e0c5e) | Analyzes OnScreen Control and LG firmware naming/download structure | Shows overlapping research; does not supply our full table or permission for it |
| [David Manouchehri's 49WL95C-W research](https://blogger.davidmanouchehri.com/2020/01/how-smart-is-my-monitor-part-1.html) | Device-specific monitor investigation, linked by ddcutil | Another independent research lead, not a replacement table |

Exact web/GitHub code searches included `27UL850-RTK`, `27UP850-L2`,
`27UN850-L2L`, `isFWUpdateSupported`, `getMonitorExtendId`, and LG/0x5124.
Targeted searches covered public MonitorControl, Lunar and ddcutil code. They
found overlapping command/profile information rather than the complete mapping.
The GitHub search API rate-limited the fwupd search; that is not a negative result.
A subsequent web-index search likewise did not locate an equivalent fwupd table.
Unindexed code, private implementations and future publications remain unknown.
Public availability is not itself a reuse license; newly found code/text still
needs its own provenance review. No third-party implementation was copied here.

## Stronger basis for retaining factual interoperability data

The earlier recommendation to replace/omit the table was too one-sided. Lack of
an express license from a proprietary source does not establish that factual
mappings require permission, and independently rediscovering every fact is not
necessarily required by copyright law.

- [Feist v. Rural, 499 U.S. 340 (1991)](https://tile.loc.gov/storage-services/service/ll/usrep/usrep499/usrep499340/usrep499340.pdf)
  distinguishes facts from original compilation authorship. Labor collecting
  facts does not alone create copyright. Protectable selection/arrangement does
  not extend ownership to underlying facts; mechanical ordering is insufficient.
- [Sega v. Accolade, 977 F.2d 1510](https://law.justia.com/cases/federal/appellate-courts/F2/977/1510/305345/)
  supports intermediate disassembly to reach otherwise inaccessible functional
  requirements for a legitimate interoperability purpose. Its conditions matter;
  it does not immunize copied protected expression in the finished product.
- [SAS Institute v. World Programming, Fourth Circuit (2017)](https://www.ca4.uscourts.gov/opinions/161808.P.pdf)
  illustrates the separate contract question: the court upheld liability under
  an agreed license's reverse-engineering/use restrictions and vacated the
  copyright ruling as moot. That does not establish LG's terms bind this research,
  but shows why copyright analysis alone does not dispose of an applicable EULA.

Application to Perch is an engineering inference, not a court finding: the rows
associate functional numeric IDs with short firmware-family names; the JSON is
mechanically ordered and includes no LG executable or explanatory prose. That
is a plausible factual/interoperability basis for retention. The operational
profile links and their input-code evidence are separately recorded by Perch.
We should not label the collection protected merely because it was extracted.
Conversely, copying all rows requires assessing any original selection or
arrangement, not just observing that each individual value is functional.
The 154 label-only records have a less direct switching benefit than the eight
records linked to input profiles.

Remaining questions are narrow: what protection, if any, applies to this exact
collection; whether any agreement was accepted and applies to the extraction;
and which law applies to planned distribution. The recorded method used static
extraction without installing/running LG software or clicking its installer
agreement. That is relevant evidence, not a categorical ruling on assent.
These U.S. decisions do not establish worldwide clearance or resolve every
possible database/contract claim. No access-control circumvention is documented
in the extraction record; interoperability exceptions are not being used as a
blanket substitute for analyzing what actually happened.

Engineering recommendation: retain the table and its honest provenance while
resolving the specific release question. There is now an affirmative basis to
assess, rather than an assumption that deletion or LG permission is mandatory.
Written permission or a focused legal assessment could resolve the remaining
uncertainty; neither has been obtained. Do not claim clearance, fabricate a
permissive license, encrypt away provenance, or relabel extracted labels as
independently observed facts. The existing public-release gate stays open.

## Actual usefulness and the missed Desk integration

Static source/data inspection found 162 firmware-family records; eight link to
four distinct operational profiles. A separate catalog contains 20 LG profiles.
The owner's 27UN850-W independently returned raw EF 0x5124 and uses USB-C 209.
The extracted table labels that ID `27UL850-RTK`: firmware family is not retail
model, and neither is unique physical-screen identity.

Before this correction, the older inspection/model-selection workflow consumed
`LGFirmwareProfiles`, but the replacement Desk setup did not. Desk retained the
transport and catalog without the identification-to-profile path. This was a
feature-parity oversight, not an intentional legal restriction or lack of value.
Generic LG identities can otherwise offer a profile with USB-C 210 when the
owner-evidenced profile needs 209.

Desk now carries raw EF/A1 results in transient detected-display metadata,
including peer advertisements. Add or identify a screen offers the locally
cataloged firmware profile as a suggestion with a family explanation. Users can
select another profile or detected inputs. A late suggestion preserves explicit
choices, invalidates an incompatible selected port, and never edits an existing
saved screen. Ordinary refresh retains identity only for the same detected
device descriptor. Unknown/unsupported IDs preserve manual setup. Add screen
saves the selected input and protocol; it does not switch the monitor.

Firmware family is deliberately excluded from shared-screen matching. Two
identical models stay distinct unless the user confirms a physical match. EF/A1
reads remain part of explicit setup inspection, not periodic idle polling. This
pass does not add live hardware probes or proprietary executable dependencies.

## Validation and disposition

The isolated functional build compiled without compiler warnings. The targeted
reset-isolation suite passed, including new Desk checks for normal/extended IDs,
manual overrides, detected-input opt-out, unknown IDs, vendor filtering, peer
metadata round-trip, refresh/replacement identity, actual add-screen persistence,
LG protocol selection and distinct identical screens.

Under AGENT MODE, real native clicks exercised Add screen with an injected LG
HDR 4K/0x5124 display: suggested 27UN850 profile; USB-C 209; opt-out clearing the
incompatible port and disabling Add; restoring the suggestion; naming/saving;
immediate third-screen and USB-C mapping; reopening and closing setup without
losing the saved screen. This validates native interaction with simulated
hardware, not a fresh live monitor read or physical switch. The pass also exposed
a duplicated refresh-error message. A subsequent click check found a second
copy in the outer sheet host; the final source correction leaves the host's
message and suppresses identical child errors. That last deduplication was
compiled and statically checked; it has not had another native click pass.

The settings-flow-review skill now requires tracing retained capabilities through
replacement journeys, including ambiguous devices and delayed suggestions.

The table remains intact. The installer agreement/full LG artifacts remain local
research files. No LG contact, live hardware change, installation, notarization,
public release, publication-gate waiver or repository-history rewrite was made.

Prepared candidate: Developer ID signed 2.0.94, zero compiler warnings. The
production build's signature/resource checks passed. It has not been installed,
notarized or published. 2.0.92/2.0.93 candidates are superseded for this correction.
