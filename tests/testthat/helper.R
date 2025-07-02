on_windows <- function() {
  isTRUE(Sys.info()[['sysname']] == "Windows")
}

rscript_binary <- function() {
  if (on_windows()) {
    return(file.path(R.home("bin"), "Rscript.exe"))
  }

  file.path(R.home("bin"), "Rscript")
}
