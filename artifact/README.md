# Prioritizing Mutants to Guide Mutation Testing

This artifact package contains data, and code to reproduce those data, for the
ICSE 2022 paper "Prioritizing Mutants to Guide Mutation Testing". Additionally,
it provides a Docker container that can be used to execute that code.

The Docker image is based on the ubuntu:20.04 image base
(sha256:57df66b9fc9ce2947e434b4aa02dbe16f6685e20db0c170917d4a1962a5fe6a9).
The below runtime estimates are based on executing the Docker container on a
server with 32 cores and 64G of RAM.

The remainder of this file describes how to reproduce the paper results, using
the code, data, and Docker container in the artifact:

1. **Reduced Runtime: Subset of Subjects:**
   Partial end-to-end reproduction by running **data collection and data
   analysis**  on a **subset of subjects**. This is suitable for verifying
   that all parts of the pipeline are functional.

2. **Reduced Runtime: Precomputed Mutation Analyses:**
   Full reproduction by running **only data analysis** on **precomputed data**
   for **all subjects**. This is suitable for quickly verifying that results
   match those reported in the paper.

3. **Full Reproduction or Extensions:**
   Full end-to-end reproduction by running **data collection and data analysis**
   on **all subjects**. This is suitable for running your own analyses or as a
   more thorough verification of both the pipeline's functionality and the
   results reported in the paper.

Note that the third option is very time-consuming---on the order of a week with
a 32-core machine. Most of this extensive runtime is due to the computational
cost of the mutation analyses on which the data analysis is based.

### Set up (all 3 options)
To load the provided Docker container, run the following command in the
artifact’s root directory:

```sh
gunzip -c docker_image.tar.gz | docker load
```

(To build the image yourself, run `docker build -t samkaufman/custmut:latest .`
in the `code` subdirectory.)

Once the container is built, it can be executed via the provided Makefile inside
the container environment, which will generate all results, including plots.

For any option below, replace **`[/path/to/results]`** with the absolute path to
a directory on your local filesystem, to which the pipeline should output all
results.

### 1. Reduced Runtime: Subset of Subjects
Use the following command to run the entire pipeline (data collection and
analysis) on two subjects (Collections-28 and Csv-16):

```sh
docker run -v [/path/to/results]:/code/customized-mutants-data/results -it samkaufman/custmut:latest make SUBJECTS_CSV=data_collection/subjects.test.csv
```

The paper draws specific examples from these two subjects. Hence, this option
demonstrates the fully automated pipeline and fully reproduces most of the plots
in the paper. Other plots are partially reproduced (i.e., data for excluded
subjects are missing).

This option requires about 90 minutes of compute time.

### 2. Reduced Runtime: Precomputed Mutation Analyses
Use the following commands to run only data analysis using precomputed data
available in the artifact:

```sh
cp -R data/simulations [/path/to/results]/simulations
rsync -a --prune-empty-dirs --include '*/' --include 'customized-mutants.csv' --exclude '*' data/ [/path/to/results]
```

This first step copies the mutation-analysis results (intermediate files
mentioned in `code/Makefile`) to the local results directory (i.e., the
directory mounted into the Docker container with the -v flag). Specifically,
these two commands copy the following files and directories:

- `data/simulations -> [/path/to/results]/simulations`

- `data/**/**/customized-mutants.csv -> [/path/to/results]/**/**/customized-mutants.csv`

Once the intermediate files are in the results directory, run:

```sh
docker run -v [/path/to/results]:/code/customized-mutants-data/results -it samkaufman/custmut:latest make
```
The pipeline will not re-generated the copied files, thus effectively skipping
data collection.

This option demonstrates that all the paper results are consistent with the
collected data.

This option requires about two hours of compute time.

### 3. Full Reproduction or Extensions
Use the following command to run the entire pipeline, reproducing all results of
the paper from scratch or re-running the pipeline after extending it:

```sh
docker run -v [/path/to/results]:/code/customized-mutants-data/results -it samkaufman/custmut:latest make`
```

If the execution is interrupted, it can be resumed by running the previous command again.

Once complete, all results will be available in the `[/path/to/results]`
directory (plots used in the paper are in `[/path/to/results]/paper`).

**Note:** Prior to running the entire pipeline, make sure to clean the results
folder if necessary -- either by removing all files from the local results
folder ([/path/to/results]) or by calling `make clean` in the Docker container.
For efficiency reasons, data collection does not re-generated existing data
files.

This option requires about one week of compute time.

### Cite
If using this artifact, please cite:

> Samuel J. Kaufman, Ryan Featherman, Justin Alvin, Bob Kurtz, Paul Ammann & René Just.
> 2022. Prioritizing mutants to guide mutation testing. In Proceedings of the 44th
> International Conference on Software Engineering (ICSE '22), May 21–29, 2022.
> Pittsburgh, PA. <https://doi.org/10.1145/3510003.3510187>.