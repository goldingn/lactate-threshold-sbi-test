# ---------------------------------------------------------------------------
# download_data.R
#
# Download and format the graded incremental exercise test dataset of
# Bernard et al. (2024), https://zenodo.org/records/10841412, into the form
# required by the lactate-threshold model described in the repository README.
#
# The dataset is distributed as a single zip (data_v2.zip) containing:
#   data/Data_Summary.xlsx  - one row per test (participant metadata + sport)
#   data/A<XXXX>.xlsx        - one workbook per test, with three sheets:
#       Sheet1  anthropometric / haematological metadata
#       Sheet2  the graded test itself, one row per 3-minute period:
#                 <Load> | HR | VO2 | Bla | SR/Cadence
#               where <Load> is "Actual Power" (cycling/rowing, W) or
#               "Velocity" (running, km/h). The first row is the stationary
#               (rest) period; each subsequent row is a 3-minute effort.
#       Sheet3  derived physiological indices (thresholds etc.)
#
# For the model we only need, per period: the average heart rate (HR, bpm) and
# the end-of-period blood lactate (Bla, mmol/L). We convert the row index into
# a time (min) using the 3-minute period length: observation i is taken at the
# end of period i, i.e. t(i) = period_minutes * i.
#
# Requires: readxl  (install.packages("readxl"))
# ---------------------------------------------------------------------------

library(readxl)

# URL of the Zenodo archive.
LACTATE_DATA_URL <- "https://zenodo.org/records/10841412/files/data_v2.zip?download=1"


#' Download and unzip the Bernard et al. (2024) dataset.
#'
#' Idempotent: if the extracted data directory already exists it is reused
#' unless `force = TRUE`.
#'
#' @param dest_dir Directory in which to place the download and extraction.
#' @param force    Re-download and re-extract even if files already exist.
#' @return Path to the directory that directly contains the .xlsx files
#'   (i.e. .../data_v2/data).
download_lactate_data <- function(dest_dir = "data-raw", force = FALSE) {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)

  zip_path    <- file.path(dest_dir, "data_v2.zip")
  extract_dir <- file.path(dest_dir, "data_v2")
  data_dir    <- file.path(extract_dir, "data")

  if (force || !file.exists(zip_path)) {
    message("Downloading dataset from Zenodo ...")
    # mode = "wb" is required for a correct binary download on Windows.
    utils::download.file(LACTATE_DATA_URL, zip_path, mode = "wb", quiet = FALSE)
  } else {
    message("Using cached zip: ", zip_path)
  }

  if (force || !dir.exists(data_dir)) {
    message("Extracting ...")
    utils::unzip(zip_path, exdir = extract_dir)
  } else {
    message("Using cached extraction: ", data_dir)
  }

  if (!dir.exists(data_dir)) {
    stop("Expected data directory not found after extraction: ", data_dir)
  }
  data_dir
}


#' Read the per-test summary table (one row per test).
#'
#' @param data_dir Directory containing Data_Summary.xlsx (as returned by
#'   `download_lactate_data()`).
#' @return A data.frame with, among others, columns `file`, `sport`, `event`,
#'   `gender`, `lt_load`, `vo2max`, `HRmax`, `height`, `weight`.
read_summary <- function(data_dir) {
  summ <- readxl::read_excel(file.path(data_dir, "Data_Summary.xlsx"))
  summ <- as.data.frame(summ)
  # The first column is an unnamed row index; drop it.
  if (names(summ)[1] %in% c("...1", "")) summ <- summ[, -1, drop = FALSE]
  summ
}


#' Read the graded-test measurements (Sheet2) from a single test workbook.
#'
#' The load column is named "Actual Power" for cycling/rowing/kayak and
#' "Velocity" for running; we read Sheet2 by position so this does not matter.
#'
#' @param path           Path to an A<XXXX>.xlsx workbook.
#' @param period_minutes Length of each test period in minutes (default 3, per
#'   the study protocol). Used to assign an end-of-period time to each row.
#' @return A data.frame with one row per period and columns:
#'   `period` (1-based index), `time_min` (end-of-period time, minutes),
#'   `load` (W or km/h), `hr` (bpm), `vo2`, `bla` (mmol/L), `sr_cadence`,
#'   `load_type` ("Actual Power" or "Velocity").
read_test <- function(path, period_minutes = 3) {
  raw <- suppressMessages(
    readxl::read_excel(path, sheet = "Sheet2", col_names = FALSE)
  )
  raw <- as.data.frame(raw)

  load_type <- as.character(raw[1, 1])          # header of the load column
  body      <- raw[-1, , drop = FALSE]          # drop the header row

  num <- function(x) suppressWarnings(as.numeric(as.character(x)))

  out <- data.frame(
    period     = seq_len(nrow(body)),
    time_min   = period_minutes * seq_len(nrow(body)),
    load       = num(body[[1]]),
    hr         = num(body[[2]]),
    vo2        = if (ncol(body) >= 3) num(body[[3]]) else NA_real_,
    bla        = if (ncol(body) >= 4) num(body[[4]]) else NA_real_,
    sr_cadence = if (ncol(body) >= 5) num(body[[5]]) else NA_real_,
    load_type  = load_type,
    stringsAsFactors = FALSE
  )
  out
}


#' Download and assemble the full dataset in the form the model consumes.
#'
#' Produces a single tidy "long" data.frame with one row per (test, period),
#' carrying both the per-period measurements (heart rate + blood lactate) and
#' the per-test metadata needed to identify participants and sports.
#'
#' @param dest_dir       Where to download/extract (passed to
#'   `download_lactate_data`).
#' @param sports         Character vector of sports to keep, or NULL for all.
#'   Per the README the model is applied to the cycling and running records, so
#'   the default keeps those two.
#' @param period_minutes Length of each period, minutes (default 3).
#' @param force          Force re-download/extraction.
#' @return A data.frame with columns:
#'   `file`, `sport`, `gender`, `event`, `hr_max`, `lt_load`, `vo2_max`,
#'   `height`, `weight`, `period`, `time_min`, `load`, `hr`, `vo2`, `bla`,
#'   `sr_cadence`, `load_type`.
load_lactate_dataset <- function(dest_dir       = "data-raw",
                                 sports         = c("Cycling", "Running"),
                                 period_minutes = 3,
                                 force          = FALSE) {
  data_dir <- download_lactate_data(dest_dir, force = force)
  summ     <- read_summary(data_dir)

  if (!is.null(sports)) {
    summ <- summ[summ$sport %in% sports, , drop = FALSE]
  }

  message("Reading ", nrow(summ), " test workbooks ...")
  per_test <- vector("list", nrow(summ))

  for (i in seq_len(nrow(summ))) {
    file_i <- summ$file[i]
    path_i <- file.path(data_dir, file_i)
    if (!file.exists(path_i)) {
      warning("Missing workbook, skipping: ", file_i)
      next
    }

    meas <- tryCatch(
      read_test(path_i, period_minutes = period_minutes),
      error = function(e) {
        warning("Failed to read ", file_i, ": ", conditionMessage(e)); NULL
      }
    )
    if (is.null(meas)) next

    # Attach the per-test metadata to every period row.
    meta <- data.frame(
      file    = file_i,
      sport   = summ$sport[i],
      gender  = summ$gender[i],
      event   = summ$event[i],
      hr_max  = summ$HRmax[i],
      lt_load = summ$lt_load[i],
      vo2_max = summ$vo2max[i],
      height  = summ$height[i],
      weight  = summ$weight[i],
      stringsAsFactors = FALSE
    )
    per_test[[i]] <- cbind(meta, meas, row.names = NULL)
  }

  dataset <- do.call(rbind, per_test)
  rownames(dataset) <- NULL
  message("Assembled ", nrow(dataset), " period-observations from ",
          length(unique(dataset$file)), " tests.")
  dataset
}


#' Split the long dataset into a per-test list.
#'
#' Convenient when fitting/simulating one participant-test at a time: each
#' element is the ordered sequence of periods for a single test, which is
#' exactly what the simulator in `simulate.R` consumes (a heart-rate series and
#' matching observation times).
#'
#' @param dataset Output of `load_lactate_dataset()`.
#' @return A named list of data.frames, one per test `file`, each ordered by
#'   `period`.
split_by_test <- function(dataset) {
  parts <- split(dataset, dataset$file)
  lapply(parts, function(d) d[order(d$period), , drop = FALSE])
}


# ---------------------------------------------------------------------------
# Example (not run on source):
#
#   source("R/download_data.R")
#   dat   <- load_lactate_dataset()          # cycling + running, ~569 tests
#   tests <- split_by_test(dat)
#   one   <- tests[[1]]
#   # one$hr        -> heart-rate series h_i (bpm), one per period
#   # one$time_min  -> end-of-period times t(i) (minutes)
#   # one$bla       -> observed blood lactate B_i (mmol/L)
# ---------------------------------------------------------------------------
