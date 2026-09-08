#!/usr/bin/env Rscript
# Generate the synthetic dataset for lsa-platform.
#
# ALL DATA PRODUCED HERE IS FICTIONAL. No real persons, schools, or results.
# The generation model is documented in docs/data-spec.md.
#
# Design: stratified two-stage sample. Strata are the 26 cantons; within each
# canton, schools are drawn with probability proportional to size (PPS,
# systematic), then a fixed number of students is drawn per sampled school.
# Item responses follow a Rasch model; five plausible values per responding
# student are drawn from an EAP posterior on a quadrature grid.
#
# Usage: Rscript generate.R [--seed N] [--out DIR]
# Base R only, no package dependencies. Reproducible for a given seed.

args <- commandArgs(trailingOnly = TRUE)
opt <- list(seed = 20260908, out = "data/raw", scale = 1L)
i <- 1
while (i <= length(args)) {
  if (args[i] == "--seed") { opt$seed <- as.integer(args[i + 1]); i <- i + 2 }
  else if (args[i] == "--out") { opt$out <- args[i + 1]; i <- i + 2 }
  else if (args[i] == "--scale") { opt$scale <- as.integer(args[i + 1]); i <- i + 2 }
  else if (args[i] == "--help") {
    cat("Usage: Rscript generate.R [--seed N] [--out DIR] [--scale N]\n",
        "--scale multiplies the school frame and per-canton sample",
        "(scale 42 yields roughly 100k students) for load testing.\n")
    quit(status = 0)
  } else stop("unknown argument: ", args[i])
}
stopifnot(opt$scale >= 1)
set.seed(opt$seed)
dir.create(opt$out, recursive = TRUE, showWarnings = FALSE)

# --- 1. Population frame -----------------------------------------------------
# 26 cantons with their (real, public) dominant language region; everything
# below the canton level is invented.
cantons <- data.frame(
  canton = c("AG","AI","AR","BE","BL","BS","FR","GE","GL","GR","JU","LU","NE",
             "NW","OW","SG","SH","SO","SZ","TG","TI","UR","VD","VS","ZG","ZH"),
  language_region = c("de","de","de","de","de","de","fr","fr","de","de","fr",
                      "de","fr","de","de","de","de","de","de","de","it","de",
                      "fr","fr","de","de"),
  # Relative population share drives how many schools the frame holds.
  rel_size = c(6,0.2,0.6,10,3,2,3,5,0.4,2,0.7,4,1.7,0.4,0.4,5,0.8,2.7,1.6,
               2.8,3.5,0.4,8,3.5,1.2,15),
  stringsAsFactors = FALSE
)

n_frame_schools <- pmax(4, round(cantons$rel_size / sum(cantons$rel_size) * 800 * opt$scale))
frame <- do.call(rbind, lapply(seq_len(nrow(cantons)), function(k) {
  n <- n_frame_schools[k]
  data.frame(
    canton = cantons$canton[k],
    language_region = cantons$language_region[k],
    n_students = pmax(15, round(rlnorm(n, meanlog = log(60), sdlog = 0.5))),
    stringsAsFactors = FALSE
  )
}))
frame$school_id <- sprintf("SCH%04d", seq_len(nrow(frame)))

# --- 2. First stage: PPS systematic sample of schools per canton -------------
schools_per_canton <- pmax(2, pmin(12 * opt$scale, round(n_frame_schools * 0.15)))
sample_pps <- function(sizes, n) {
  # Systematic PPS: random start on the cumulative size scale, fixed step.
  cum <- cumsum(sizes)
  step <- cum[length(cum)] / n
  points <- runif(1, 0, step) + (seq_len(n) - 1) * step
  idx <- findInterval(points, c(0, cum), left.open = TRUE)
  unique(idx)  # a very large school can be hit twice; keep it once
}
schools <- do.call(rbind, lapply(seq_len(nrow(cantons)), function(k) {
  f <- frame[frame$canton == cantons$canton[k], ]
  n_draw <- schools_per_canton[k]
  hit <- sample_pps(f$n_students, n_draw)
  s <- f[hit, ]
  # Inclusion probability under systematic PPS: n * size / total size, capped.
  s$incl_prob <- pmin(1, n_draw * s$n_students / sum(f$n_students))
  s$school_weight <- 1 / s$incl_prob
  s
}))

# --- 3. Second stage: students within sampled schools ------------------------
students_per_school <- 20
students <- do.call(rbind, lapply(seq_len(nrow(schools)), function(j) {
  s <- schools[j, ]
  n_sampled <- min(students_per_school, s$n_students)
  data.frame(
    school_id = s$school_id,
    canton = s$canton,
    language_region = s$language_region,
    sex = sample(c("f", "m"), n_sampled, replace = TRUE),
    ses_quintile = sample(1:5, n_sampled, replace = TRUE),
    # Within-school stage weight: sampled from n_students with equal probability.
    student_weight = s$school_weight * s$n_students / n_sampled,
    stringsAsFactors = FALSE
  )
}))
students$student_id <- sprintf("STU%05d", seq_len(nrow(students)))

# --- 4. Nonresponse ----------------------------------------------------------
# Participation varies by canton so the ingestion plausibility checks have a
# realistic response-rate profile to test against.
canton_rr <- setNames(runif(nrow(cantons), 0.82, 0.98), cantons$canton)
students$participated <- rbinom(nrow(students), 1,
                                canton_rr[students$canton]) == 1
# Nonresponse adjustment within stratum (canton): inflate responder weights so
# each canton's weighted total is preserved.
adj <- tapply(students$student_weight, students$canton, sum) /
  tapply(ifelse(students$participated, students$student_weight, 0),
         students$canton, sum)
students$final_weight <- ifelse(
  students$participated,
  students$student_weight * adj[students$canton],
  NA_real_
)

# --- 5. Rasch item responses -------------------------------------------------
n_items <- 30
items <- data.frame(
  item_id = sprintf("IT%02d", seq_len(n_items)),
  difficulty = round(rnorm(n_items, 0, 1), 4),
  domain = rep(c("reading", "math", "science"), length.out = n_items),
  stringsAsFactors = FALSE
)
# Ability: canton effect + language-region effect + SES gradient + noise.
canton_eff <- setNames(rnorm(nrow(cantons), 0, 0.25), cantons$canton)
lang_eff <- c(de = 0.05, fr = -0.05, it = -0.10)
theta <- canton_eff[students$canton] +
  lang_eff[students$language_region] +
  0.15 * (students$ses_quintile - 3) +
  rnorm(nrow(students), 0, 1)

responders <- which(students$participated)
responses <- do.call(rbind, lapply(responders, function(r) {
  p <- plogis(theta[r] - items$difficulty)
  data.frame(
    student_id = students$student_id[r],
    item_id = items$item_id,
    correct = rbinom(n_items, 1, p),
    stringsAsFactors = FALSE
  )
}))

# --- 6. Plausible values via EAP posterior on a quadrature grid --------------
grid <- seq(-4, 4, length.out = 81)
prior <- dnorm(grid)
loglik_by_theta <- sapply(grid, function(g) {
  p <- plogis(g - items$difficulty)
  cbind(log(p), log(1 - p))  # 30 x 2: loglik of correct / incorrect per item
}, simplify = "array")  # dims: n_items x 2 x length(grid)

# Compute the posterior per student from the actual response pattern.
resp_wide <- matrix(NA_integer_, nrow = length(responders), ncol = n_items,
                    dimnames = list(students$student_id[responders], items$item_id))
resp_wide[cbind(responses$student_id, responses$item_id)] <- responses$correct
pv <- t(apply(resp_wide, 1, function(x) {
  ll <- sapply(seq_along(grid), function(gi) {
    sum(ifelse(x == 1, loglik_by_theta[, 1, gi], loglik_by_theta[, 2, gi]))
  })
  post <- exp(ll - max(ll)) * prior
  post <- post / sum(post)
  sample(grid, 5, replace = TRUE, prob = post) + runif(5, -0.05, 0.05)
}))
# Report PVs on a conventional assessment scale (mean 500, sd 100).
pv_scaled <- round(500 + 100 * pv, 2)
plausible <- data.frame(
  student_id = rownames(pv_scaled),
  pv1 = pv_scaled[, 1], pv2 = pv_scaled[, 2], pv3 = pv_scaled[, 3],
  pv4 = pv_scaled[, 4], pv5 = pv_scaled[, 5],
  stringsAsFactors = FALSE
)

# --- 6b. Jackknife replicate weights (grouped JKn, variance zones) -----------
# Strata are cantons, PSUs are schools, grouped into at most ~120 variance
# zones overall so the replicate count stays bounded as the sample scales —
# the same device real assessments use. Replicate r drops one zone: its
# students get weight 0, students in the stratum's other zones are scaled
# by G_h/(G_h-1), everyone else keeps their weight; the variance factor
# (G_h-1)/G_h travels with the replicate. At the default scale each zone
# holds exactly one school. Simplification, documented in docs/data-spec.md:
# replicates scale the final (nonresponse-adjusted) weight rather than
# re-estimating the adjustment per replicate.
resp_students <- students[students$participated, ]
schools_by_canton <- split(schools$school_id, schools$canton)
max_zones <- 120
n_per_canton <- vapply(schools_by_canton, length, integer(1))
# pmin first: pmax()/pmin() take attributes from their first argument, and
# the canton names must survive.
zones_per_canton <- pmin(n_per_canton,
                         pmax(round(max_zones * n_per_canton / sum(n_per_canton)), 2))

# Deterministic round-robin assignment of schools to zones within a stratum.
school_zone <- unlist(lapply(names(schools_by_canton), function(h) {
  ids <- schools_by_canton[[h]]
  setNames(((seq_along(ids) - 1) %% zones_per_canton[[h]]) + 1, ids)
}))

replicates <- do.call(rbind, lapply(names(schools_by_canton), function(h) {
  g_h <- zones_per_canton[[h]]
  data.frame(canton = h, zone = seq_len(g_h),
             n_schools = as.integer(table(factor(
               school_zone[schools_by_canton[[h]]], levels = seq_len(g_h)))),
             jk_factor = (g_h - 1) / g_h,
             stringsAsFactors = FALSE)
}))
replicates$replicate_id <- seq_len(nrow(replicates))

student_zone <- school_zone[resp_students$school_id]
rep_weights <- do.call(rbind, lapply(seq_len(nrow(replicates)), function(r) {
  rep <- replicates[r, ]
  g_h <- zones_per_canton[[rep$canton]]
  w <- resp_students$final_weight
  same_stratum <- resp_students$canton == rep$canton
  dropped <- same_stratum & student_zone == rep$zone
  w[same_stratum] <- w[same_stratum] * g_h / (g_h - 1)
  w[dropped] <- 0
  data.frame(student_id = resp_students$student_id,
             replicate_id = rep$replicate_id,
             weight = w, stringsAsFactors = FALSE)
}))

# --- 7. Invariant checks before writing --------------------------------------
stopifnot(
  !anyDuplicated(schools$school_id),
  !anyDuplicated(students$student_id),
  all(responses$student_id %in% students$student_id),
  all(plausible$student_id %in% students$student_id),
  all(students$final_weight[students$participated] > 0),
  # Weighted responder total per canton must reproduce the sampled total.
  isTRUE(all.equal(
    as.numeric(tapply(students$final_weight[students$participated],
                      students$canton[students$participated], sum)),
    as.numeric(tapply(students$student_weight, students$canton, sum)),
    tolerance = 1e-6
  )),
  # Zones partition each stratum's schools; every responder appears in each
  # replicate; at most a bounded number of replicates overall.
  sum(replicates$n_schools) == nrow(schools),
  nrow(replicates) <= 130,
  nrow(rep_weights) == nrow(resp_students) * nrow(replicates),
  all(rep_weights$weight >= 0)
)

# --- 8. Write outputs --------------------------------------------------------
out <- function(df, name) {
  write.csv(df, file.path(opt$out, name), row.names = FALSE, quote = TRUE)
}
out(schools[, c("school_id", "canton", "language_region", "n_students",
                "incl_prob", "school_weight")], "schools.csv")
out(students[, c("student_id", "school_id", "canton", "language_region",
                 "sex", "ses_quintile", "participated", "student_weight",
                 "final_weight")], "students.csv")
out(items, "items.csv")
out(responses, "responses.csv")
out(plausible, "plausible_values.csv")
out(replicates[, c("replicate_id", "canton", "n_schools", "jk_factor")],
    "replicates.csv")
out(rep_weights, "replicate_weights.csv")

manifest <- data.frame(
  key = c("seed", "generated_at_utc", "n_schools", "n_students",
          "n_responders", "n_items", "n_responses"),
  value = c(opt$seed, format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
            nrow(schools), nrow(students), length(responders), n_items,
            nrow(responses))
)
out(manifest, "manifest.csv")

cat(sprintf("Wrote %d schools, %d students (%d responders), %d responses to %s\n",
            nrow(schools), nrow(students), length(responders), nrow(responses),
            opt$out))
