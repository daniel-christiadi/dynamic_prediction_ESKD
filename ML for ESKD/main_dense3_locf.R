libraries <- c("tidyverse", "data.table", "skimr", "nlme", "rsample", 
               "dynpred", "prodlim", "randomForestSRC", "pec", 
               "gtsummary", "future", "furrr", "patchwork")
installed <- installed.packages()[,'Package']
new.libs <- libraries[!(libraries %in% installed)]
if(length(new.libs)) install.packages(new.libs,repos="http://cran.csiro.au",
                                      dependencies=TRUE)
lib.ok <- sapply(libraries, require, character.only=TRUE)

cross_val <- 5
seed <- 7
predict_horizon <- 5
landmark <- c(0.5, 1, 1.5, 2, 2.5, 3)

longi_cov_full <- c("albumin", "alkphos", "bicarb", "calcium", "chloride",
                "egfr", "glucose", "haemoglobin", "phosphate", "platelet",
                "potassium", "sodium", "wcc")

longi_cov_top10 <- c("albumin", "alkphos", "bicarb", "chloride", "egfr",
                     "haemoglobin", "platelet",
                     "potassium", "sodium", "wcc")

longi_cov_top5 <- c("albumin", "bicarb", "chloride", "egfr", "haemoglobin")
base_cov_full <- c("sex", "age_init", "gn_fct")
base_cov_reduced <- c("age_init")

source("utility_functions.R")

# dense3 locf exploration -------------------------------------------------

dense3_dt <- tibble(
    dt_path = "main_dense3_dt.rds",
    base_cov = list(base_cov_reduced, base_cov_reduced),
    longi_cov = list(longi_cov_top10, longi_cov_top5)
)

dense3_dt <- dense3_dt %>% 
    mutate(dt = map(dt_path, prepare_dt),
           folds = map(dt, create_folds, seed)) %>% 
    unnest_longer(folds)

dense3_dt <- dense3_dt %>% 
    select(folds) %>% 
    map(~.x) %>% 
    bind_rows() %>% 
    bind_cols(dense3_dt) %>% 
    select(id, base_cov, longi_cov, dt, splits) %>% 
    mutate(id_name = rep(c("top10", "top5"), each = 5)) %>% 
    mutate(id = str_to_lower(id))

dense3_dt <- dense3_dt %>% 
    mutate(train_dt = pmap(list(dt, splits), extract_train_dt),
           test_dt = pmap(list(dt, splits), extract_test_dt)) %>% 
    select(id_name, id, base_cov, longi_cov, train_dt, test_dt)

dense3_dt <- dense3_dt %>% 
    mutate(performance = future_pmap(list(train_dt, test_dt, longi_cov, base_cov), 
                                     cross_val_performance_locf_map, landmark,
                                     predict_horizon))

write_rds(dense3_dt, "main_dense3_locf_exploration_performance.rds")

# visualisation -----------------------------------------------------------

main_dt <- read_rds("main_dense3_vs_acr3_performance.rds")
dense3_dt <- read_rds("main_dense3_locf_exploration_performance.rds")

main_dt <- main_dt %>% 
    filter(id_name == "dense3") %>% 
    rename("method" = "id_name")

locf_perf <- main_dt %>% 
    unnest_longer(locf_perf) %>% 
    select(locf_perf) %>% 
    map(~.x) %>% 
    bind_rows() 

dense3_locf_performance <- main_dt %>% 
    unnest_longer(locf_perf) %>% 
    select(method) %>% 
    bind_cols(locf_perf)

dense3_locf_performance <- dense3_locf_performance %>% 
    summarise(across(error_eskd:brier_death, \(x) confidence_interval (x, 0.95)),
              .by = c("LM")) %>% 
    unnest_wider(error_eskd:brier_death, names_sep = "_")

dense3_locf_performance <- dense3_locf_performance %>% 
    pivot_longer(cols = error_eskd_mean:brier_death_upper,
                 names_to = "performance", 
                 values_to = "values") %>% 
    separate_wider_delim(cols = performance, delim = "_",
                         names = c("metrics", "event", "stats")) %>% 
    pivot_wider(names_from = stats, 
                values_from = values)

dense3_locf_performance <- dense3_locf_performance %>% 
    mutate(method = "full")

temp <- dense3_dt %>% 
    select(performance) %>% 
    unnest_longer(performance) %>% 
    map(~ .x) %>% 
    bind_rows()

dense3_top10or5_performance <- dense3_dt %>% 
    unnest_longer(performance) %>% 
    select(id_name) %>% 
    bind_cols(temp) %>% 
    rename("method" = "id_name")

dense3_top10or5_performance <- dense3_top10or5_performance %>% 
    summarise(across(error_eskd:brier_death, \(x) confidence_interval (x, 0.95)),
              .by = c("method","LM")) %>% 
    unnest_wider(error_eskd:brier_death, names_sep = "_")

dense3_top10or5_performance <- dense3_top10or5_performance %>% 
    pivot_longer(cols = error_eskd_mean:brier_death_upper,
                 names_to = "performance", 
                 values_to = "values") %>% 
    separate_wider_delim(cols = performance, delim = "_",
                         names = c("metrics", "event", "stats")) %>% 
    pivot_wider(names_from = stats, 
                values_from = values)

all_dense3_locf_performance <- rbind(dense3_locf_performance, dense3_top10or5_performance)

all_dense3_error <- all_dense3_locf_performance %>% 
    filter(metrics == "error")

all_dense3_error %>% 
    group_by(event) %>% gt()

error1 <- create_error_graph(all_dense3_error,
                             method = "full",
                             "Dense3 Full Model Error Rate (1 - Harrell's C-index) per Landmark LOCF 
                             Prediction Horizon 5 years")

error2 <- create_error_graph(all_dense3_error,
                             method = "top10",
                             "Dense3 Top 10 Error Rate (1 - Harrell's C-index) per Landmark LOCF 
                             Prediction Horizon 5 years")

error3 <- create_error_graph(all_dense3_error,
                             method = "top5",
                             "Dense3 Top 5 Error Rate (1 - Harrell's C-index) per Landmark LOCF 
                             Prediction Horizon 5 years")

error1 + error2 + error3 + plot_annotation(
    title = "Comparison Dense3 LOCF Models",
    theme = theme(plot.title = element_text(hjust = 0.5))
)

all_dense3_brier <- all_dense3_locf_performance %>% 
    filter(metrics == "brier")

all_dense3_brier %>% 
    group_by(event) %>% gt()

brier1 <- create_brier_graph(all_dense3_brier,
                             method = "full",
                             "Dense3 Full Model Integrated Brier Score per Landmark LOCF
                             Prediction Horizon 5 years")

brier2 <- create_brier_graph(all_dense3_brier,
                             method = "top10",
                             "Dense3 Top 10 Integrated Brier Score per Landmark LOCF
                             Prediction Horizon 5 years")

brier3 <- create_brier_graph(all_dense3_brier, 
                             method = "top5",
                             "Dense3 Top 5 Integrated Brier Score per Landmark LOCF
                             Prediction Horizon 5 years")

brier1 + brier2 + brier3 + plot_annotation(
    title = "Comparison Dense3 LOCF Models",
    theme = theme(plot.title = element_text(hjust = 0.5))
)

# trained models ----------------------------------------------------------

trained_models <- tibble(
    dt_path = "main_dense3_dt.rds",
    base_cov = list(base_cov_full, base_cov_reduced),
    longi_cov = list(longi_cov_full, longi_cov_top5),
    model_name = c("full", "top5")
)

trained_models <- trained_models %>% 
    mutate(dt = map(dt_path, prepare_dt))

trained_models %>% 
    select(dt, longi_cov, base_cov, model_name) %>% 
    future_pwalk(final_models, landmark, predict_horizon)

# external data -----------------------------------------------------------

external_performance <- read_rds("external_performance.rds")

external_locf <- external_performance %>% 
    select(performance) %>% 
    unnest_longer(performance) %>% 
    map(~ .x) %>% 
    bind_rows()

external_locf <- external_locf %>% 
    select(-error_eskd) %>% 
    rename(error_eskd = error_death)

external_locf <- external_performance %>% 
    unnest_longer(performance) %>% 
    select(analysis_models) %>% 
    bind_cols(external_locf) %>% 
    arrange(LM, analysis_models)

error1_external

error1_external <- external_locf %>% 
    filter(analysis_models == "full") %>% 
    mutate(LM = as_factor(LM)) %>% 
    pivot_longer(cols = c("error_eskd"), names_to = "error") %>% 
    mutate(error = factor(error, levels = c("error_eskd"),
                          labels = c("ESKD"))) %>% 
    ggplot(aes(x = error, y = value, fill = error)) + geom_boxplot() +
    facet_grid(~ LM) + scale_fill_manual(values = c("blue")) + 
    labs(title = "External Error Rate (1 - Harrell's C-index) per Landmark with LOCF 
         Prediction Horizon 5 years", 
         y = "Error Rate (%)") + 
    theme_bw() + theme(axis.title.x = element_blank(), 
                       legend.title = element_blank(),
                       legend.position = "none") + 
    scale_y_continuous(breaks = seq(0, 30, 5), limits = c(0,30))

error4_external <- external_locf %>% 
    filter(analysis_models == "top5") %>% 
    mutate(LM = as_factor(LM)) %>% 
    pivot_longer(cols = c("error_eskd"), names_to = "error") %>% 
    mutate(error = factor(error, levels = c("error_eskd"),
                          labels = c("ESKD"))) %>% 
    ggplot(aes(x = error, y = value, fill = error)) + geom_boxplot() +
    facet_grid(~ LM) + scale_fill_manual(values = c("blue")) + 
    labs(title = "External Top 5 Error Rate (1 - Harrell's C-index) per Landmark 
         with LOCF Prediction Horizon 5 years", 
         y = "Error Rate (%)") + 
    theme_bw() + theme(axis.title.x = element_blank(), 
                       legend.title = element_blank(),
                       legend.position = "none") + 
    scale_y_continuous(breaks = seq(0, 30, 5), limits = c(0,30))

error1 + error1_external + error4 + error4_external + plot_annotation(
    title = "Comparison Internal vs External LOCF Models"
) + plot_layout(ncol = 2, guides = "collect")

# end ---------------------------------------------------------------------