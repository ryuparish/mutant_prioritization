#!/bin/sh
set -o nounset

OUT_DIR="./simulations_sample"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*

export CM_SAMPLE=TRUE
for subject in $(tail -n+2 ../../results/predictions.csv | cut -f1,2 -d',' | sort -u); do
  pid=$(echo $subject | cut -f1 -d',')
  bid=$(echo $subject | cut -f2 -d',')
  vid=${bid}f
  printf "$pid-$vid: "
  Rscript work_simulation.R $pid $bid ../../results $OUT_DIR
done
echo "Done"
