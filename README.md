# Work in progress: Gaming patterns in NEET Youth

This repository contains the reproducible manuscript and analysis code for a descriptive study examining what video game play looks like among youth that are not in education, employment, or training (NEET).

The rendered manuscript is available at [https://nballou.github.io/open-play-neet/](https://nballou.github.io/open-play-neet/).

## Repository Structure

```
├── index.qmd           # Main manuscript (Quarto document)
├── _quarto.yml         # Quarto project configuration
├── references.bib      # Bibliography
├── R/
│   └── helpers.R       # Helper functions for visualizations and analysis
├── data/               # Data downloaded from Zenodo during render
├── _extensions/        # Quarto extensions (ACM format, preprint-typst)
├── _freeze/            # Frozen computation outputs
└── site_libs/          # Site dependencies
```

## Data

This analysis uses data from the [Open Play dataset](https://doi.org/10.5281/zenodo.17536656), which contains multi-platform digital trace data from US and UK video game players. The data is automatically downloaded from Zenodo when rendering the manuscript.

Key data components used:

- **Digital trace data**: Hourly and session-level gameplay records from Steam, Xbox, and Nintendo Switch
- **Demographic data**: NEET and other demographic variables from the intake survey
- **Game metadata**: Genre classifications harmonized across platforms

## Reproducing the Analysis

### Prerequisites

1. **R** (version 4.0 or later)
2. **Quarto** (version 1.4 or later) — [Download here](https://quarto.org/docs/get-started/)

### Setup

1. Clone this repository:
2. 
   ```bash
   git clone https://github.com/nballou/open-play-neet.git
   cd open-play-neet
   ```

2. Restore the R environment:
3. 
   ```r
   renv::restore()
   ```

3. Render the manuscript:
4. 
   ```bash
   quarto render
   ```

The first render will download the data from Zenodo (~194MB), which may take a few minutes.

### Output Formats

The manuscript renders to multiple formats:

- **HTML** — Interactive web version with code folding
- **PDF (Typst)** — Preprint format (`index-typst.pdf`)
- **Word** — For journal submissions requiring `.docx`

To render a specific format:

```bash
quarto render index.qmd --to html
quarto render index.qmd --to preprint-typst
```
<!--## Citation

If you use this code or analysis, please cite:

```
TODO
```-->

## License

CC0

## Contact

Nick Ballou — [nick@nickballou.com](mailto:nick@nickballou.com)
