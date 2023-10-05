This repository contains code for reproducing the results of the ICSE 2022
publication "Prioritizing Mutants to Guide Mutation Testing".

If you are interested in generating all results, all the way from mutation
analysis through the generation of figures in the paper, the easiest way to do
this is by running, from the root of this working directory, `init.sh` and
`make`. (Or, if using a container based on the included Dockerfile, just `make`.)

This repo. distinguishes between data collection and data analysis. *Data collection*
refers to the relatively expensive stage of running mutation analysis on our subject
projects, and *analysis* to the work simulations and other processing done on the
results of the data colletion stage. In general, data collection should be run first.
Both stages save their outputs to a `results` directory at the top of this source
tree (a sibling to this README.md).

Scripts for running these stages is contained in the `data_collection` and
`data_analysis` directories respectively. See the READMEs in those subdirectories
for more information.