## cluster_configs.R ##
## Single source of truth for the clustering feature sets used in the revision ##
## Sourced by risk_variable_data_wrangling.Rmd (complete-case definition) and every clustering script ##

#1. Features shared by all three configurations
#1.1 Clinical/prodromal features other than the CBCL block
feats_clinical <- c(
  "mh_p_gbi_sum", "mh_y_upps__nurg_sum", "mh_y_upps__purg_sum", "sds_total"
)

#1.2 Reward features (BIS/BAS; RR and BIS use the Pagliaccio et al., 2016 revised v01 scoring)
feats_reward <- c(
  "mh_y_bisbas__bas__rr_sum__v01", "mh_y_bisbas__bas__dr_sum",
  "mh_y_bisbas__bis_sum__v01", "mh_y_bisbas__bas__fs_sum"
)

#1.3 Familial features (first-degree relatives)
feats_familial <- c(
  "family_history_depression", "family_history_mania",
  "family_history_psychosis", "family_history_hospitalization"
)

#1.4 Environmental features other than the ACE block
feats_environmental <- c(
  "le_l_coi__addr1__coi__total__national_zscore", "fc_p_nsc__ns_mean", "bullying"
)

#1.5 Neurocognitive features
feats_neurocognitive <- c(
  "nc_y_nihtb__lswmt__uncor_score", "nc_y_nihtb__flnkr__uncor_score", "nc_y_nihtb__pttcp__uncor_score"
)

#2. The blocks that differ between configurations
#2.1 CBCL as the dysregulation profile raw sum (anxious/depressed + attention + aggression)
feats_cbcl_dpsum <- "cbcl_dp_raw_sum"

#2.2 CBCL as the three dysregulation profile raw syndrome sums entered separately
feats_cbcl3raw <- c("mh_p_cbcl__synd__anxdep_sum", "mh_p_cbcl__synd__attn_sum", "mh_p_cbcl__synd__aggr_sum")

#2.3 ACE block with all three abuse types separated from the non-abuse composite (7 factors)
feats_ace_abusesplit <- c("ACE_index_nonabuse_sum_score", "abuse_physical", "abuse_sexual", "abuse_emotional")

#2.4 ACE block with emotional abuse folded into the composite (8 factors); physical and sexual remain separate
feats_ace_emo_in_composite <- c("ACE_index_nonabuse_emo_sum_score", "abuse_physical", "abuse_sexual")

#3. Configuration definitions
feats_shared <- c(feats_clinical, feats_reward, feats_familial, feats_environmental, feats_neurocognitive)

cluster_configs <- list(

  #3.1 Primary: CBCL dysregulation profile raw sum, all three abuse types separated (23 features)
  primary = c(feats_cbcl_dpsum, feats_shared, feats_ace_abusesplit),

  #3.2 Backup: three CBCL raw syndrome sums entered separately, otherwise identical to primary (25 features)
  backup_cbcl3raw = c(feats_cbcl3raw, feats_shared, feats_ace_abusesplit),

  #3.3 Fallback: emotional abuse folded into the ACE composite, otherwise identical to primary (22 features)
  fallback_emo_ace = c(feats_cbcl_dpsum, feats_shared, feats_ace_emo_in_composite)
)

#4. Categorical (binary) features across all configurations, to be coerced to factor before clustering
feats_categorical <- c(
  "family_history_depression", "family_history_mania", "family_history_psychosis",
  "family_history_hospitalization", "bullying", "abuse_physical", "abuse_sexual", "abuse_emotional"
)

#5. Union of all clustering features; defines the complete-case analytic sample so every configuration uses identical rows
feats_all_configs <- unique(unlist(cluster_configs))

#6. Fail loudly if a configuration's size ever drifts from what the manuscript will report
stopifnot(
  length(cluster_configs$primary) == 23,
  length(cluster_configs$backup_cbcl3raw) == 25,
  length(cluster_configs$fallback_emo_ace) == 22,
  !anyDuplicated(cluster_configs$primary)
)
