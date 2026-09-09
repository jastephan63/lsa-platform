# Glossary

Plain-language explanations of the survey-statistics terms used across this
repository, roughly in the order you meet them.

**Stratum / stratified sample** — the population is divided into groups
(here: the 26 cantons) and a sample is drawn *within each group*, so every
group is represented. Each stratum can then be reported on its own.

**PSU (primary sampling unit)** — the first thing you sample. Here it is
the *school*: first schools are drawn, then students within the drawn
schools ("two-stage sampling"). Students from the same school resemble each
other, and the variance estimation has to account for that.

**PPS (probability proportional to size)** — big schools get a higher
chance of being drawn than small ones. This keeps the workload predictable
and is standard in school surveys; the sampling weights undo the unequal
chances afterwards.

**Sampling / design weight** — "how many students does this sampled student
stand for?" The inverse of the probability of ending up in the sample. All
published statistics are weighted, otherwise over-sampled groups would
dominate the results.

**Nonresponse adjustment** — some sampled students don't take the test.
The weights of those who did are scaled up within their canton so the
canton's total is preserved (`final_weight` in the data).

**Rasch model** — a simple model from psychometrics: the chance of
answering an item correctly depends on the student's ability minus the
item's difficulty. The generator uses it to produce realistic-looking
answer patterns.

**Facility** — the share of students who answered an item correctly. High
facility = easy item. The most basic item statistic there is.

**Plausible values (PVs)** — a student's ability is never observed
directly; a 30-item test measures it with error. Instead of one estimated
score per student, five values are drawn from the range of scores that are
*plausible* given their answers. Analysing all five (and combining with
**Rubin's rules**, below) keeps that measurement uncertainty in the
results instead of hiding it.

**EAP (expected a posteriori)** — the specific way this project draws
plausible values: combine what the answers say with a prior assumption
about the ability distribution, then sample from the result.

**Reporting scale** — raw ability numbers are rescaled to a mean of 500 and
a standard deviation of 100, the convention large assessments use so that
"520" is meaningful across studies.

**Jackknife / replicate weights** — the trick for honest uncertainty in
complex samples: recompute the statistic many times, each time leaving one
group of schools out (with the remaining weights scaled up), and measure
how much the answer wobbles. Each "leave-one-out" version is a *replicate*,
and its weights are the *replicate weights*.

**Variance zone** — with thousands of schools, one replicate per school
would be enormous, so schools are grouped into at most ~120 zones and each
replicate drops a zone instead. Standard practice in large assessments.

**Rubin's rules** — the recipe for combining results across the five
plausible values: average the five estimates, and add the spread *between*
them (measurement uncertainty) to the sampling uncertainty from the
jackknife. The result is one estimate with one honest standard error.

**Standard error (SE) and confidence interval (CI)** — the "give or take"
of an estimate. A 95% CI of 490–520 means: under repeated sampling, the
procedure captures the true value 95% of the time. Small cantons have wide
intervals — fewer students, more wobble.

**Small-cell suppression** — a disclosure-control rule: results computed
from fewer than 10 students are not published at all, because tiny groups
make individuals guessable. Enforced three times here (SQL views, R
package, API guard), each with its own test.
