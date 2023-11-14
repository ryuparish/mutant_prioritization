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
from linear_model_feature_importance import get_interval_from_dataframe

# Parser
parser = argparse.ArgumentParser(
            prog="correlation_of_features.py",
            description="Determine correlation of features using coefficients of determination",
            epilog="Made by rp")
parser.add_argument("-i", "--independent-variable")
parser.add_argument("-d", "--dependent-variable")
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

def cod_per_feature(transformed_df, original_df, ind_feature, dep_feature):
    """
    Determine the coefficient of determination for each of the dependent feature values by 
    using the independent feature values to predict those dependent feature values.

    :param transformed_df: original_df dataframe transformed by a mapper with default settings one-hot encoding format
    :param original_df: this is a dataframe before transformed by a Dataframe Mapper
    :param ind_feature: name of independent feature to use
    :param dep_feature: name of dependent feature to use
    :type transformed_df: Dataframe
    :type original_df: Dataframe
    :type ind_feature: str
    :type dep_feature: str
    :returns: None
    """
    # Getting the intervals for the dependent and independent variables.
    # With "intervals" being the intervals of columns in the transformed
    # matrix.
    ind_feature_indexes = get_interval_from_dataframe(transformed_df, original_df, ind_feature)
    ind_feature_names = transformed_df.columns[ind_feature_indexes[0]:ind_feature_indexes[1]]
    ind_feature_values = transformed_df[ind_feature_names]
    dep_feature_indexes = get_interval_from_dataframe(transformed_df, original_df, dep_feature)
    dep_feature_names = transformed_df.columns[dep_feature_indexes[0]:dep_feature_indexes[1]]
    dep_feature_values = transformed_df[dep_feature_names]

    print(f"\nUsing {ind_feature} to predict values for {dep_feature}...")
    print(f"\nCoefficients of determination for each feature in one-hot encodings of {dep_feature}:\n")

    # Getting sample sizes using same train_test_split
    X_train, X_test, y_train, y_test = train_test_split(ind_feature_values, dep_feature_values[dep_feature_values.columns[0]], random_state=42, test_size=0.20)
    print(f"Train set size: {len(X_train)}, Test set size: {len(X_test)}")

    for dep_feature_column in dep_feature_values.columns:
        dep_feature_value = dep_feature_values[dep_feature_column]
        X_train, X_test, y_train, y_test = train_test_split(ind_feature_values, dep_feature_value, random_state=42, test_size=0.20)
        clf = Ridge(solver="sparse_cg", copy_X=False)
        clf.fit(sparse.csc_matrix(X_train), y_train)
        score = clf.score(sparse.csc_matrix(X_test), y_test)
        print(f"{dep_feature_column[:15]}...{dep_feature_column[15:]} : {score}")
    
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

    cod_per_feature(X, custmut_csv, args.independent_variable, args.dependent_variable)
    

# Python
if __name__ == "__main__":
    main()
