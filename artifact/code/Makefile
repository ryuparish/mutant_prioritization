# Use zsh. bash cannot parse the following case statements in subshells.
SHELL = /bin/zsh

# Include .NOTPARALLEL as a target to avoid building targets in parallel.
# Expensive targets are parallelized internally.
.NOTPARALLEL:

RESULTS_DIR = results
PAPER_RESULTS_DIR = $(RESULTS_DIR)/paper
PREDICTIONS_DIR = $(RESULTS_DIR)/predictions
SIMS_NO_SAMPLING_DIR := $(RESULTS_DIR)/simulations/no_sampling
SIMS_SAMPLING_DIR := $(RESULTS_DIR)/simulations/sampling

SUBJECTS_CSV := data_collection/subjects.csv

MODEL_CLASSES := linear randomforest
DATASET := all_features few_features
SPLIT := all_projects project_only between_projects

# Only a single model is used for downstream analysis.
SELECTED_MODEL := linear-all_features-project_only

MODELS := $(foreach X,$(MODEL_CLASSES),$(foreach Y,$(DATASET),$(foreach Z,$(SPLIT),$(RESULTS_DIR)/models/model-$X-$Y-$Z.joblib)))
PREDICTIONS := $(foreach X,$(MODEL_CLASSES),$(foreach Y,$(DATASET),$(foreach Z,$(SPLIT),$(PREDICTIONS_DIR)/predictions-$X-$Y-$Z.csv.gz)))

# This is the default "hosts" (-S) argument passed to GNU Parallel. It can be
# overridden by the user with, for example, `make HOSTS="8/:"
HOSTS = :

# ',' literals cannot be passed into Makefile functions. $(COMMA) can be passed instead.
COMMA := ,

.PHONY: all models paper

all: $(RESULTS_DIR)/customized-mutants.csv $(RESULTS_DIR)/predictions.csv $(MODELS) paper

paper: $(PAPER_RESULTS_DIR)/intrinsic_performance.pdf $(PAPER_RESULTS_DIR)/intrinsic_performance.pgf $(PAPER_RESULTS_DIR)/subjectStats.tex $(PAPER_RESULTS_DIR)/numbers_macros.tex $(PAPER_RESULTS_DIR)/stopping_class.png $(PAPER_RESULTS_DIR)/efficiency.pdf $(PAPER_RESULTS_DIR)/efficiency_sampling.pdf $(PAPER_RESULTS_DIR)/Collections-28-org.apache.commons.collections4.CollectionUtils.csv1.png $(PAPER_RESULTS_DIR)/Collections-28-org.apache.commons.collections4.CollectionUtils.csv2.pdf $(PAPER_RESULTS_DIR)/Collections-28-org.apache.commons.collections4.functors.ConstantFactory.csv2.pdf $(PAPER_RESULTS_DIR)/Csv-16-Token.coverage.pdf

clean:
	rm -rf $(RESULTS_DIR)

# Collect the subjects from subjects.csv.
subjects := $(shell tail -q -n +2 "$(SUBJECTS_CSV)")  # tail strips the header.

# Grab the project IDs from the subjects.csv file.
projects := $(shell tail -q -n +2 "$(SUBJECTS_CSV)" | cut -d ',' -f1 | sort | uniq)

# create_subject_name converts a row of subjects.csv and a string into the corresponding
# results path. For example: giving "Csv,1" and "hi" returns results/Csv/1f/hi.
define create_subject_name
$(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/$2
endef

# create_subject_target defines a target for a given row in subjects.csv.
define create_subject_target
$(eval $(call create_subject_name,$1,customized-mutants.csv) $(call create_subject_name,$1,killMap.csv) $(call create_subject_name,$1,testMap.csv) $(call create_subject_name,$1,covMap.csv) $(call create_subject_name,$1,mutants.log) $(call create_subject_name,$1,dmsgs.csv) $(call create_subject_name,$1,scoreMatrix.csv) &:
	cd data_collection && ./collect_one_subject.sh -h $(HOSTS) $(subst $(COMMA), ,$1))
endef

# Create collect_one_subject.sh target for every subject in subjects.csv.
$(foreach row,$(subjects),$(call create_subject_target,$(row)))

# Concatenate the customized-mutants.csv all subjects into one file:
# $(RESULTS_DIR)/customized-mutants.csv.
$(RESULTS_DIR)/customized-mutants.csv: $(foreach r,$(subjects),$(call create_subject_name,$(r),customized-mutants.csv))
	mkdir -p "$(dir $@)"
	rm -f "$@.tmp"
	head -n 1 "$<" > "$@.tmp"
	for f in $^; do tail -q -n +2 "$$f" >> "$@.tmp"; done
	mv "$@.tmp" "$@"

# Train a number of machine learning models. These will be used in an intrinsic 
# performance evaluation.
models: $(MODELS)

$(MODELS): $(RESULTS_DIR)/customized-mutants.csv
	mkdir -p "$(dir $@)"
	data_analysis/ml/train_model.py \
		--out "$@" \
		--model $(word 2,$(subst -, ,$(notdir $(basename $@)))) \
		--data \
		$$( \
			case "$(word 3,$(subst -, ,$(notdir $(basename $@))))" in \
				all_features) echo "all" ;; \
				few_features) echo "small" ;; \
				*) exit 2 ;; \
			esac \
		) \
		$$( \
			case "$(word 3,$(subst -, ,$(notdir $(basename $@))))" in \
				project_only) echo "--project_only" ;; \
				between_projects) echo "--between_projects" ;; \
				*) ;; \
			esac \
		) \
		"$(RESULTS_DIR)"

$(RESULTS_DIR)/predictions.csv: $(PREDICTIONS_DIR)/predictions-$(SELECTED_MODEL).csv.gz
	gunzip --to-stdout "$<" > "$@"


define create_coverage_target
$(eval $(RESULTS_DIR)/cov_simulation/$(firstword $(subst $(COMMA), ,$1)).coverage.csv:
	mkdir -p "$(RESULTS_DIR)/cov_simulation"
	cd data_analysis/work_simulation && Rscript cov_simulation.R $(subst $(COMMA), ,$1) "../../$(RESULTS_DIR)" "../../$(RESULTS_DIR)/cov_simulation")
endef
$(foreach row,$(subjects),$(call create_coverage_target,$(row)))

# Makes 2 things:
# 1. paste0(OUT_DIR, "/", PID, "-", BID, "-", class, ".csv")
# 2. paste0(OUT_DIR, "/", PID, "-", BID, "-summary.csv")
# But we don't have a way of iterating over classes, so only the summary CSV is
# represented in this Makefile.
define create_worksim_target
$(eval $2/$(subst $(COMMA),-,$1)-summary.csv: $(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/customized-mutants.csv $(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/dmsgs.csv $(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/killMap.csv $(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/covMap.csv $(RESULTS_DIR)/cov_simulation/$(firstword $(subst $(COMMA), ,$1)).coverage.csv $(RESULTS_DIR)/$(subst $(COMMA),/,$1)f/testMap.csv $(RESULTS_DIR)/predictions.csv
	mkdir -p "$2"
	cd data_analysis/work_simulation && Rscript ./work_simulation.R $(subst $(COMMA), ,$1) "../../$(RESULTS_DIR)" "../../$2")
endef
$(foreach row,$(subjects),$(call create_worksim_target,$(row),$(SIMS_SAMPLING_DIR)))
$(foreach row,$(subjects),$(call create_worksim_target,$(row),$(SIMS_NO_SAMPLING_DIR)))

# Produce plots comparing the intrinsic performance of the models.
$(PAPER_RESULTS_DIR)/intrinsic_performance.pdf $(PAPER_RESULTS_DIR)/intrinsic_performance.pgf $(PREDICTIONS) &: $(MODELS)
	mkdir -p "$(PAPER_RESULTS_DIR)"
	mkdir -p "$(PREDICTIONS_DIR)"
	data_analysis/ml/model_eval.py \
		"$(RESULTS_DIR)" "$(RESULTS_DIR)/models" \
		"$(PAPER_RESULTS_DIR)/intrinsic_performance.pdf" \
		"$(PAPER_RESULTS_DIR)/intrinsic_performance.pgf" \
		"$(PREDICTIONS_DIR)"


# Produce LaTeX table summarizing subjects, as well as some basic statistics-as-LaTeX macros.
# 
# &: below tells GNU make to interpret the next rule as producing multiple outputs,
# rather than as a short-hand for each output.
$(PAPER_RESULTS_DIR)/subjectStats.tex $(PAPER_RESULTS_DIR)/numbers_macros.tex &: $(foreach r,$(subjects),$(call create_subject_name,$(r),killMap.csv)) $(foreach r,$(subjects),$(call create_subject_name,$(r),customized-mutants.csv)) $(foreach r,$(subjects),$(call create_subject_name,$(r),testMap.csv))
	data_collection/paper_stats.py "$(RESULTS_DIR)" "$(PAPER_RESULTS_DIR)"


# These targets use the summary CSV as a dependency, even though the summary CSV itself
# isn't used. This is because they require side 
$(SIMS_SAMPLING_DIR)/efficiency/efficiency.csv: $(foreach row,$(subjects),$(SIMS_SAMPLING_DIR)/$(subst $(COMMA),-,$(row))-summary.csv)
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/efficiency_sample.R "$(SIMS_SAMPLING_DIR)" "$@"

$(SIMS_NO_SAMPLING_DIR)/efficiency/efficiency.csv: $(foreach row,$(subjects),$(SIMS_NO_SAMPLING_DIR)/$(subst $(COMMA),-,$(row))-summary.csv)
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/efficiency.R "$(SIMS_NO_SAMPLING_DIR)" "$@"


$(PAPER_RESULTS_DIR)/efficiency.pdf: $(SIMS_NO_SAMPLING_DIR)/efficiency/efficiency.csv
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/plot_efficiency.R "$<" "$@"

$(PAPER_RESULTS_DIR)/efficiency_sampling.pdf: $(SIMS_SAMPLING_DIR)/efficiency/efficiency.csv
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/plot_efficiency.R "$<" "$@"


$(RESULTS_DIR)/stopping_class.csv: $(foreach row,$(subjects),$(SIMS_NO_SAMPLING_DIR)/$(subst $(COMMA),-,$(row))-summary.csv)
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/stopping.R "$(SIMS_NO_SAMPLING_DIR)" "$@"

$(PAPER_RESULTS_DIR)/stopping_class.png: $(RESULTS_DIR)/stopping_class.csv
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/plot_stopping.R "$<" "$@"

$(RESULTS_DIR)/%-simplot.csv.pdf: $(SIMS_SAMPLING_DIR)/%.csv
	mkdir -p "$(dir $@)"
	Rscript data_analysis/work_simulation/plot_simulation.R "$<" "$@"

$(PAPER_RESULTS_DIR)/%.csv1.png: $(RESULTS_DIR)/%-simplot.csv.pdf
	mkdir -p "$(dir $@)"
	ghostscript -dLastPage=1 -dBATCH -dNOPAUSE -sDEVICE=png16m -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -r200 -o $@ "$<"

$(PAPER_RESULTS_DIR)/%.csv2.pdf: $(RESULTS_DIR)/%-simplot.csv.pdf
	mkdir -p "$(dir $@)"
	pdfseparate -f 2 -l 2 "$<" "$@"

$(SIMS_SAMPLING_DIR)/Collections-28-org.apache.commons.collections4.CollectionUtils.csv: $(SIMS_SAMPLING_DIR)/Collections-28-summary.csv

$(RESULTS_DIR)/Csv-16-org.apache.commons.csv.Token.coverage.csv:
	mkdir -p "$(RESULTS_DIR)"
	cd data_analysis/work_simulation && Rscript cov_simulation.R Csv 16 "../../$(RESULTS_DIR)" "../../$(RESULTS_DIR)" org.apache.commons.csv.Token

$(PAPER_RESULTS_DIR)/Csv-16-Token.coverage.pdf: $(RESULTS_DIR)/Csv-16-org.apache.commons.csv.Token.coverage.csv
	mkdir -p "$(dir $@)"
	Rscript data_analysis/test_sampling_vs_coverage.R "$<" org.apache.commons.csv.Token "$@"