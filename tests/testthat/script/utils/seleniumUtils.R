# from find.package('RSelenium')/examples/serverUtils/*.R

startSelServer <- function() {
  library(XML)
  suppressWarnings(system('taskkill /f /im java.exe', show.output.on.console = F))
  suppressWarnings(system('taskkill /f /im phantomjs.exe', show.output.on.console = F))
  source(paste0(find.package('RSelenium'), '/examples/serverUtils/startServer.R'))
  
  for (i in 1:2) {
    res <- tryCatch(startServer(), 
                    error=function(e) grepl('Run checkForServer', e$message))
    if (is.logical(res) && res) {
      source(paste0(find.package('RSelenium'), '/examples/serverUtils/checkForServer.R'))
      checkForServer()
    } else {
      return(res)
    }
  }
  stop()
  # system('chcp 65001')  # for windows non-english encoding
  # system('tasklist /fi "imagename eq java.exe"')
  # system('taskkill /f /pid 4668')
}

getDriver <- function(url='http://127.0.0.1', port=6012) {
  phantomJsFile <- paste0(find.package('RSelenium'), '/bin/phantomjs.exe')
  if (!file.exists(phantomJsFile)) {
    stop('Please download the latest version of phantomjs.exe from 
          http://phantomjs.org/download.html to [', dirname(phantomJsFile), ']')
  }
  
  driver <- remoteDriver(
    browserName = "phantomjs", extraCapabilities = 
      list(phantomjs.binary.path = phantomJsFile))
  driver$open(silent = T)  # == capture.output(driver$open(), file='NUL')
  driver$navigate(paste0(url, if (!is.null(port)) paste0(':', port) else ''))
  driver$setWindowSize(1920, 1080)
  driver
}

openPageInBrowser <- function(driver) {
  tmpFileName <- paste0(tempfile(), '.html')
  write(driver$getPageSource()[[1]], file = tmpFileName)
  browseURL(tmpFileName)
}

stopExternals <- function(msgForError=NULL) {
  eval.in.any.env(quote(driver$close()))
  eval.in.any.env(quote(selServer$stop()))
  closeAllConnections()
  if (!is.null(msgForError)) stop(msgForError)
}

getEls <- function(source, query, directChildren=F) {
  if (length(query) > 1) query <- paste0(query, collapse='')
  #grepl('#|\\.\\w|>',query)
  how <- if (grepl('/|@|\\.\\W', query)) 'xpath' else  'css selector'
  res <- if (class(source) == 'remoteDriver') {
    source$findElements(how, query)
  } else if (class(source) == 'webElement') {
    if (how == 'xpath') {
      if (grepl('^[\\./]', query)) stopExternals('Wrong query')  # starts with neither . nor /
      query <- paste0('./', if (!directChildren) '/', query)
    }
    source$findChildElements(how, query)
  } else {
    stopExternals('Wrong class of "source"')
  }
  # if (!length(res)) warning('>> empty')
  res
}

getEl <- function(source, query, directChildren=F) {
  res <- getEls(source, query, directChildren)
  if (length(res) > 1) {
    print(html(res))
    stopExternals(sprintf('\nElements found: %s', length(res)))
  }
  if (length(res) == 1) res[[1]]
}

isWebElement <- function(obj) class(obj) == 'webElement'

stopIfNotWebElement <- function(obj) {
  if (!isWebElement(obj)) stopExternals('Input element class: ', class(obj))
}

attr <- function(el, attrName) {
  if (!length(el)) return(el)
  stopIfNotWebElement(if (is.list(el)) el[[1]] else el)
  if (!is.list(el)) el <- list(el)
  
  unlist(lapply(el, function(x) {
    res <- x$getElementAttribute(attrName)
    if (length(res) == 1) res[[1]] else if (length(res) > 1) res
  }))
}

html <- function(el) attr(el, 'outerHTML')

text <- function(el) attr(el, 'outerText')

isVisible <- function(el) {
  stopIfNotWebElement(el)
  el$isElementDisplayed()[[1]]
}

click <- function(el) {
  stopIfNotWebElement(el)
  if (!isVisible(el)) {
    browser()
    stopExternals('Input element is invisible: ', html(el))
  }
  el$clickElement()
}

filterElByAttr <- function(els, attrKey, attrVal) {
  if (!is.list(els)) stopExternals('Wrong "els" class')
  res <- Filter(function(x) attr(x, attrKey) == attrVal, els)
  if (length(res) != 1) stopExternals('')
  res[[1]]
}

moveSlider <- function(driver, dotEl, pos) {
  driver$mouseMoveToLocation(webElement = dotEl)
  driver$buttondown()
  driver$mouseMoveToLocation(x = pos - dotEl$getElementLocation()$x, y = -1L)
  driver$buttonup()
}

waitFor <- function(target, source=driver, timeout=10, errorIfNot=T, catchStale=F) {
  nChecks <- 2 * timeout
  oneWaitDur <- timeout / nChecks
  
  targetFun <- 
    if (is.function(target)) {
      target
    } else if (is.character(target)) {
      function(source) unlist(lapply(target, function(x) getEls(source, x)))
    } else if (is.call(target)) {  # if quoted expression
      function(source) eval.in.any.env(target)
    } else {
      stop(sprintf('Not implemented for target class [%s]', class(target)))
    }
  
  for (i in 1:nChecks) {
    res <- suppressMessages(tryCatch(
      targetFun(source),
      error=function(e) if (catchStale && isStaleException(e)) F else {
        browser()
        stop(e$message)
      }))
    
    if (is.list(res)) {
      if (length(target) == 1) {
        if (length(res)) {
          return(invisible(if (length(res) > 1) res else res[[1]]))
        }
      } else {
        if (length(Filter(length, res)) == 1) {
          return(Filter(length, res)[[1]])
        }
      }
    } else if (is.logical(res) && res) {
      return(TRUE)
    }
    Sys.sleep(oneWaitDur)
  }
  
  if (errorIfNot) stop('Could not wait') else F
}