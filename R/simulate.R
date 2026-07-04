# ---------------------------------------------------------------------------
# simulate.R
#
# Forward simulator for the two-compartment (muscle / blood) lactate model
# described in the repository README, under a dynamic heart-rate forcing.
#
# Reparameterised process model (README "Reparameterisation" section):
#
#   lambda(t) = alpha + beta * h(t)                         # muscle production
#   dC_m/dt   = lambda      - rho * a_m * (C_m - C_b)       # muscle balance
#   dC_b/dt   = a_m * (C_m - C_b) - r_b * tanh(a_b*(C_b - C_min)/r_b)  # blood
#
# and the Gaussian sampling model for the end-of-period blood-lactate samples:
#
#   B_i ~ Normal( C_b(t(i)), sigma^2 )
#
# with parameters
#   rho   > 0   ratio of blood to muscle volume  (V_b / V_m)
#   a_m   > 0   muscle<->blood permeability / V_b
#   a_b   > 0   blood clearance permeability / V_b
#   r_b   > 0   saturating (threshold) blood clearance rate / V_b
#   alpha       intercept of muscle production (real-valued)
#   beta  > 0   slope of muscle production in heart rate
#   C_min > 0   minimum blood lactate (clearance floor)
#   sigma > 0   blood-lactate measurement standard deviation
#
# Requires: deSolve  (install.packages("deSolve"))
# ---------------------------------------------------------------------------

library(deSolve)


#' Construct and validate a parameter set for the lactate model.
#'
#' @return A named list of the eight model parameters, with defaults chosen to
#'   produce a plausible incremental-test lactate curve. All positivity
#'   constraints from the README are enforced.
lactate_params <- function(rho   = 3.0,
                           a_m   = 0.30,
                           a_b   = 0.60,
                           r_b   = 2.0,
                           alpha = -0.60,
                           beta  = 0.010,
                           C_min = 0.8,
                           sigma = 0.3) {
  p <- list(rho = rho, a_m = a_m, a_b = a_b, r_b = r_b,
            alpha = alpha, beta = beta, C_min = C_min, sigma = sigma)
  pos <- c("rho", "a_m", "a_b", "r_b", "C_min", "beta", "sigma")
  for (nm in pos) {
    if (!is.finite(p[[nm]]) || p[[nm]] <= 0)
      stop(sprintf("Parameter '%s' must be finite and > 0 (got %s).",
                   nm, format(p[[nm]])))
  }
  if (!is.finite(p$alpha)) stop("Parameter 'alpha' must be finite.")
  p
}


#' Build a piecewise-constant heart-rate forcing function h(t).
#'
#' Heart rate `hr[i]` is the average over period i, so h(t) is constant on the
#' interval ((i-1)*period, i*period]. `t` is in minutes.
#'
#' @param hr             Numeric vector of per-period average heart rates (bpm).
#' @param period_minutes Length of each period in minutes (default 3).
#' @return A function h(t) (vectorised over t).
make_hr_forcing <- function(hr, period_minutes = 3) {
  if (any(!is.finite(hr)))
    stop("Heart-rate series contains non-finite values; ",
         "clean or interpolate before simulating.")
  n     <- length(hr)
  knots <- (0:n) * period_minutes          # 0, period, 2*period, ..., n*period
  vals  <- c(hr, hr[n])                     # value on [knot_j, knot_{j+1})
  approxfun(knots, vals, method = "constant", rule = 2, f = 0)
}


#' Right-hand side of the two-compartment ODE system (for deSolve::ode).
#'
#' @param t     Time (minutes).
#' @param y     Named state c(C_m = ..., C_b = ...).
#' @param parms List with model parameters and an `hr_fun` forcing function.
lactate_rhs <- function(t, y, parms) {
  C_m <- y[["C_m"]]
  C_b <- y[["C_b"]]

  h      <- parms$hr_fun(t)
  lambda <- parms$alpha + parms$beta * h                 # muscle production

  transfer  <- parms$a_m * (C_m - C_b)                   # muscle -> blood flux
  clearance <- parms$r_b * tanh(parms$a_b * (C_b - parms$C_min) / parms$r_b)

  dC_m <- lambda - parms$rho * transfer
  dC_b <- transfer - clearance

  list(c(C_m = dC_m, C_b = dC_b), lambda = lambda)
}


#' Simulate the latent lactate trajectories C_m(t) and C_b(t).
#'
#' Integrates the ODE system under the heart-rate forcing implied by `hr`, and
#' returns the modelled concentrations at the requested times.
#'
#' @param params         A list from `lactate_params()`.
#' @param hr             Per-period average heart rates (bpm).
#' @param period_minutes Period length, minutes (default 3).
#' @param obs_times      Times (minutes) at which to report the trajectory.
#'   Default: end of each period, i.e. period_minutes * seq_along(hr) — the
#'   times t(i) at which blood lactate is sampled.
#' @param y0             Initial state c(C_m, C_b). Default: both at C_min
#'   (resting baseline).
#' @param ...            Passed to deSolve::ode (e.g. method, rtol, atol).
#' @return A data.frame with columns `time_min`, `C_m`, `C_b`, `lambda`.
simulate_lactate <- function(params,
                             hr,
                             period_minutes = 3,
                             obs_times      = NULL,
                             y0             = NULL,
                             ...) {
  if (is.null(obs_times))
    obs_times <- period_minutes * seq_along(hr)
  if (is.null(y0))
    y0 <- c(C_m = params$C_min, C_b = params$C_min)

  parms <- c(params,
             list(hr_fun = make_hr_forcing(hr, period_minutes)))

  # Integrate from 0 through all requested times. deSolve needs t = 0 in the
  # time grid for the initial condition; we prepend it and drop it after.
  times <- sort(unique(c(0, obs_times)))
  sol   <- deSolve::ode(y = y0, times = times, func = lactate_rhs,
                        parms = parms, ...)
  sol   <- as.data.frame(sol)

  out <- sol[sol$time %in% obs_times, , drop = FALSE]
  data.frame(time_min = out$time,
             C_m      = out$C_m,
             C_b      = out$C_b,
             lambda   = out$lambda,
             row.names = NULL)
}


#' Simulate observed blood-lactate samples B_i from the model.
#'
#' Runs the forward model and adds Gaussian measurement noise with standard
#' deviation `params$sigma`, per the README sampling model
#' B_i ~ Normal(C_b(t(i)), sigma^2).
#'
#' @inheritParams simulate_lactate
#' @return A data.frame with columns `period`, `time_min`, `hr`, `C_b`
#'   (latent), and `bla` (noisy simulated observation).
simulate_lactate_obs <- function(params,
                                 hr,
                                 period_minutes = 3,
                                 obs_times      = NULL,
                                 y0             = NULL,
                                 ...) {
  if (is.null(obs_times))
    obs_times <- period_minutes * seq_along(hr)

  traj <- simulate_lactate(params, hr, period_minutes = period_minutes,
                           obs_times = obs_times, y0 = y0, ...)

  noise <- rnorm(nrow(traj), mean = 0, sd = params$sigma)
  data.frame(period   = seq_len(nrow(traj)),
             time_min = traj$time_min,
             hr       = hr[seq_len(nrow(traj))],
             C_b      = traj$C_b,
             bla      = traj$C_b + noise,
             row.names = NULL)
}


#' Draw a parameter set from a (placeholder) prior.
#'
#' The README states that priors other than sigma are to be pinned down by
#' prior-predictive checking; these are weakly-informative placeholders that
#' respect the positivity/support constraints (log-normal for the positive
#' parameters, normal for the real-valued alpha). Tune the hyperparameters as
#' the prior-predictive work proceeds.
#'
#' @return A list in the same shape as `lactate_params()`.
sample_prior <- function() {
  ln <- function(meanlog, sdlog) exp(rnorm(1, meanlog, sdlog))
  lactate_params(
    rho   = ln(log(3.0),  0.4),
    a_m   = ln(log(0.30), 0.5),
    a_b   = ln(log(0.60), 0.5),
    r_b   = ln(log(2.0),  0.5),
    alpha = rnorm(1, -0.6, 0.4),
    beta  = ln(log(0.010), 0.4),
    C_min = ln(log(0.8),  0.25),
    sigma = ln(log(0.3),  0.3)      # informative-ish; refine from lit. (README)
  )
}


#' Simulate a full synthetic test given a heart-rate protocol.
#'
#' Convenience wrapper: draw parameters (or use supplied ones) and produce a
#' synthetic set of blood-lactate observations for a given HR series. Useful for
#' generating training/validation data or for prior-predictive checks.
#'
#' @param hr             Per-period average heart rates (bpm).
#' @param params         Parameter list; if NULL, drawn from `sample_prior()`.
#' @param period_minutes Period length, minutes (default 3).
#' @return A list with `params` (the parameters used) and `data` (the
#'   simulated per-period data.frame from `simulate_lactate_obs`).
simulate_test <- function(hr,
                          params         = NULL,
                          period_minutes = 3) {
  if (is.null(params)) params <- sample_prior()
  dat <- simulate_lactate_obs(params, hr, period_minutes = period_minutes)
  list(params = params, data = dat)
}


# ---------------------------------------------------------------------------
# Example (not run on source):
#
#   source("R/simulate.R")
#
#   # A heart-rate protocol: 3 min rest then rising efforts (bpm).
#   hr <- c(74, 122, 128, 140, 150, 158, 164, 169, 179, 184, 190)
#
#   # Forward-simulate the latent lactate curve with default parameters:
#   p    <- lactate_params()
#   traj <- simulate_lactate(p, hr)          # time_min, C_m, C_b, lambda
#
#   # Simulate noisy blood-lactate observations B_i:
#   obs  <- simulate_lactate_obs(p, hr)      # ... plus a 'bla' column
#
#   # Draw parameters from the prior and simulate a whole synthetic test:
#   sim  <- simulate_test(hr)
# ---------------------------------------------------------------------------
