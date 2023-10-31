import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)
from sklearn.datasets import load_breast_cancer
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.preprocessing import OneHotEncoder, StandardScaler
import sklearn_pandas


EXPANDED_FEATURES = [
             "nodeTypeBasic",
             "nodeTypeDetailed",
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
            ]

SELECTED_FEATURES = [
            "lineRatio",
            "nestingIf",
            "nestingLoop",
            "nestingTotal",
            "maxNestingInSameMethod",
            "nestingRatioLoop",
            "nestingRatioIf",
            "nestingRatioTotal",
            "hasOperatorChild",
            "hasVariableChild",
            "hasLiteralChild",
            "nodeTypeBasic", # Expanded Start
            "nodeTypeDetailed",
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
            "parentStmtContextDetailed" # Expanded End
    ]

def get_expanded_counts(dataframe):
    total_item_count = 0
    for idx, col in enumerate(dataframe.columns):
        if col in SELECTED_FEATURES:
            if dataframe[col].dtype == "object":
                print(f"[{idx}, {col}] Count: {len(dataframe[col].unique())} dtype: {dataframe[col].dtype}")
                total_item_count += len(dataframe[col].unique())
            else: 
                print(f"[{idx}, {col}] Count: 1 dtype: {dataframe[col].dtype}")
                total_item_count += 1

    print(f"\nTotal number of features: {total_item_count}")
    return

custmut_csv = pd.read_csv("data/all-customized-mutants.csv").sample(frac=0.20, random_state=42)

# There are a total of 13451 columns
mapper = sklearn_pandas.DataFrameMapper(
    [
        # Row 1
        (["lineRatio"], [SimpleImputer(strategy="mean"), StandardScaler()]),
        (
        # Row 2-5
            ["nestingIf", "nestingLoop", "nestingTotal", "maxNestingInSameMethod"],
            StandardScaler(),
        ),
        (
        # Row 6-11
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
        # Row 12-13
            ["nodeTypeBasic", "nodeTypeDetailed"],
            [
                SimpleImputer(strategy="constant", fill_value="Unknown"),
                OneHotEncoder(handle_unknown="ignore"),
            ],
        ),
        (
        # Row 14-24
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
, df_out=True)

# 0. Get the expanded form of the dataframe printed out
get_expanded_counts(custmut_csv)

# 1. Print out the columns originally from the custom mutation dataframe
print(f"\nCustomized Mutant dataframe, Columns: {len(custmut_csv.columns)}")

X, y = mapper.fit_transform(custmut_csv.loc[:, custmut_csv.columns != "pKillsDom"]).astype(np.float32), custmut_csv.loc[:, "pKillsDom"].astype(np.float32)
X_train, X_test, y_train, y_test = train_test_split(X, y,random_state=42)

# 2. Print out the number of columns now in the transformed dataframe
print(f"\nNum columns in transformed dataframe: {len(X.columns)}\n")

# 3. Print out the number of feature_importances_ the random forest regressor has
clf = RandomForestRegressor(n_estimators=1, max_depth=1, random_state=42)
clf.fit(X_train, y_train)
print(f"\nNum columns in feature importance: {len(clf.feature_importances_)}")

#X, y = load_breast_cancer(return_X_y=True, as_frame=True)
#X_train, X_test, y_train, y_test = train_test_split(X, y, random_state=42)
#print(f"Here is the type of X_train: {type(X_train)}")
