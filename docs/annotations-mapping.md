# annotations/ — old-to-new file mapping

Mapping of every file currently released under
`current.geneontology.org/annotations/` (old pipeline) to its
counterpart in the June "pipeline switch" release.

## Layout shift

Old: flat dir, files named per upstream **resource** (`fb`, `cgd`,
`goa_human`, ...). Three formats per dataset (`.gaf.gz`,
`.gpad.gz`, `.gpi.gz`) — except for two aggregate UniProt files.

```
annotations/
├── {dataset}.gaf.gz
├── {dataset}.gpad.gz
└── {dataset}.gpi.gz
```

New: three subdirs by format, files named per **organism** (UniProt
five-letter mnemonic) with `-mod` or `-uniprot` suffix encoding the
ID space. All 171 organisms have a `-uniprot` flavor; the 23
MOD-managed organisms additionally have a `-mod` flavor.

```
annotations/
├── gaf/   MNEMONIC-mod.gaf.gz   (23) + MNEMONIC-uniprot.gaf.gz   (171)
├── gpad/  MNEMONIC-mod.gpad.gz  (23) + MNEMONIC-uniprot.gpad.gz  (171)
└── gpi/   MNEMONIC-mod.gpi.gz   (23) + MNEMONIC-uniprot.gpi.gz   (171)
```

## File-by-file mapping

For each old file, the closest-equivalent new file(s).

### Per-MOD aggregates → MNEMONIC-mod (1:1 or 1:N)

These old files aggregated all annotations managed by a given MOD;
the new layout splits them per organism.

| Old file                              | New file(s)                                                                                                                                                                                                                                                                                                                  |
|---------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `cgd.gaf.gz`                          | `gaf/CANAL-mod.gaf.gz`, `gaf/CANCO-mod.gaf.gz`, `gaf/CANDC-mod.gaf.gz`, `gaf/CANGB-mod.gaf.gz`, `gaf/CANPA-mod.gaf.gz`, `gaf/CANTI-mod.gaf.gz`, `gaf/CLALU-mod.gaf.gz`, `gaf/DEBHA-mod.gaf.gz`, `gaf/LODEL-mod.gaf.gz`, `gaf/PICGU-mod.gaf.gz`                                                                                 |
| `cgd.gpad.gz`                         | same 10 mnemonics under `gpad/*-mod.gpad.gz`                                                                                                                                                                                                                                                                                 |
| `cgd.gpi.gz`                          | same 10 mnemonics under `gpi/*-mod.gpi.gz`                                                                                                                                                                                                                                                                                   |
| `dictybase.gaf.gz`                    | `gaf/DICDI-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `dictybase.gpad.gz`                   | `gpad/DICDI-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `dictybase.gpi.gz`                    | `gpi/DICDI-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `ecocyc.gaf.gz`                       | `gaf/ECOLI-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `ecocyc.gpad.gz`                      | `gpad/ECOLI-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `ecocyc.gpi.gz`                       | `gpi/ECOLI-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `fb.gaf.gz`                           | `gaf/DROME-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `fb.gpad.gz`                          | `gpad/DROME-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `fb.gpi.gz`                           | `gpi/DROME-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `japonicusdb.gaf.gz`                  | `gaf/SCHJY-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `japonicusdb.gpad.gz`                 | `gpad/SCHJY-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `japonicusdb.gpi.gz`                  | `gpi/SCHJY-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `mgi.gaf.gz`                          | `gaf/MOUSE-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `mgi.gpad.gz`                         | `gpad/MOUSE-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `mgi.gpi.gz`                          | `gpi/MOUSE-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `pombase.gaf.gz`                      | `gaf/SCHPO-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `pombase.gpad.gz`                     | `gpad/SCHPO-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `pombase.gpi.gz`                      | `gpi/SCHPO-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `rgd.gaf.gz`                          | `gaf/RAT-mod.gaf.gz`                                                                                                                                                                                                                                                                                                         |
| `rgd.gpad.gz`                         | `gpad/RAT-mod.gpad.gz`                                                                                                                                                                                                                                                                                                       |
| `rgd.gpi.gz`                          | `gpi/RAT-mod.gpi.gz`                                                                                                                                                                                                                                                                                                         |
| `sgd.gaf.gz`                          | `gaf/YEAST-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `sgd.gpad.gz`                         | `gpad/YEAST-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `sgd.gpi.gz`                          | `gpi/YEAST-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `tair.gaf.gz`                         | `gaf/ARATH-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `tair.gpad.gz`                        | `gpad/ARATH-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `tair.gpi.gz`                         | `gpi/ARATH-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `wb.gaf.gz`                           | `gaf/CAEEL-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `wb.gpad.gz`                          | `gpad/CAEEL-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `wb.gpi.gz`                           | `gpi/CAEEL-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |
| `xenbase.gaf.gz`                      | `gaf/XENLA-mod.gaf.gz`, `gaf/XENTR-mod.gaf.gz`                                                                                                                                                                                                                                                                               |
| `xenbase.gpad.gz`                     | `gpad/XENLA-mod.gpad.gz`, `gpad/XENTR-mod.gpad.gz`                                                                                                                                                                                                                                                                           |
| `xenbase.gpi.gz`                      | `gpi/XENLA-mod.gpi.gz`, `gpi/XENTR-mod.gpi.gz`                                                                                                                                                                                                                                                                               |
| `zfin.gaf.gz`                         | `gaf/DANRE-mod.gaf.gz`                                                                                                                                                                                                                                                                                                       |
| `zfin.gpad.gz`                        | `gpad/DANRE-mod.gpad.gz`                                                                                                                                                                                                                                                                                                     |
| `zfin.gpi.gz`                         | `gpi/DANRE-mod.gpi.gz`                                                                                                                                                                                                                                                                                                       |

### Old MOD-named, now UniProt-sourced → MNEMONIC-uniprot only

These datasets had MOD-style filenames in the old pipeline but
their organisms are listed in `goex.yaml` with `group: UniProt`,
so the new pipeline ships only a `-uniprot` flavor — no `-mod`.

| Old file                              | New file                          |
|---------------------------------------|-----------------------------------|
| `genedb_lmajor.gaf.gz`                | `gaf/LEIMA-uniprot.gaf.gz`        |
| `genedb_lmajor.gpad.gz`               | `gpad/LEIMA-uniprot.gpad.gz`      |
| `genedb_lmajor.gpi.gz`                | `gpi/LEIMA-uniprot.gpi.gz`        |
| `genedb_pfalciparum.gaf.gz`           | `gaf/PLAF7-uniprot.gaf.gz`        |
| `genedb_pfalciparum.gpad.gz`          | `gpad/PLAF7-uniprot.gpad.gz`      |
| `genedb_pfalciparum.gpi.gz`           | `gpi/PLAF7-uniprot.gpi.gz`        |
| `genedb_tbrucei.gaf.gz`               | `gaf/TRYB2-uniprot.gaf.gz`        |
| `genedb_tbrucei.gpad.gz`              | `gpad/TRYB2-uniprot.gpad.gz`      |
| `genedb_tbrucei.gpi.gz`               | `gpi/TRYB2-uniprot.gpi.gz`        |
| `pseudocap.gaf.gz`                    | `gaf/PSEAE-uniprot.gaf.gz`        |
| `pseudocap.gpad.gz`                   | `gpad/PSEAE-uniprot.gpad.gz`      |
| `pseudocap.gpi.gz`                    | `gpi/PSEAE-uniprot.gpi.gz`        |
| `sgn.gaf.gz`                          | `gaf/SOLLC-uniprot.gaf.gz`        |
| `sgn.gpad.gz`                         | `gpad/SOLLC-uniprot.gpad.gz`      |
| `sgn.gpi.gz`                          | `gpi/SOLLC-uniprot.gpi.gz`        |

### goa_* per-organism UniProt sets → MNEMONIC-uniprot

| Old file                              | New file                          |
|---------------------------------------|-----------------------------------|
| `goa_chicken.gaf.gz`                  | `gaf/CHICK-uniprot.gaf.gz`        |
| `goa_chicken.gpad.gz`                 | `gpad/CHICK-uniprot.gpad.gz`      |
| `goa_chicken.gpi.gz`                  | `gpi/CHICK-uniprot.gpi.gz`        |
| `goa_cow.gaf.gz`                      | `gaf/BOVIN-uniprot.gaf.gz`        |
| `goa_cow.gpad.gz`                     | `gpad/BOVIN-uniprot.gpad.gz`      |
| `goa_cow.gpi.gz`                      | `gpi/BOVIN-uniprot.gpi.gz`        |
| `goa_dog.gaf.gz`                      | `gaf/CANLF-uniprot.gaf.gz`        |
| `goa_dog.gpad.gz`                     | `gpad/CANLF-uniprot.gpad.gz`      |
| `goa_dog.gpi.gz`                      | `gpi/CANLF-uniprot.gpi.gz`        |
| `goa_human.gaf.gz`                    | `gaf/HUMAN-uniprot.gaf.gz`        |
| `goa_human.gpad.gz`                   | `gpad/HUMAN-uniprot.gpad.gz`      |
| `goa_human.gpi.gz`                    | `gpi/HUMAN-uniprot.gpi.gz`        |
| `goa_pig.gaf.gz`                      | `gaf/PIG-uniprot.gaf.gz`          |
| `goa_pig.gpad.gz`                     | `gpad/PIG-uniprot.gpad.gz`        |
| `goa_pig.gpi.gz`                      | `gpi/PIG-uniprot.gpi.gz`          |

### No direct equivalent

These old files have no 1:1 counterpart in the new pipeline:

- `filtered_goa_uniprot_all.gaf.gz`
- `filtered_goa_uniprot_all_noiea.gaf.gz`
- `filtered_goa_uniprot_all_noiea.gpad.gz`
- `filtered_goa_uniprot_all_noiea.gpi.gz`
- `reactome.gaf.gz`
- `reactome.gpad.gz`
- `reactome.gpi.gz`

All of these resources are now handled and bundled upstream.
