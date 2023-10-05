#!/usr/bin/env python3
"""A script to generate numbers_macros.tex and subjectStats.tex files for the paper.

Run `paper_stats.py --help` for more information.
"""

import numpy as np
import pandas as pd

import sys
import os
from typing import Iterable, Union, Mapping
import subprocess
import pathlib
import argparse

IGNORED_SUBDIRS = {"simulations"}

arg_parser = argparse.ArgumentParser()
arg_parser.add_argument(
    "in_path",
    type=str,
    help="The path to a results directory with subdirs. <pid>/<vid>/...",
)
arg_parser.add_argument("out_dir", type=str)


def walk_subject_dirs(root: Union[str, pathlib.Path]) -> Iterable[pathlib.Path]:
    if isinstance(root, str):
        root = pathlib.Path(root)
    for project_dir in root.iterdir():
        if (
            project_dir.name.startswith(".")
            or project_dir.name in IGNORED_SUBDIRS
            or not project_dir.is_dir()
        ):
            continue
        versions_seen = 0
        for version_dir in project_dir.iterdir():
            if not version_dir.is_dir():
                continue
            assert versions_seen <= 1, f"Expected one subdir. in: {project_dir}"
            if _only_log_or_empty(version_dir):
                continue
            _check_file_exists(version_dir / "killMap.csv")
            yield version_dir
            versions_seen += 1


def read_killmap(path) -> pd.DataFrame:
    df = pd.read_csv(path)
    assert isinstance(df, pd.DataFrame)
    return df.rename(columns={"[FAIL | TIME | EXC]": "status"})


def _only_log_or_empty(path: pathlib.Path) -> bool:
    all_paths = list(path.iterdir())
    if not all_paths:
        return True
    if len(all_paths) != 1:
        return False
    return all_paths[0].name.lower() in ("log", "log.gz", "log.zip")


def _check_file_exists(path: pathlib.Path):
    """Raises Exception if the path is not an existing file."""
    if not path.exists():
        raise Exception(f"Expected file to exist: {path}")
    if not path.is_file():
        raise Exception(f"Expected path to be a file: {path}")


def _emit_def(name: str, value: Union[int, np.int64, float], file):
    if isinstance(value, float):
        print(f"\\def\\{name}{{{value:.1f}}}", file=file)
    else:
        print(f"\\def\\{name}{{{value:,}}}", file=file)


def print_table_one(cm_df: pd.DataFrame, tests_per_project: Mapping[str, int], out_fo):
    # Only retain, while making this table, those mutants that are covered.
    covered_or_not = cm_df
    cm_df = cm_df[cm_df.isCovered.astype("bool")]

    cols = ["isDominator", "isKilled"]
    df = (
        cm_df.astype({c: "bool" for c in cols})
        .groupby("projectId")[cols]
        .mean()
        # .sum()
        # .divide(cm_df.groupby("projectId").size(), axis=0)
        .rename(
            columns={
                "isDominator": "dominatorPct",
                "isKilled": "killedPct",
            }
        )
    )

    # Add the un-filtered classes and mutants columns
    df = (
        covered_or_not.groupby("projectId")[["className", "mutantId"]]
        .nunique()
        .rename(columns={"className": "allClassCnt", "mutantId": "allMutantCnt"})
        .join(df)
    )

    df = (
        cm_df.groupby("projectId")[["className", "mutantId"]]
        .nunique()
        .rename(columns={"className": "classCnt", "mutantId": "mutantCnt"})
        .join(df)
    )
    df["equivalentPct"] = 1.0 - df.killedPct

    df["avgTestsCoveringEachMutant"] = cm_df.groupby("projectId").coveringTests.mean()
    df["avgTestsKillingEachMutant"] = cm_df.groupby("projectId").killingTests.mean()
    df["totalTests"] = pd.Series(tests_per_project)

    # Compute totals
    totals_series = df[["allClassCnt", "allMutantCnt", "classCnt", "mutantCnt"]].sum()
    totals_series = pd.concat(
        [
            totals_series,
            cm_df.astype({c: "bool" for c in cols})[cols].mean()
            # .sum()
            # .divide(len(cm_df), axis=0)
            .rename(
                {
                    "isDominator": "dominatorPct",
                    "isKilled": "killedPct",
                }
            ),
        ]
    )
    totals_series["equivalentPct"] = 1.0 - totals_series.killedPct
    totals_series["totalTests"] = df.totalTests.sum()
    totals_series["avgTestsCoveringEachMutant"] = cm_df.coveringTests.mean()
    totals_series["avgTestsKillingEachMutant"] = cm_df.killingTests.mean()

    # Format and print
    def _format_df_for_display(d):
        d = d.copy()
        pct_cols = [c for c in d.columns if c.endswith("Pct")]
        d[pct_cols] = (d[pct_cols] * 100).applymap(lambda v: f"{v:.1f}\\%")
        d[["classCnt", "mutantCnt", "totalTests"]] = d[
            ["classCnt", "mutantCnt", "totalTests"]
        ].applymap(lambda v: f"{v:,.0f}")
        d[["avgTestsCoveringEachMutant", "avgTestsKillingEachMutant"]] = d[
            ["avgTestsCoveringEachMutant", "avgTestsKillingEachMutant"]
        ].applymap(lambda v: f"{v:.1f}")

        # Select the columns we're interested in typesetting, in the right order
        d = d.reindex(
            [
                "classCnt",
                "mutantCnt",
                "equivalentPct",
                "dominatorPct",
                "killedPct",
                "totalTests",
                "avgTestsCoveringEachMutant",
                "avgTestsKillingEachMutant",
            ],
            axis=1,
        )

        return d

    with pd.option_context("display.max_columns", 999):
        for line in str(df).splitlines():
            print(f"% {line}", file=out_fo)
        print("", file=out_fo)
        for line in str(totals_series).splitlines():
            print(f"% {line}", file=out_fo)

    df = _format_df_for_display(df)
    totals_series = _format_df_for_display(totals_series.to_frame().T)

    for project, series in df.iterrows():
        print(
            project + " & " + " & ".join(f"{item}" for item in series) + "\\\\",
            file=out_fo,
        )
    print("\\midrule", file=out_fo)
    print(
        "Total & " + " & ".join(f"{item}" for item in totals_series.iloc[0]),
        file=out_fo,
    )


def main():
    args = arg_parser.parse_args()

    out_path = pathlib.Path(args.out_dir)
    out_path.mkdir(exist_ok=True)

    numbers_macros_fo = (out_path / "numbers_macros.tex").open("w")

    print(
        f"%% This file was generated by {os.path.basename(__file__)} the data repository.",
        file=numbers_macros_fo,
    )

    cm_dfs = []
    projects_in_results = 0
    timeouts = 0
    mutant_test_pairs = 0
    tests_per_project = {}
    for subject_dir in walk_subject_dirs(args.in_path):
        killmap = read_killmap(subject_dir / "killMap.csv")
        cm_dfs.append(pd.read_csv(subject_dir / "customized-mutants.csv"))

        project_id = cm_dfs[-1].iloc[0].projectId
        tests_per_project[project_id] = len(pd.read_csv(subject_dir / "testMap.csv"))

        timeouts += (killmap.status == "TIME").sum()
        mutant_test_pairs += len(killmap)
        assert isinstance(
            timeouts, (np.int64, int)
        ), f"Expected timeouts to be int, but was {type(timeouts)}"
        projects_in_results += 1
    cm_df = pd.concat(cm_dfs, ignore_index=True)
    _emit_def("numOfProjectsUsed", projects_in_results, file=numbers_macros_fo)
    _emit_def(
        "numOfClassesUsed",
        len(cm_df.className.drop_duplicates()),
        file=numbers_macros_fo,
    )

    # Emit \numOfProgramsInDJ
    defects4j_path = (
        pathlib.Path(os.path.realpath(__file__)).parent.parent
        / "deps"
        / "defects4j"
        / "framework"
        / "bin"
        / "defects4j"
    )
    pid_count = sum(
        1
        for line in subprocess.check_output([str(defects4j_path), "pids"])
        .decode("utf8")
        .splitlines()
        if line.strip()
    )
    _emit_def("dJTotalPrograms", pid_count, file=numbers_macros_fo)
    _emit_def("numSubjectsTimeout", timeouts, file=numbers_macros_fo)
    _emit_def("numTestMutantPairs", mutant_test_pairs, file=numbers_macros_fo)
    _emit_def(
        "pctTestMutantPairsTimedOut",
        100 * timeouts / mutant_test_pairs,
        file=numbers_macros_fo,
    )

    with (out_path / "subjectStats.tex").open("w") as fo:
        print_table_one(cm_df, tests_per_project, fo)

    return 0


if __name__ == "__main__":
    sys.exit(main())
