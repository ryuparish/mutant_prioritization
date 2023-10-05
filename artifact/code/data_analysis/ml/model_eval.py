#!/usr/bin/env python3
"""Creates plots comparing the intrinsic model performance of a collecton of models.

Run `model_eval.py --help` for more information.
"""

import logging
import sys
import glob
import argparse
import itertools
import joblib
import warnings
import pathlib
import tempfile

from typing import Any, Union, Mapping, cast

import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import pandas as pd
import scipy
import scipy.stats
import sklearn
import sklearn.metrics

arg_parser = argparse.ArgumentParser(
    description="Create plots for the intrinsic model comparison."
)
arg_parser.add_argument(
    "results_dir",
    type=pathlib.Path,
    help="Directory containing the data collection output, such as "
    "the root of customized-mutants-logs.",
)
arg_parser.add_argument(
    "model_root",
    type=pathlib.Path,
    help=(
        "Directory containing results of train_model.py. "
        "This should contain files named things like "
        "model-linear-few_features-all_projects.joblib."
    ),
)
arg_parser.add_argument(
    "output_pdf_path",
    type=pathlib.Path,
    help="The destination for the output PDF",
)
arg_parser.add_argument(
    "output_pgf_path",
    type=pathlib.Path,
    help="The destination for the output .pgf",
)
arg_parser.add_argument(
    "output_predictions_path",
    type=pathlib.Path,
    help="The destination directory for the output predictions CSVS",
)


def main() -> int:
    logging.basicConfig()

    args = arg_parser.parse_args()

    cm_df = read_cm_df(args.results_dir)
    loaded_models = load_models(args.model_root)

    all_eval_metrics = {}
    mutants_to_predictions = {}
    src = list(loaded_models.items())
    for name, (em, m2p) in joblib.Parallel(n_jobs=-1)(
        joblib.delayed(_cpd_job)(n, cm_df, m, r) for n, (m, r) in src
    ):
        expanded_model_desc = tuple(name.split("-"))
        assert len(expanded_model_desc) == 3
        all_eval_metrics[expanded_model_desc] = em
        mutants_to_predictions[expanded_model_desc] = m2p

    all_eval_metrics_df: pd.DataFrame = pd.concat(
        all_eval_metrics, names=["modelType", "featuresUsed", "trainingSet"]
    )

    # Save the plot as a .pgf to a temp. path
    plot_spearmans_to_temp_file(
        all_eval_metrics_df, args.output_pdf_path, args.output_pgf_path
    )

    # Save predictions to one gzipped CSV per model.
    mutants_to_predictions_df = pd.concat(
        {
            model_desc: pd.DataFrame.from_records(
                d, index=["projectId", "bugId", "mutantId"]
            )
            for model_desc, d in mutants_to_predictions.items()
        },
        names=["modelType", "featuresUsed", "trainingSet"],
    )
    for key in (
        mutants_to_predictions_df.reset_index()[
            ["modelType", "featuresUsed", "trainingSet"]
        ]
        .drop_duplicates()
        .itertuples(index=False)
    ):
        file_key = "-".join(key)
        filename = args.output_predictions_path / f"predictions-{file_key}.csv.gz"
        to_write = mutants_to_predictions_df.loc[key].rename(
            columns={"prediction": "predictedProbKillsDom"}
        )
        assert len(to_write)
        to_write.to_csv(str(filename), index=True)

    return 0


def read_cm_df(results_dir: Union[str, pathlib.Path]) -> pd.DataFrame:
    if isinstance(results_dir, str):
        results_dir = pathlib.Path(results_dir)
    if not results_dir.is_dir():
        raise ValueError(f"{results_dir} is not a directory")

    # Read all results and concatenate into a single DataFrame: cm_df
    paths = glob.glob(str(results_dir / "**/**/*customized-mutants.csv"))
    cm_dfs = []
    for path in paths:
        print(f"Reading: {path}")
        cm_dfs.append(pd.read_csv(path))
    cm_df = pd.concat(cm_dfs)

    # We're only interested in covered mutants, so immediately discard uncovered.
    cm_df.isCovered = cm_df.isCovered.astype("bool")
    cm_df = cast(pd.DataFrame, cm_df[cm_df.isCovered])

    # Assert that we only have one bug ID per project
    assert (cm_df.groupby("projectId").bugId.nunique() == 1).all()

    return cm_df


def load_models(models_root: Union[str, pathlib.Path]) -> Mapping[str, Any]:
    """Loads all machine learning models from the given directory.

    Returns:
        A dictionary mapping model names to loaded models. A name is derived
        from the path; e.g., "linear-all_features-project_only".
    """
    if isinstance(models_root, str):
        models_root = pathlib.Path(models_root)

    loaded_models = {}
    for t in itertools.product(
        ["linear", "randomforest"],
        ["all_features", "few_features"],
        ["all_projects", "project_only", "between_projects"],
    ):
        name = "-".join(t)
        path = models_root / f"model-{name}.joblib"
        if not path.is_file():
            warnings.warn(f"Skipping {path}")
            continue
        with open(path, "rb") as fo:
            loaded_models[name] = joblib.load(fo)
    return loaded_models


def _cpd_job(name, *args):
    return name, create_predictions(*args)


# Produce predictions for each Java class, for each model
def create_predictions(cm_df: pd.DataFrame, mapper, results):
    m2p = []

    project_ids = []
    bug_ids = []
    class_names = []
    r2_scores = []
    spearmans = []
    spearmans_exp_dom_nodes = []

    for (proj, bug_id, key), model in results:
        if isinstance(key, str):  # Convert. (For backward compatibility.)
            key = {"class": key}
        assert isinstance(key, dict), "Key was " + str(type(key))

        if "project" in key:
            target_class_names = list(
                cm_df[cm_df.projectId == key["project"]]["className"].drop_duplicates()
            )
        else:
            target_class_names = [key["class"]]

        for target_class_name in target_class_names:
            project_ids.append(proj)
            bug_ids.append(bug_id)
            class_names.append(target_class_name)

            eval_df = cm_df[
                (cm_df.projectId == proj) & (cm_df.className == target_class_name)
            ].copy()
            assert len(eval_df) < len(cm_df)

            X_ = mapper.transform(eval_df)
            y_ = eval_df.pKillsDom.values.copy()
            y_exp_killed = eval_df.expKilledDomNodes.copy()

            preds = model.predict(X_)
            for m, p in zip(eval_df.mutantId, preds):
                m2p.append(
                    {"projectId": proj, "bugId": bug_id, "mutantId": m, "prediction": p}
                )

            if len(y_) < 2:
                print(
                    "Skipping R2/Spearman because fewer than 2 samples", file=sys.stderr
                )
                r2_scores.append(np.nan)
                spearmans.append(np.nan)
                spearmans_exp_dom_nodes.append(np.nan)
            else:
                r2_scores.append(sklearn.metrics.r2_score(y_, preds))
                spearmans.append(scipy.stats.spearmanr(y_, preds).correlation)
                spearmans_exp_dom_nodes.append(
                    scipy.stats.spearmanr(y_exp_killed, preds).correlation
                )

    eval_metrics = pd.DataFrame(
        data={
            "projectId": project_ids,
            "bugId": bug_ids,
            "className": class_names,
            "r2Score": r2_scores,
            "spearmans": spearmans,
            "spearmans_exp_dom_nodes": spearmans_exp_dom_nodes,
        }
    ).set_index(["projectId", "bugId", "className"], verify_integrity=True)

    return eval_metrics, m2p


def plot_spearmans_to_temp_file(
    all_eval_metrics: pd.DataFrame,
    out_pdf_path: Union[str, pathlib.Path],
    out_pgf_path: Union[str, pathlib.Path],
) -> None:
    if isinstance(out_pdf_path, str):
        out_pdf_path = pathlib.Path(out_pdf_path)
    if isinstance(out_pgf_path, str):
        out_pgf_path = pathlib.Path(out_pgf_path)

    def inner_plot():
        sns.catplot(
            kind="box",
            data=(
                all_eval_metrics.groupby(
                    ["modelType", "featuresUsed", "trainingSet", "projectId"]
                )
                .spearmans.median()
                .to_frame()
                .reset_index()
                .rename(
                    columns={
                        "spearmans": "Median Corr. Coefficients",
                        "trainingSet": "Training Set",
                        "modelType": "Model",
                        "featuresUsed": "Features Used",
                    }
                )
                .replace(
                    {
                        "linear": "Linear",
                        "randomforest": "Random Forest",
                        "all_features": "All",
                        "few_features": "Few",
                        "all_projects": "All Projects",
                        "between_projects": "Between Projects",
                        "project_only": "Project-Only",
                    }
                )
            ),
            y="Median Corr. Coefficients",
            col="Model",
            x="Training Set",
            row="Features Used",
            margin_titles=True,
            sharey=True,
            height=2.4,
            aspect=1.6,
            palette="Blues",
        )

    inner_plot()
    plt.savefig(str(out_pdf_path), format="pdf")

    rc_update = {
        "pgf.texsystem": "pdflatex",
        "pgf.rcfonts": False,
        "text.usetex": True,
        "font.family": "sans serif",
    }
    with plt.rc_context(rc_update):
        inner_plot()
        plt.savefig(str(out_pgf_path))


if __name__ == "__main__":
    sys.exit(main())
