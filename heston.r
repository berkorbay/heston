# The Heston Stochastic Volatility model
#
# - Closed form solution for a European call option
# - Monte Carlo solution (Absorbing at zero)
# - Monte Carlo solution (Reflecting at zero)
# - Monte Carlo solution (Reflecting at zero + Milstein method)
# - Monte Carlo solution (Alfonsi)
# - Plot implied volality surface
#
# Dale Roberts <dale.roberts@anu.edu.au>
#

ONEYEAR <- 365
OPAR <- par(mai=c(0.2,0.1,0.1,0.1),family="sans",ps="8")

Moneyness <- function(S, K, tau, r) {
   K*exp(-r*tau)/S
 }

BlackScholesCall <- function(S0, K, tau, r, sigma) {
	EPS <- 0.01
	d1 <- (log(S0/K) + (r + 0.5*sigma^2)*tau)/(sigma*sqrt(tau))
	d2 <- d1 - sigma*sqrt(tau)
	if (T < EPS) {
		return(max(S0-K,0))
	} else {
	 	return(S0*pnorm(d1) - K*exp(-r*(tau))*pnorm(d2))
	}
}

ImpliedVolCall <- function(S0, K, tau, r, price) {
  f <- function(x) BlackScholesCall(S0,K,tau,r,x) - price
  if (f(-1) * f(1) > 0) { cat("tau=",tau,"\n"); return(NA) } # hack
  iv <- uniroot(f,c(-1,1))$root
	return(iv)
}

HestonCallClosedForm <-
function(lambda, vbar, eta, rho, v0, r, tau, S0, K) {
	PIntegrand <- function(u, lambda, vbar, eta, rho, v0, r, tau, S0, K, j) {
	  F <- S0*exp(r*tau)
	  x <- log(F/K)
	  a <- lambda * vbar
	  
	  if (j == 1) {
	    b <- lambda - rho* eta
	    alpha <- - u^2/2 - u/2 * 1i + 1i * u
	    beta <- lambda - rho * eta - rho * eta * 1i * u
	  } else { # j ==0
	    b <- lambda
	    alpha <- - u^2/2 - u/2 * 1i
	    beta <- lambda - rho * eta * 1i * u
	  }
	
	  gamma <- eta^2/2
	  d <- sqrt(beta^2 - 4*alpha*gamma)
	  rplus <- (beta + d)/(2*gamma)
	  rminus <- (beta - d)/(2*gamma)
	  g <- rminus / rplus
	
	  D <- rminus * (1 - exp(-d*tau))/(1-g*exp(-d*tau))
	  C <- lambda * (rminus * tau - 2/(eta^2) * log( (1-g*exp(-d*tau))/(1-g) ) )
	  
	  top <- exp(C*vbar + D*v0 + 1i*u*x)
	  bottom <- (1i * u)
	  Re(top/bottom)
	}
	
	P <- function(lambda, vbar, eta, rho, v0, r, tau, S0, K, j) {
	  value <- integrate(PIntegrand, lower = 0, upper = Inf, lambda, vbar, eta, rho, v0, r, tau, S0, K, j, subdivisions=1000)$value
	  0.5 + 1/pi * value
	}

  A <- S0*P(lambda, vbar, eta, rho, v0, r, tau, S0, K, 1)
  B <- K*exp(-r*tau)*P(lambda, vbar, eta, rho, v0, r, tau, S0, K, 0)
  A-B
}

HestonCallMonteCarlo <-
function(lambda, vbar, eta, rho, v0, r, tau, S0, K, nSteps=2000, nPaths=3000, vneg=2) {

  n <- nSteps
  N <- nPaths
  
  dt <- tau / n
  
  negCount <- 0
  
  S <- rep(S0,N)
  v <- rep(v0,N)
  
  for (i in 1:n)
  {
    W1 <- rnorm(N);
    W2 <- rnorm(N);
    W2 <- rho*W1 + sqrt(1 - rho^2)*W2;

    sqvdt <- sqrt(v*dt)
    S <- S*exp((r-v/2)*dt + sqrt(v * dt) * W1)
    
    if ((vneg == 3) & (2*lambda*vbar/(eta^2) <= 1)) {
        cat("Variance not guaranteed to be positive with choice of lambda, vbar, and eta\n")
        cat("Defaulting to Reflection + Milstein method\n")
        vneg = 2
    }

    if (vneg == 0){
      ## Absorbing condition
      v <- v + lambda*(vbar - v)* dt + eta * sqvdt * W2
      negCount <- negCount + length(v[v < 0])
      v[v < 0] <- 0
    }
    if (vneg == 1){
      # Reflecting condition
      sqvdt <- sqrt(v*dt)
      v <- v + lambda*(vbar - v)* dt + eta * sqvdt * W2
      negCount <- negCount + length(v[v < 0])
      v <- ifelse(v<0, -v, v)
    }
    if (vneg == 2) {
      # Reflecting condition + Milstein
      v <- (sqrt(v) + eta/2*sqrt(dt)*W2)^2 - lambda*(v-vbar)*dt - eta^2/4*dt
      negCount <- negCount + length(v[v < 0])
      v <- ifelse(v<0, -v, v)     
    }
    if (vneg == 3) {
      # Alfonsi - See Gatheral p.23
      v <- v -lambda*(v-vbar)*dt +eta*sqrt(v*dt)*W2 - eta^2/2*dt      
    }
  }
  
  negCount <- negCount / (n*N);

  # Evaluate mean call value for each path
  V <- exp(-r*tau)*(S>K)*(S - K); # Boundary condition for European call
  AV <- mean(V);
  AVdev <- 2 * sd(V) / sqrt(N);

  list(value=AV, lower = AV-AVdev, upper = AV+AVdev, zerohits = negCount)
}

HestonSurface <- function(lambda, vbar, eta, rho, v0, r, tau, S0, K, N=5, min.tau = 1/ONEYEAR) {
  LogStrikes <- seq(-0.5, 0.5, length=N)
  Ks <- rep(0.0,N)
  taus <- seq(min.tau, tau, length=N)
  vols <- matrix(0,N,N)

  TTM <- Money <- Vol <- rep(0,N*N)
  
  HestonPrice <- function(K, tau) {HestonCallClosedForm(lambda, vbar, eta, rho, v0, r, tau, S0, K)}

  n <- 1
  for (i in 1:N) {
    for (j in 1:N) {
      Ks[i] <- exp(r * taus[j]+LogStrikes[i]) * S0
      price <- HestonPrice(Ks[i],taus[j])
      iv <- ImpliedVolCall(S0, Ks[i], taus[j], r, price)
      TTM[n] <- taus[j] * ONEYEAR # in days
      Money[n] <- Moneyness(S0,Ks[i],taus[j],r)
      Vol[n] <- iv
      n<- n+1
    }
  }

  data.frame(TTM=TTM, Moneyness=Money, ImpliedVol=Vol)
}

plotHestonSurface <-
function(lambda, vbar, eta, rho, v0, r, tau, S0, K, N=30, min.tau = 1/ONEYEAR, ...) {
  
  Ks <- seq(0.8*K, 1.25 * K, length=N)  
  taus <- seq(0.21, tau, length=N)
  
  HestonPrice <- Vectorize(function(k, t) {HestonCallClosedForm(lambda, vbar, eta, rho, v0, r, t, S0, k)})
  
  IVHeston <- Vectorize(function(k,t) { ImpliedVolCall(S0, k, t, r, HestonPrice(k,t))})
  
  z <- outer(Ks, taus, IVHeston)
  
  nrz <- nrow(z)
  ncz <- ncol(z)
  nb.col <- 256
  color <- heat.colors(nb.col)
  facet <- - (z[-1, -1] + z[-1, -ncz] + z[-nrz, -1] + z[-nrz, -ncz])
  facetcol <- cut(facet, nb.col)
    
  persp(x=Ks, y=taus, z, theta = 40, phi = 20, expand = 0.5, col=color[facetcol], xlab="Strikes", ylab="Time to maturity", zlab="Implied Volatility", ticktype="detailed", ...) -> res

  return(invisible(z))
}


lambda <- 6.21 # drift scale
vbar <- 0.019 # long-term average volatility
eta <- 0.61 # volatility of vol process
rho <- -0.7 # correlation between stock and vol
v0 <- 0.010201 # initial volatility
r <- 0.0319 # risk-free interest rate
tau <- 1.0 # time to maturity
S0 <- 100 # initial share price
K <- 100 # strike price

#opts <- expand.grid(
#	payoff = c("Put", "Call"),
#	lambda  = seq(0.00, 1.00, length.out=10),
#	vbar   = seq(0.01, 0.08, length.out=10),
#	eta    = seq(0.01, 0.90, length.out=10),
#	rho    = seq(-0.5, -0.5, length.out=10),
#	v0     = seq(0.05, 0.20, length.out=10),
#	r      = seq(0.00, 0.10, length.out=10),
#	tau    = seq(1.00, 5.00, length.out=10),
#	S0     = seq( 100,  200, length.out=10),
#	K      = seq( 100,  200, length.out=10))

cat("lambda =", lambda, "vbar = ", vbar, "eta = ", eta, 
    "rho = ", rho, "v0 = ", v0, "r = ", r, 
    "tau = ", tau, "S0 =", S0, "K = ", K, "\n")

cf <- HestonCallClosedForm(lambda, vbar, eta, rho, v0, r, tau, S0, lambda)
print(cf)

#for (k in c(0.5,0.75,1.00,1.25,1.5)) {
#  cf <- HestonCallClosedForm(lambda, vbar, eta, rho, v0, r, tau, S0, k)
#  mc1 <- HestonCallMonteCarlo(lambda, vbar, eta, rho, v0, r, tau, S0, k, vneg=0)
#  cat(sprintf("%.2f\t%.6f\t%.6f\n", k, cf, mc1))
#}
  
#mc <- HestonCallMonteCarlo(lambda, vbar, eta, rho, v0, r, tau, S0, K, vneg=1)
#cat("Heston Call Monte Carlo (Reflecting) = ", mc$value, " [", mc$lower, ",", mc$upper, "]", "zero hits = ", mc$zerohits, "\n")
# 
# mc <- HestonCallMonteCarlo(lambda, vbar, eta, rho, v0, r, tau, S0, K, vneg=2)
# cat("Heston Call Monte Carlo (Reflecting + Milstein) = ", mc$value, " [", mc$lower, ",", mc$upper, "]", "zero hits = ", mc$zerohits, "\n")
# 
# mc <- HestonCallMonteCarlo(lambda, vbar, eta, rho, v0, r, tau, S0, K, vneg=3)
# cat("Heston Call Monte Carlo (Alfonsi) = ", mc$value, " [", mc$lower, ",", mc$upper, "]", "zero hits = ", mc$zerohits, "\n")

# surf <- HestonSurface(lambda, vbar, eta, rho, v0, r, tau, S0, K, N=10)
# z <- plotImpliedVolSurface(surf, main="Heston Implied Volatility Surface", show.data=T)

z <- plotHestonSurface(lambda, vbar, eta, rho, v0, r, tau, S0, K)

