# AI Services VM for the SUASecLab

A randomized, self-hosted AI services VM for the SUASecLab ethical hacking lab
(Schmalkalden University of Applied Sciences). Team 21, winter term 2026/27.

## Structure

| Folder | Content |
|---|---|---|
| `catalog/` | Vulnerability catalog and a sample configuration |
| `generator/` | Seeded generator, copied virtual-machines modules (`lib/`), unit tests |
| `analysis/` | RQ2 analysis and charts |
| `packer/` | Packer templates (base image, student VM), Debian preseed |
| `scripts/platform/` | In-VM build scripts: Docker, images, models, host weaknesses, internet block |
| `scripts/services/` | In-VM build scripts: admin setup, data and flags, self-check |
| `files/` | Static files copied from virtual-machines  |
| `lab/` | Build many VMs, start, stop, reset; lab flag system |
| `builder/` | Renderer and its text templates |
| `checker/` | Configuration check of finished VMs |
| `benchmark/` | RQ1 benchmark |
| `spikes/` | Early tests and measurements |
| `docs/` | Project documentation for the submission |

Files copied from virtual-machines are listed in `PROVENANCE.md`. Generated files go to `output/`, which is never
committed (it contains flags and passwords).

