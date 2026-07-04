# Lactate threshold modelling - simulation-based inference test case

This experimental repository defines and simulates from a mechanistic model of lactate accumulation under dynamic excercise loads. It will then build and validates an amortised Bayesian simulation-based inference engine, and applies it to empirical data with continuous heart rate monitoring and intermittent lactate testing, to infer a posterior over the lactate threshold and lactate threshold heart rate.

This is a simple test case of using agentic AI to perform amortised simulation-based Bayesian inference on a user-provided model and target dataset. This will use the agentic AI resources in https://github.com/idem-lab/bayesflow-sbi-agent-kit.

The main branch will contain the code and information prior to engaging agentic AI to support SBI. Worked agentic SBI analyses, with different versions of the above agent kit will be stored on different branchs.   

Note that the author is not an expert in exercise physiology, and the use case is a toy example, so the assumptions made in constructing this model should not be considered as remotely authoritative. Agentic AI is also being used to rapidly implement the initial code for this toy example and write documentation, so errors may well occur there too.

Below we define the model and data considered in this repo.

## Model

We define simple two-compartment model of lactate levels in muscle and blood, with a simple form of negative density dependence on lactate levels, under dynamic exercise load (external forcing). This model is inspired by the model of [Zouloumian & Freund (1981)](https://doi.org/10.1007/BF00428866), though that model focuses on lactate kinetics after the cessation of exercise, rather than under dynamic forcing of lactate.

### Assumptions:

1. Lactate is generated in working muscle, with the rate of lactate production increasing with the rate of work.

2. Lactate is transported between muscle and blood, with the rate of transport depending on the concentrations in the two compartments

3. Lactate is cleared from the blood, with a rate that increases with the blood lactate concentration, up to a maximum value.

### Process model:

We model kinetics of the concentration of lactate (mmol.L^-1) in the muscle (C_m) and blood (C_b) during exercise via three processes: lactate genertion in muscle, lactate transfer from muscle to blood, and lactate clearing from blood.

#### Lactate generation in muscle

We parameterise the rate of lactate concentration accumulation in the muscle compartment (mmol.L^-1.min^-1) as \lambda, which we can model as linear in heart rate h(t) at time t, as a proxy for the amount of work being done by the muscle:

  \lambda(t) = \alpha + \beta h(t)

where \alpha and \beta are unconstrained (real-valued) free scalar parameters. This term governs external forcing of lactate in the system.

#### Lactate transfer

We model the rate of transfer of lactate mass (mmol.min^-1, note: not concentration) away from muscle and into blood as proportional to the chemical gradient (difference in concentration between muscle and blood) and a unitless 'permeability parameter' P_m:

  \eta_m = P_m (C_m - C_b)

#### Lactate clearance

At 'low' blood lactate concentrations (below some threshold transport rate \eta_{threshold}), lactate is modelled as being cleared from the blood with some permeability P_b, proportionally to its concentration above a minimum value C_{min}; analagous to a permeable membrane with a fixed low concentration in on the other side. However at high blood lactate concentrations this membrane saturates, and the gradient can no longer increase. We model this with a tanh function, and the threshold transport rate:

  \eta_b = \eta_{threshold} tanh(P_b (C_b - C_{min}) / \eta_{threshold})

#### Kinetics

We model the lactate kinetics with two differential equations on the concentrations of lactate in muscle and in blood, by adjusting these absolute flow rates to the concentrations of the respective compartments:

  dC_m/dt = \lambda - \eta_m / V_m
  dC_b/dt = \eta_m / V_b - eta_b / V_b

#### Reparameterisation

This system has 8 unknown parameters: V_m, V_b, P_m, P_b, C_{min}, \eta_{threshold}, \alpha, \beta. While some can be jointly inferred from heart rate and blood lactate data, others are not identified. In particular, the total volumes of muscle and blood cannot be identified from only concentration data. We therefore reparameterise this relative to the. uscle volume V_m.

We define rho as the ratio of blood to muscle volumes:
  \rho = V_b / V_m

We scale the permeability and threshold transfer parameters by the blood volume:
  a_m = P_m / V_b
  a_b = P_b / V_b
  r_b = \eta_{threshold} / V_b

since:
  P_m / V_m = (P_m / V_b) (V_b / V_m) = \rho a_m 

we have the reparameterised model:

  dC_m/dt = \lambda - \rho a_m (C_b - C_m)
  dC_b/dt = a_m (C_b - C_m) - r_b tanh(a_b (C_b - C_{min}) / r_b)

with two fewer parameters:
 \rho > 0
 a_m > 0
 a_b > 0
 r_b > 0
 \alpha
 \beta > 0

where beta must be positive because the increase in lactate concentration is assumed to increase with heart rate, and others are positive by construction (ratios and rates).

### Sampling model

The data available to infer these parameters are from graded incremental exercise tests for various participants in cycling and running. The protocol has participants warm up, stand stationary for 3 minutes, and then perform a continuous series of 3 minute efforts with increasing exercise intensity. Two relevant types of data are collected for each of these 3 minute periods (stationary and efforts)
Two types of data are available for each period, for each participant:
 - average heart rate over the period, in beats per minute (bpm)
 - the measured concentration of lactate in the blood in millimoles per litre (mmol.L^-1) in a small blood sample taken at the end of the 3 minute period.

Since the amount of work is kept roughly constant within each period, we convert the average heart rate measuements into a piecewise constant continuous function on time: h(t). Given the reparameterised process equations and parameters listed above, we model a continuous-time function of blood lactate concentration as:

  \lambda(t) = \alpha + \beta h(t)
  C_b(t) = \int_0^t dC_b/dt dt

We define a Gaussian sampling model for each blood lactate concentration measurement B_i using this modelled function, where t(i) denotes the time corresponding to blood lactate observation i - the end of each 3 minute period - and an observation standard deviation parameter \sigma:

  B_i ~ N(C_b(t(i)), \sigma^2)

### Priors

We should be able to define an informative prior on sigma from literature on the measurement error of lactate tests. For all other parameters we will have to define reasonable priors by prior predictive checking. As a heuristic, blood lactate in a sports setting (ie. not in a medical emergency) has been observed as high as 32 mmol.L^-1 [(Osnes & Hermansen, 1972)](https://doi.org/10.1152/jappl.1972.32.1.59).

## Data

We will infer the model parameters for each participant in the cycling and running records of a large dataset of graded incremental exercise tests, which give these average heart rates and blood lactate measurements: [Bernard et al. (2024)](https://zenodo.org/records/10841412).
