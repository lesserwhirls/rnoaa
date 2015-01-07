#' Get GHCND daily data from NOAA FTP server
#' 
#' @importFrom tidyr gather
#' @importFrom dplyr tbl_df mutate rename select %>%
#' @export
#'
#' @param stationid Stationid to get
#' @param path (character) A path to store the files, Default: \code{~/.rnoaa/isd}
#' @param overwrite (logical) To overwrite the path to store files in or not, Default: TRUE.
#' @param ... Curl options passed on to \code{\link[httr]{GET}}
#' @param n Number of rows to print
#' @param x Input object to print methods. For \code{ghcnd_splitvars()}, the output of a call 
#' to \code{ghcnd()}.
#'
#' @examples \dontrun{
#' # Get metadata
#' ghcnd_states()
#' ghcnd_countries()
#' ghcnd_version()
#' 
#' # Get stations, ghcnd-stations and ghcnd-inventory merged
#' (stations <- ghcnd_stations())
#'
#' # Get data
#' ghcnd(stationid="AGE00147704")
#' ghcnd(stations$id[40])
#' ghcnd(stations$id[4000])
#' ghcnd(stations$id[10000])
#' ghcnd(stations$id[80000])
#'
#' # manipulate data
#' ## using built in fxns
#' (alldat <- ghcnd_splitvars(dat))
#' library("ggplot2")
#' ggplot(subset(alldat$tmax, tmax >= 0), aes(date, tmax)) + geom_point()
#' 
#' ## using dplyr
#' library("dplyr")
#' dat <- ghcnd(stationid="AGE00147704")
#' dat$data %>%
#'  filter(element == "PRCP", year == 1909)
#' }

ghcnd <- function(stationid, path = "~/.rnoaa/ghcnd", overwrite = TRUE, ...){
  csvpath <- ghcnd_local(stationid, path)
  if(!is_ghcnd(x = csvpath)){
    structure(list(data=ghcnd_GET(path, stationid, overwrite, ...)), class="ghcnd", source=csvpath)
  } else {
    structure(list(data=read.csv(csvpath, stringsAsFactors = FALSE)), class="ghcnd", source=csvpath)
  }
}

#' @export
print.ghcnd <- function(x, ..., n = 10){
  cat("<GHCND Data>", sep = "\n")
  cat(sprintf("Size: %s X %s", NROW(x$data), NCOL(x$data)), sep = "\n")
  cat(sprintf("Source: %s\n", attr(x, "source")), sep = "\n")
  trunc_mat_(x$data, n = n)
}

#' @export
#' @rdname ghcnd
ghcnd_splitvars <- function(x){
  tmp <- x$data
  tmp <- tmp[!is.na(tmp$id),]
  # tmp$date <- as.Date(sprintf("%s-%s-01", tmp$year, tmp$month), "%Y-%m-%d")
  # tmp2 <- tmp %>% tbl_df() %>% select(-contains("FLAG"))
  out <- lapply(as.character(unique(tmp$element)), function(y){
    dd <- tmp[ tmp$element == y, ] %>% 
      select(-contains("FLAG")) %>% 
      gather(var, value, -id, -year, -month, -element) %>%
      mutate(day = strex(var), date = as.Date(sprintf("%s-%s-%s", year, month, day), "%Y-%m-%d")) %>% 
      filter(!is.na(date)) %>% 
      select(-element, -var, -year, -month, -day)
    dd <- setNames(dd, c("id",tolower(y),"date"))
    
    mflag <- tmp[ tmp$element == y, ] %>% 
      select(-contains("VALUE"), -contains("QFLAG"), -contains("SFLAG")) %>% 
      gather(var, value, -id, -year, -month, -element) %>%
      mutate(day = strex(var), date = as.Date(sprintf("%s-%s-%s", year, month, day), "%Y-%m-%d")) %>% 
      filter(!is.na(date)) %>% 
      select(value) %>% 
      rename(mflag = value)
    
    qflag <- tmp[ tmp$element == y, ] %>% 
      select(-contains("VALUE"), -contains("MFLAG"), -contains("SFLAG")) %>% 
      gather(var, value, -id, -year, -month, -element) %>%
      mutate(day = strex(var), date = as.Date(sprintf("%s-%s-%s", year, month, day), "%Y-%m-%d")) %>% 
      filter(!is.na(date)) %>% 
      select(value) %>% 
      rename(qflag = value)
      
    sflag <- tmp[ tmp$element == y, ] %>% 
      select(-contains("VALUE"), -contains("QFLAG"), -contains("MFLAG")) %>% 
      gather(var, value, -id, -year, -month, -element) %>%
      mutate(day = strex(var), date = as.Date(sprintf("%s-%s-%s", year, month, day), "%Y-%m-%d")) %>% 
      filter(!is.na(date)) %>% 
      select(value) %>% 
      rename(sflag = value)
    
    tbl_df(cbind(dd, mflag, qflag, sflag))
  })
  setNames(out, tolower(unique(tmp$element)))
}

strex <- function(x) str_extract_(x, "[0-9]+")

# ghcnd_mergevars <- function(x){
#   merge(x[[2]], x[[3]] %>% select(-id), by='date')
# }

#' @export
#' @rdname ghcnd
ghcnd_stations <- function(..., n = 10){
  sta <- get_stations(...)
  inv <- get_inventory(...)
  structure(list(data=merge(sta, inv[,-c(2,3)], by = "id")), class = "ghcnd_stations")
}

#' @export
print.ghcnd_stations <- function(x, ..., n = 10){
  cat("<GHCND Station Data>", sep = "\n")
  cat(sprintf("Size: %s X %s\n", NROW(x$data), NCOL(x$data)), sep = "\n")
  trunc_mat_(x$data, n = n)
}

get_stations <- function(...){
  res <- suppressWarnings(GET("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-stations.txt", ...))
  df <- read.fwf(textConnection(content(res, "text")), widths = c(11, 9, 11, 7, 33, 5, 10), header = FALSE, strip.white=TRUE, comment.char="", stringsAsFactors=FALSE)
  nms <- c("id","latitude", "longitude", "elevation", "name", "gsn_flag", "wmo_id")
  setNames(df, nms)
}

get_inventory <- function(...){
  res <- suppressWarnings(GET("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-inventory.txt", ...))
  df <- read.fwf(textConnection(content(res, "text")), widths = c(11, 9, 10, 5, 5, 5), header = FALSE, strip.white=TRUE, comment.char="", stringsAsFactors=FALSE)
  nms <- c("id","latitude", "longitude", "element", "first_year", "last_year")
  setNames(df, nms)
}

#' @export
#' @rdname ghcnd
ghcnd_states <- function(...){
  res <- suppressWarnings(GET("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-states.txt", ...))
  df <- read.fwf(textConnection(content(res, "text")), widths = c(2, 27), header = FALSE, strip.white=TRUE, comment.char="", stringsAsFactors=FALSE, col.names = c("code","name"))
  df[ -NROW(df) ,]
}

#' @export
#' @rdname ghcnd
ghcnd_countries <- function(...){
  res <- suppressWarnings(GET("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-countries.txt", ...))
  df <- read.fwf(textConnection(content(res, "text")), widths = c(2, 47), header = FALSE, strip.white=TRUE, comment.char="", stringsAsFactors=FALSE, col.names = c("code","name"))
  df[ -NROW(df) ,]
}

#' @export
#' @rdname ghcnd
ghcnd_version <- function(...){
  res <- suppressWarnings(GET("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-version.txt", ...))
  content(res, "text")
}

ghcnd_GET <- function(bp, stationid, overwrite, ...){
  dir.create(bp, showWarnings = FALSE, recursive = TRUE)
  fp <- ghcnd_local(stationid, bp)
  res <- suppressWarnings(GET(ghcnd_remote(stationid), ...))
  tt <- content(res, "text")
  vars <- c("id","year","month","element",do.call("c", lapply(1:31, function(x) paste0(c("VALUE","MFLAG","QFLAG","SFLAG"), x))))
  df <- read.fwf(textConnection(tt), c(11,4,2,4,rep(c(5,1,1,1), 31)), stringsAsFactorse = FALSE)
  dat <- setNames(df, vars)
  write.csv(dat, fp, row.names = FALSE)
  return(dat)
  # res$request$writer[[1]]
}

ghcnd_remote <- function(stationid) file.path(ghcndbase(), paste0(stationid, ".dly"))
ghcnd_local <- function(stationid, path) file.path(path, paste0(stationid, ".dly"))
is_ghcnd <- function(x) if(file.exists(x)) TRUE else FALSE
ghcndbase <- function() "ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/all"
str_extract_ <- function(string, pattern) regmatches(string, regexpr(pattern, string))