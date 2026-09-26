## silhouette_helpers.R ##
## Exact closed-form reproduction of clustMixType::kproto2silhouette() for Huang-type k-prototypes ##

#1. Compute individual silhouette widths without building the n x n distance matrix
#1.1 For squared Euclidean (numeric) + weighted simple mismatch (categorical) distance, the mean distance
#    from observation i to all members of cluster C (including i itself, matching clustMixType's convention) is:
#      numeric:     sum_v w_v * [ (x_iv - mean_Cv)^2 + popvar_Cv ]
#      categorical: sum_j l_j * [ 1 - freq_C(x_ij) ]
#    which is algebraically identical to rowMeans() over the full pairwise distance matrix used by the package
silhouette_exact_huang <- function(object) {

  #1.1.1 Validate inputs against the assumptions of the identity
  if (!inherits(object, "kproto")) stop("object must be of class kproto")
  if (!identical(object$type, "huang")) stop("closed form implemented for type = 'huang' only")
  if (is.null(object$data)) stop("kproto object must be fit with keep.data = TRUE")
  x <- object$data
  cl <- object$cluster
  numvars <- vapply(x, is.numeric, logical(1))
  catvars <- vapply(x, is.factor, logical(1))
  if (any(!(numvars | catvars))) stop("all clustering columns must be numeric or factor")
  if (anyNA(x) || anyNA(cl)) stop("closed form requires complete data and cluster assignments")

  #1.1.2 Map lambda onto numeric and categorical weights exactly as clustMixType:::calc.dist() does
  lambda <- object$lambda
  if (length(lambda) == 1) {
    w_num <- rep(1, sum(numvars))
    w_cat <- rep(lambda, sum(catvars))
  } else {
    w_num <- lambda[numvars]
    w_cat <- lambda[catvars]
  }

  #1.1.3 Assemble inputs
  n <- nrow(x)
  K <- length(table(cl))
  X <- as.matrix(x[, numvars, drop = FALSE])
  cat_idx <- which(catvars)
  cluster_dists <- matrix(0, nrow = n, ncol = K)

  #1.1.4 Mean distance from every observation to every cluster
  for (i in seq_len(K)) {
    members <- which(cl == i)

    #1.1.4.1 Numeric component: weighted squared distance to centroid plus weighted within-cluster population variance
    if (ncol(X) > 0) {
      Xc <- X[members, , drop = FALSE]
      mu <- colMeans(Xc)
      pop_var <- colMeans(sweep(Xc, 2, mu)^2)
      cluster_dists[, i] <- colSums(w_num * (t(X) - mu)^2) + sum(w_num * pop_var)
    }

    #1.1.4.2 Categorical component: weighted proportion of cluster members with a different category
    for (jj in seq_along(cat_idx)) {
      v <- x[[cat_idx[jj]]]
      freq <- tabulate(as.integer(v[members]), nbins = nlevels(v)) / length(members)
      cluster_dists[, i] <- cluster_dists[, i] + w_cat[jj] * (1 - freq[as.integer(v)])
    }
  }

  #1.1.5 a(i), b(i), neighbour, and s(i), with the package's special cases
  own <- cbind(seq_len(n), cl)
  a <- cluster_dists[own]
  other <- cluster_dists
  other[own] <- Inf
  b <- apply(other, 1, min)
  neighbor <- max.col(-other, ties.method = "first")
  denom <- pmax(a, b)
  s <- ifelse(denom == 0, 0, (b - a) / denom)

  #1.1.6 Observations in singleton clusters receive s = 0, as in the package
  singletons <- as.integer(names(which(table(cl) == 1)))
  s[cl %in% singletons] <- 0

  #1.1.7 Return an object of class silhouette, structured identically to kproto2silhouette()
  result <- cbind(cluster = cl, neighbor = neighbor, sil_width = s)
  class(result) <- "silhouette"
  attr(result, "Ordered") <- FALSE
  result
}
