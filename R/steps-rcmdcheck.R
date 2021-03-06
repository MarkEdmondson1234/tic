RCMDcheck <- R6Class( # nolint
  "RCMDcheck",
  inherit = TicStep,

  public = list(
    initialize = function(warnings_are_errors = NULL, notes_are_errors = NULL,
                          args = c("--no-manual", "--as-cran"),
                          build_args = "--force", error_on = "warning",
                          repos = repo_default(), timeout = Inf,
                          check_dir = NULL) {
      if (!is.null(notes_are_errors)) {
        warning_once(
          '`notes_are_errors` is deprecated, please use `error_on = "note"`'
        )
        if (notes_are_errors) {
          error_on <- "note"
        }
      }
      else if (!is.null(warnings_are_errors)) {
        warning_once(
          "`warnings_are_errors` is deprecated, ",
          'please use `error_on = "warning"`'
        )
        if (warnings_are_errors) {
          error_on <- "warning"
        }
      }
      private$args <- args
      private$build_args <- build_args
      private$error_on <- error_on
      private$repos <- repos
      private$timeout <- timeout
      private$check_dir <- check_dir

      super$initialize()
    },

    run = function() {
      # Don't include vignettes if --no-build-vignettes is included
      if ("--no-build-vignettes" %in% private$args) {
        cat("^vignettes$\n", file = ".Rbuildignore", append = TRUE)
      }

      withr::with_envvar(
        c(
          # Avoid large version components
          "_R_CHECK_CRAN_INCOMING_" = "FALSE",
          # Don't check system clocks (because the API used there is flaky)
          "_R_CHECK_SYSTEM_CLOCK_" = "FALSE",
          # Don't force suggests
          "_R_CHECK_FORCE_SUGGESTS_" = "FALSE",
          # Work around missing qpdf executable
          "R_QPDF" = if (Sys.which("qpdf") == "") "true"
        ),
        res <- rcmdcheck::rcmdcheck(
          args = private$args, build_args = private$build_args,
          error_on = "never",
          repos = private$repos,
          timeout = private$timeout,
          check_dir = private$check_dir
        )
      )

      print(res)
      if (length(res$errors) > 0) {
        stopc("Errors found in rcmdcheck::rcmdcheck().")
      }
      if (private$error_on %in% c("warning", "note") && length(res$warnings) > 0) {
        stopc(
          "Warnings found in rcmdcheck::rcmdcheck(), ",
          'and `errors_on = "warning"` is set.'
        )
      }
      if (private$error_on == "note" && length(res$notes) > 0) {
        stopc(
          "Notes found in rcmdcheck::rcmdcheck(), ",
          'and `errors_on = "note"` is set.'
        )
      }
    },

    prepare = function() {
      verify_install("rcmdcheck")
      super$prepare()
    }
  ),

  private = list(
    args = NULL,
    build_args = NULL,
    error_on = NULL,
    repos = NULL,
    timeout = NULL,
    check_dir = NULL
  )
)

#' Step: Check a package
#'
#' Check a package using [rcmdcheck::rcmdcheck()],
#' which ultimately calls `R CMD check`.
#'
#' @section Updating of (dependency) packages:
#' Packages shipped with the R-installation will not be updated as they will be
#' overwritten by the Travis R-installer in each build.
#' If you want these package to be updated, please add the following
#' step to your workflow: `add_code_step(remotes::update_packages("<pkg>"))`.
#'
#' @param ... Ignored, used to enforce naming of arguments.
#' @param warnings_are_errors,notes_are_errors `[flag]`\cr
#'   Deprecated, use `error_on`.
#' @param error_on `[character]`\cr
#'   Whether to throw an error on R CMD check failures. Note that the check is
#'   always completed (unless a timeout happens), and the error is only thrown
#'   after completion. If "never", then no errors are thrown. If "error", then
#'   only ERROR failures generate errors. If "warning", then WARNING failures
#'   generate errors as well. If "note", then any check failure generated an
#'   error.
#' @param repos `[character]`\cr
#'   Passed to `rcmdcheck::rcmdcheck()`, default:
#'   [repo_default()].
#' @param timeout `[numeric]`\cr
#'   Passed to `rcmdcheck::rcmdcheck()`, default:
#'   `Inf`.
#' @param check_dir `[character]` \cr Path specifying the directory for R CMD
#'   check. Defaults to `"check"` for easy upload of artifacts.
#' @export
#' @examples
#' dsl_init()
#'
#' get_stage("script") %>%
#'   add_step(step_rcmdcheck(error_on = "note", repos = repo_bioc()))
#'
#' dsl_get()
step_rcmdcheck <- function(...,
                           warnings_are_errors = NULL,
                           notes_are_errors = NULL,
                           args = NULL,
                           build_args = NULL,
                           error_on = "warning",
                           repos = repo_default(),
                           timeout = Inf,
                           check_dir = "check") {

  #' @param build_args `[character]`\cr
  #'   Passed to `rcmdcheck::rcmdcheck()`.\cr
  #'   Default for Travis and local runs: `"--force"`.\cr
  #'   Default for Appveyor: `c("--no-build-vignettes", "--force")`.\cr
  if (is.null(build_args)) {
    if (isTRUE(ci_on_appveyor())) {
      build_args <- c("--no-build-vignettes", "--force")
    } else {
      build_args <- "--force"
    }
  }

  #' @param args `[character]`\cr
  #'   Passed to `rcmdcheck::rcmdcheck()`.\cr
  #'
  #'   Default for Travis and local runs: `c("--no-manual", "--as-cran")`.
  #'
  #'   Default for Appveyor and GitHub Actions (Windows):
  #'   `c("--no-manual", "--as-cran", "--no-vignettes",
  #'   "--no-build-vignettes", "--no-multiarch")`.
  #'
  #'   On GitHub Actions option "--no-manual" is always used (appended to custom
  #'   user input) because LaTeX is not available and installation is time
  #'   consuming and error prone.\cr
  if (is.null(args)) {
    if (isTRUE(ci_on_appveyor()) ||
      isTRUE((ci_on_ghactions() &&
        Sys.info()[["sysname"]] == "Windows"))) {
      args <- c(
        "--no-manual", "--as-cran", "--no-vignettes",
        "--no-build-vignettes", "--no-multiarch"
      )
    } else {
      if (isTRUE((ci_on_ghactions() &&
        Sys.info()[["sysname"]] == "Windows"))) {
        args <- append(args, "--no-manual")
        cli_alert_info("{.fun step_rcmdcheck}: {.pkg tic} always appends option
                     '--no-manual' during R CMD Check on Windows because LaTeX
                     is not available.", wrap = TRUE)
      } else {
        args <- c("--no-manual", "--as-cran")
      }
    }
  } else {
    if (isTRUE((ci_on_ghactions() &&
      Sys.info()[["sysname"]] == "Windows"))) {
      args <- append(args, "--no-manual")
      cli_alert_info("{.fun step_rcmdcheck}: {.pkg tic} always uses option
                     '--no-manual' during R CMD Check on Windows because LaTeX
                     is not available.", wrap = TRUE)
    }
  }

  RCMDcheck$new(
    warnings_are_errors = warnings_are_errors,
    notes_are_errors = notes_are_errors,
    args = args,
    build_args = build_args,
    error_on = error_on,
    repos = repos,
    timeout = timeout,
    check_dir = check_dir
  )
}

# withr usage from R6 methods not recognized
use_withr <- function() {
  withr::with_environment(c(a = "b"), TRUE)
}
