# Data Analysis scripts

## Prepare the Environment

Before running scripts in this directory, install the required Python and R packages.
If running from the Docker container, the requirements are already installed and these
steps can be skipped.

### Python

Before running anything in the data_analysis directory, first make sure the packages
listed in requirements.txt are installed in the local Python 3 environment. Install them
with:

```sh
pip3 install -r requirements.txt
```

Alternatively, packages can be intalled into a virtual environment. Make, activate, then
install requirements with:

```sh
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
```

If using a virtual environment, be sure to follow the remainder of these instructions
from a shell in which the virtual environment is active.

### R

Additionally, install the R package dependencies:

```sh
R -e \
  "install.packages(
    c('data.table', 'plyr', 'ggplot2', 'reshape2', 'sigmoid', 'doMC'),
    dependencies=TRUE, repos='http://cran.rstudio.com/')"
```

## Scripts

There are a number of user-facing scripts in this directory: 

- work_simulation/efficiency.R
- work_simulation/cov_simulation.R
- work_simulation/plot_efficiency.R
- work_simulation/stopping.R
- work_simulation/plot_simulation.R
- work_simulation/work_simulation.R
- work_simulation/plot_stopping.R
- work_simulation/findExampleSimulation.R
- work_simulation/efficiency_sample.R
- ml/train_model.py
- ml/eval_model.py
- test_sampling_vs_coverage.R

See comments at the top of each script for more information about function and
expected arguments.

In general, R scripts are run with with `Rscript` and Python scripts are run
with `python3` (optionally from the virtual environment created in a prior
step).

## Replacing the Machine Learning Model

To replace the machine learning model, modify the `train_model.py` and `eval_model.py`
files.