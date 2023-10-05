# Data Collection pipeline

Implementation of the data collection pipeline, which produces the
`customized-mutants.csv` data file as its main artifact. The subsequent
data analysis pipeline (in `../data_analysis`) consumes this data file.

For convenience, there are two wrapper scripts for running the pipeline on a
single subject (collect_one_subject.sh <PID> <BID>) and for running it on all
subjects listed in subjects.csv (collect_all_subjects.sh).

## Pipeline design

The pipeline is divided into three stages:

1. 10_mutation_analysis.sh,

2. 20_dmsg_analysis.sh, and

3. 30_consolidate_data.sh.

The pipeline writes all outputs to `results/data_collection` at the root of
this repository.

Each of the three pipeline scripts takes a PID and BID (e.g., Lang 1), which
identify a subject. Results are independent with respect to the subject, and
results appear in `results/data_collection/<PID/<BID>` subdirectories.

The first step of the pipeline (10_mutation_analysis.sh) does not depend on
any files existing. The subsequent steps rely on the outputs of the previous
steps.

See the documentation at the tops of individual scripts for their inputs and
outputs.

## Data Files

The data-collection pipeline creates the following outputs
(in `results/data_collection/<PID>/<BID>`).

##### Mutation analysis

  * `mutants.log`: Lists, for each generated mutants, information about mutation
                   operator and target (class/method/line).

  * `covMap.csv`: Mapping tests (TestNo) to covered mutants (MutantNo).

  * `killMap.csv`: Mapping tests (TestNo) to killed mutants (MutantNo) and the
                   kill reason (FAIL: failing assertion, TIME: timeout,
                   EXC: runtime exception).

  * `testMap.csv`: Mapping test IDs (TestNo) to test names (TestName).

  * `mutants.context`: Program-context information for each mutant (MutantNo).

##### DMSG analysis

  * `scoreMatrix.csv`: Expanded kill matrix (MuJava) format with one column per
                       test and one row per mutant. (Score matrix for all
                       classes in a subject.)

  * `dmsgs.csv`: All dmsgs (one for each top-level class) in a single file.

  * `mutant_class.map`: Mapping mutants (Mutant) to mutation targets (Target and
                        Line). A mutation target is a fully qualified class name
                        plus a method name (if applicable).

  * `score_matrix_slice/<class name>`: Score matrix and DMSG analysis for each
                                       top-level class in a subject:

      + `scoreMatrix.csv`: Score matrix for a single top-level class.

      + `run0/dmsg_test0.dot`: The DMSG, encoded in GraphViz dot format
                               (use dot -Tpng <file>.dot to render a png).

      + `run0/mutants_test0.csv`: The DMSG, mapping mutants (mutantId) to graph
                                  nodes (groupId) and score (dominatorStrength);
                                  a score of 1 indicates a dominator mutant;
                                  a score of -1 indicates an equivalent mutant;
                                  a score of [0,1) indicates a subsumed mutant.

##### Consolidated data

  * `customize-mutants.csv`: The final data file, providing context features and
                             utility labels for each mutant in a subject.
