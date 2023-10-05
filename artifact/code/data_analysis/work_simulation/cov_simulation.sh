#!/bin/sh
#
# Runs cov_simulation.R on all subjects found in `../../results/predictions.csv`.
# Results are placed in `./cov_simulation`.
#
# No CLI arguments are expected.
#
set -o nounset

OUT_DIR="./cov_simulation"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*

for subject in $(tail -n+2 ../../results/predictions.csv | cut -f1,2 -d',' | sort -u); do
  pid=$(echo $subject | cut -f1 -d',')
  bid=$(echo $subject | cut -f2 -d',')
  vid=${bid}f
  printf "$pid-$vid: "
  Rscript cov_simulation.R $pid $bid ../../results $OUT_DIR
done
echo "Done"
