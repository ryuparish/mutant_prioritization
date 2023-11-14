# Write an function that loops over all the generated column names, then 
# counts the largest integer+1 at the end of the column group and saves both the
# largest integer+1 and the column group name. Then we will know exactly how to 
# name and slice the intervals.

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
import re
from count_features import get_expanded_counts

# Parser
parser = argparse.ArgumentParser(
            prog="getFeaturesNamesAndCount",
            description="Get the features and count for columns combined with DataframeMapper's default settings.",
            epilog="Made by rp")
args, unknown = parser.parse_known_args()

def getFeatureNamesAndCount(df, feature_count=None, debug=False):
    """
    Matches all the underscore-formatted prefixes to the number of (e.g. <prefix>_<some increment>)
    values that have that same prefix.

    :param df: A Dataframe that possibly contains one-hot-encodings from a DataFrame Mapper
    :param feature_count: A dictionary that contains a mapping from pre-transformed-column-name to the count of unique values in that column
    :param debug: Debugging flag
    :type df: Dataframe
    :type feature_count: dict
    :type debug: bool
    :return :Returns a dict mapping from column name prefix to number of that column prefix.
    """
    # First create map to store the names and count.
    lastDigitsRegex = re.compile("(\d+)$")
    columnNameToCount = {}
    for column_name in df.columns:
        results = lastDigitsRegex.search(column_name)

        # No match found, there is only this singular column prefix in it's group.
        if results is None:
            columnNameToCount[column_name] = 1

        else:
            offset = len(results.group()) + 1 # Plus one to account for underscore in front of last digit
            column_name_prefix = column_name[:-offset]
            if column_name_prefix not in columnNameToCount:
                columnNameToCount[column_name_prefix] = 0
            columnNameToCount[column_name_prefix] = columnNameToCount[column_name_prefix] + 1

    # Print out the column names and maximum counts
    for column_name, maxCount in columnNameToCount.items():

        if debug:
            print(f"Group Name: {column_name}, Feature Count: {maxCount}")

        individual_feature_names = column_name.split("_")
        if debug and feature_count is not None and len(individual_feature_names) > 1:
            for feature_name in individual_feature_names:
                print(f"\tFeature: {feature_name}, Encoded Values: {feature_count[feature_name]}")
    return columnNameToCount

def main():
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
    
    print("Reading csv...")
    custmut_csv = pd.read_csv("data/all-customized-mutants.csv").sample(frac=0.20, random_state=42)
    columnNameToCount = get_expanded_counts(custmut_csv)
    print("Done!")
    
    print("Loading/Fitting the data...")
    X, y = mapper.fit_transform(custmut_csv.loc[:, custmut_csv.columns != "pKillDom"]).astype(np.float32), custmut_csv.loc[:, "pKillsDom"].astype(np.float32)
    print("Done!")
    
    print("Splitting the data...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, random_state=42)
    transformedNameToCount = getFeatureNamesAndCount(X_train, columnNameToCount)

if __name__ == "__main__":
    main()
