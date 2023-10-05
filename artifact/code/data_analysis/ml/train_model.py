#!/usr/bin/env python3
"""Trains a machine learning model suitable for mutant selection.

Run `train_model.py --help` for more information.
"""

import argparse
import glob
import os
import os.path

import joblib
import numpy as np
import pandas as pd
import seaborn as sns
import sklearn_pandas
from scipy import sparse
from sklearn.ensemble import RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.preprocessing import OneHotEncoder, StandardScaler

arg_parser = argparse.ArgumentParser()
arg_parser.add_argument("--model", required=True, choices=["linear", "randomforest"])
arg_parser.add_argument("--data", required=True, choices=["all", "small"])
arg_parser.add_argument("--out", required=True, type=str)
arg_parser.add_argument(
    "--project_only",
    action="store_true",
    help="If set, training data will only be drawn from the same project.",
)
arg_parser.add_argument(
    "--between_projects",
    action="store_true",
    help="If set, training data will only be drawn from other projects.",
)
arg_parser.add_argument(
    "results_dir",
    type=str,
    help="The directory to search for customized_mutants.csv files.",
)
args = arg_parser.parse_args()

assert not (args.project_only and args.between_projects), "Args cannot be combined"

# Validate the results_dir is a directory.
assert os.path.isdir(args.results_dir)

# Find the customized_mutants.csv files for each individual project.
# (e.g., '{results_dir}/Codec/18f/customized-mutants.csv')
paths = glob.glob(os.path.join(args.results_dir, "**/**/*customized-mutants.csv"))
if not paths:
    raise Exception(f"No customized-mutants.csv files found in {args.results_dir}")

# Read all results and concatenate into a single DataFrame: cm_df
cm_dfs = []
for path in paths:
    print(f"Reading: {path}")
    cm_dfs.append(pd.read_csv(path))
cm_df = pd.concat(cm_dfs)

# We're only interested in covered mutants, so immediately discard uncovered.
cm_df.isCovered = cm_df.isCovered.astype("bool")
cm_df = cm_df[cm_df.isCovered]

# Assert that we only have one bug ID per project
assert (cm_df.groupby("projectId").bugId.nunique() == 1).all()

if args.data == "small":
    mapper = sklearn_pandas.DataFrameMapper(
        [
            (
                ["mutationOperator", "parentStmtContextDetailed"],
                OneHotEncoder(handle_unknown="ignore"),
            )
        ]
    )
elif args.data == "all":
    mapper = sklearn_pandas.DataFrameMapper(
        [
            (["lineRatio"], [SimpleImputer(strategy="mean"), StandardScaler()]),
            (
                ["nestingIf", "nestingLoop", "nestingTotal", "maxNestingInSameMethod"],
                StandardScaler(),
            ),
            (
                [
                    "nestingRatioLoop",
                    "nestingRatioIf",
                    "nestingRatioTotal",
                    "hasOperatorChild",
                    "hasVariableChild",
                    "hasLiteralChild",
                ],
                None,
            ),
            (
                ["nodeTypeBasic", "nodeTypeDetailed"],
                [
                    SimpleImputer(strategy="constant", fill_value="Unknown"),
                    OneHotEncoder(handle_unknown="ignore"),
                ],
            ),
            (
                [
                    "mutationOperator",
                    "mutationOperatorGroup",
                    "nodeContextBasic",
                    "astContextBasic",
                    "astContextDetailed",
                    "astStmtContextBasic",
                    "astStmtContextDetailed",
                    "parentContextBasic",
                    "parentContextDetailed",
                    "parentStmtContextBasic",
                    "parentStmtContextDetailed",
                ],
                OneHotEncoder(handle_unknown="ignore"),
            ),
        ]
    )
else:
    raise Exception(f"Unexpected --data arg: " + str(args.data))

X_all = mapper.fit_transform(cm_df.copy()).astype(np.float32)
y_all = cm_df.pKillsDom.values.copy()

if args.model == "linear":
    X_all = sparse.csc_matrix(X_all)
elif args.model == "randomforest":
    X_all = sparse.csc_matrix(X_all)


def _fit_model(project_id, train_set_selection, selection_key):
    assert (cm_df.projectId == project_id).any()
    bug_id = cm_df[cm_df.projectId == project_id].bugId.drop_duplicates()
    assert len(bug_id) == 1
    bug_id = bug_id.iloc[0]

    X = X_all[train_set_selection]
    assert not np.shares_memory(X, X_all)
    y = y_all[train_set_selection]

    assert X.shape[0] < len(cm_df)
    assert y.shape[0] < len(cm_df)

    if args.model == "linear":
        model = Ridge(solver="sparse_cg", copy_X=False)
    elif args.model == "randomforest":
        model = RandomForestRegressor(
            max_depth=3,
            n_estimators=10,
            n_jobs=1,
            # n_jobs=max(1, os.cpu_count() // 8),
        )
    else:
        raise Exception(f"Unexpected model arg: " + str(args.model))
    model.fit(X, y)
    return (project_id, bug_id, selection_key), model


def fit_model(project_id, held_out_class_name):
    assert (cm_df.className == held_out_class_name).any()
    train_set_selection = cm_df.className != held_out_class_name
    if args.project_only:
        train_set_selection = train_set_selection & (cm_df.projectId == project_id)
    return _fit_model(project_id, train_set_selection, {"class": held_out_class_name})


def fit_model_from_other_projects(project_id):
    assert isinstance(project_id, str)
    train_set_selection = cm_df.projectId != project_id
    return _fit_model(project_id, train_set_selection, {"project": project_id})


project_names = [
    tuple(row)
    for _, row in cm_df[["projectId", "className"]].drop_duplicates().iterrows()
]
project_classes = [
    tuple(row)
    for _, row in cm_df[["projectId", "className"]].drop_duplicates().iterrows()
]

if args.data == "small":
    n_jobs = int(os.getenv("TRAIN_MODEL_CPUS", "-1"))
elif args.data == "all":
    n_jobs = int(os.getenv("TRAIN_MODEL_CPUS", "8"))

else:
    raise Exception(f"Unexpected model arg: " + str(args.model))

if args.between_projects:
    fit_model_delayed = joblib.delayed(fit_model_from_other_projects)
    parallel_jobs = [fit_model_delayed(n) for n in cm_df.projectId.drop_duplicates()]
else:
    fit_model_delayed = joblib.delayed(fit_model)
    parallel_jobs = [fit_model_delayed(*t) for t in project_classes]
print(f"Training {len(parallel_jobs)} models")
results = joblib.Parallel(n_jobs=n_jobs, verbose=61)(parallel_jobs)

# Save all results, including models, to disk
print(f"Writing to: {args.out}")
joblib.dump((mapper, results), args.out)
