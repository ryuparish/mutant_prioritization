from sklearn.inspection import permutation_importance

from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from scipy import sparse
import pandas as pd
import sklearn_pandas
import numpy as np
import matplotlib.pyplot as plt
import argparse
import pprint
from count_features import get_expanded_counts
from getFeaturesNamesAndCount import getFeatureNamesAndCount

# Parser
parser = argparse.ArgumentParser(
            prog="linear_model_feature_analysis",
            description="Analyze features that the linear model deems important",
            epilog="Made by rp")
parser.add_argument("-g", "--granularity", default="group")
args, unknown = parser.parse_known_args()

# Hold out interval names
INDIVIDUAL_FEATURE_NAMES = [
    "mutationOperatorGroup",
    "mutationOperator",
    "nodeTypeBasic",
    "nodeTypeDetailed",
    "nodeContextBasic",
    "astContextBasic",
    "astContextDetailed",
    "astStmtContextBasic",
    "astStmtContextDetailed",
    "parentContextBasic",
    "parentContextDetailed",
    "parentStmtContextBasic",
    "parentStmtContextDetailed",
    "hasLiteralChild",
    "hasVariableChild",
    "hasOperatorChild",
    "nestingTotal",
    "nestingLoop",
    "nestingIf",
    "maxNestingInSameMethod",
    "nestingRatioTotal",
    "nestingRatioLoop",
    "nestingRatioIf",
    "lineRatio",
]

# Hold out interval names
GROUPED_FEATURE_NAMES = [
     "mutation_operator_features",
     "node_type_features",
     "AST_Context_features",
     "parent_Context_features",
     "child_features",
     "nesting_features",
     "lineRatio",
]

# Hold out interval names
INDIVIDUAL_FEATURE_NAMES = [
    "mutationOperatorGroup",
    "mutationOperator",
    "nodeTypeBasic",
    "nodeTypeDetailed",
    "nodeContextBasic",
    "astContextBasic",
    "astContextDetailed",
    "astStmtContextBasic",
    "astStmtContextDetailed",
    "parentContextBasic",
    "parentContextDetailed",
    "parentStmtContextBasic",
    "parentStmtContextDetailed",
    "hasLiteralChild",
    "hasVariableChild",
    "hasOperatorChild",
    "nestingTotal",
    "nestingLoop",
    "nestingIf",
    "maxNestingInSameMethod",
    "nestingRatioTotal",
    "nestingRatioLoop",
    "nestingRatioIf",
    "lineRatio",
]

FEATURE_GROUP_TO_INDIVIDUAL_FEATURES = {
     'mutation_operator_features' : ['mutationOperatorGroup', 'mutationOperator'],
     'node_type_features' : ['nodeTypeBasic', 'nodeTypeDetailed'],
     'AST_Context_features' : ['astContextBasic', 'astContextDetailed', 'astStmtContextBasic', 'astStmtContextDetailed'],
     'parent_Context_features' : ['parentContextBasic', 'parentContextDetailed', 'parentStmtContextBasic', 'parentStmtContextDetailed'],
     'child_features' : ['hasLiteralChild', 'hasVariableChild', 'hasOperatorChild'], 
     'nesting_features' : ['nestingTotal', 'nestingLoop', 'nestingIf', 'maxNestingInSameMethod', 'nestingRatioTotal', 'nestingRatioLoop', 'nestingRatioIf'],
     'lineRatio' : ['lineRatio'],
}

def get_interval_from_dataframe(transformed_df, original_df, feature_name, debug=False):
    """
    Return a list that contains the interval of the feature given as "feature_name" in the dataframe "df"
    
    :param transformed_df: original_df dataframe transformed by a mapper with default settings one-hot encoding format
    :param original_df: this is a dataframe before transformed by a Dataframe Mapper
    :type transformed_df: Dataframe
    :type original_df: Dataframe
    :returns: list with two integers signifying the 
    :type return: List[Int, Int]
    :raises ValueError: when feature_name is not found in transformed_df.columns
    """
    interval_start = 0
    interval_end = 0
    featureNameToCount = get_expanded_counts(original_df)
    columnNameToCount = getFeatureNamesAndCount(transformed_df)
    for column_name in columnNameToCount.keys():
        columns = column_name.split("_")

        # If the feature name is in the column-group
        # we read the feature names of the column, left to right
        # until we find the name of matching feature.
        if feature_name in columns:
            for column in columns:
                if feature_name == column:
                    interval_end = interval_start + featureNameToCount[column]
                    return [interval_start, interval_end]
                else:
                    interval_start += featureNameToCount[column]

        # If the feature name is not in the column-group
        # we add the number of all features from the column-group
        else:
            if debug:
               print(f"Adding interval for column-group: {column_name}")
            interval_start += columnNameToCount[column_name]
    print(f"WARNING, could not find feature name: {feature_name} in transformed dataframe")
    raise ValueError("could not find feature name: {feature_name} in transformed dataframe")



def hold_out_feature_train(model, custmut_csv, X_all, Y_all, X_test, y_test, baseline_score, granularity) :
    """
    Train model with one feature held out.
    
    :param model: model to use for predictions
    :param custmut_csv: dataframe before Dataframe Mapper transformation
    :param X_all: training split of custmut_csv after Dataframe Mapper transformation
    :param Y_all: single column of custmut_csv to predict (pKillsDom) during training
    :param X_test: testing split of custmut_csv after Dataframe Mapper transformation
    :param y_test: single column of custmut_csv to predict (pKillsDom) during testing
    :param baseline_score: baseline score to compare splits against
    :param granularity: granularity of hold out groups
    :type model: sklearn.linear_model.Ridge
    :type custmut_csv: Dataframe
    :type X_all: Dataframe
    :type Y_all: Dataframe
    :type X_test: Dataframe
    :type y_test: Dataframe
    :type baseline_score: float
    :type granularity: str
    :returns: None
    """
    num_times_sampled = 5
    average_decrease = {}
    interval_names = []

    match granularity:
        case "group":
            interval_names = GROUPED_FEATURE_NAMES
        case "individual":
            interval_names = INDIVIDUAL_FEATURE_NAMES

    # Sampling scores
    for sample_num in range(num_times_sampled):

        # Getting the interval names
        for interval_name in interval_names:
            print(f"({sample_num})Training while holding out {interval_name}...")

            # If the interval name is a group interval, we collect all the individual feature names for that group
            individual_features = [interval_name]
            if interval_name in GROUPED_FEATURE_NAMES:
                individual_features = FEATURE_GROUP_TO_INDIVIDUAL_FEATURES[interval_name]
            
            feature_intervals = [get_interval_from_dataframe(X_all, custmut_csv, feature) for feature in individual_features]
            feature_interval_names = [X_all.columns[start:end] for start, end in feature_intervals]
            feature_interval_names = [feature_name for feature_interval_names in feature_interval_names for feature_name in feature_interval_names]

            # Testing with control input
            feature_interval_names = pd.Index(feature_interval_names)

            # START TESTING ABOVE LOGIC RYU
            X_without_hold_out = sparse.csc_matrix(X_all.drop(columns=feature_interval_names))
            X_test_without_hold_out = sparse.csc_matrix(X_test.drop(columns=feature_interval_names))
            clf = Ridge(solver="sparse_cg", copy_X=False)
            clf.fit(X_without_hold_out, Y_all)
            held_out_score = clf.score(X_test_without_hold_out, y_test)

            # Adding decrease to sum of decreases per interval
            if interval_name not in average_decrease:
                average_decrease[interval_name] = baseline_score - held_out_score
            else:
                average_decrease[interval_name] += baseline_score - held_out_score
    
    # Averaging scores
    for interval_name in interval_names:
        average_decrease[interval_name] = average_decrease[interval_name] / num_times_sampled
    
    # Printout sorted by value
    sorted_averages = sorted(average_decrease.items(), key=lambda x:x[1], reverse=True)
    print()
    for name, average in sorted_averages:
        print(f"{name} decrease: {average}")

def main():
    print("\nReading csv...")
    custmut_csv = pd.read_csv("data/all-customized-mutants.csv").sample(frac=0.20, random_state=42)
    print("Done!")

    print("Creating mapper...")
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
    ,   df_out=True)
    print("Done!")
    
    
    print("Loading/Mapping the data...")
    X, y = mapper.fit_transform(custmut_csv.loc[:, custmut_csv.columns != "pKillDom"]).astype(np.float32), custmut_csv.loc[:, "pKillsDom"].astype(np.float32)
    print("Done!")
    
    
    print("Training the model...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, random_state=42)
    clf = Ridge(solver="sparse_cg", copy_X=False)
    clf.fit(sparse.csc_matrix(X_train), y_train)
    print("Done!")
    
    print("Getting baseline score...")
    baseline_score = clf.score(X_test, y_test)
    print(f"\nBaseline accuracy on test data: {baseline_score}")
    print(f"\nHeld-out feature scores:")
    hold_out_feature_train(clf, custmut_csv, X_train, y_train, X_test, y_test, baseline_score, granularity=args.granularity)

# Python
if __name__ == "__main__":
    main()
