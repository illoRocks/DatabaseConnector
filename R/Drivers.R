# @file Drivers.R
#
# Copyright 2023 Observational Health Data Sciences and Informatics
#
# This file is part of DatabaseConnector
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

jdbcDrivers <- new.env()

#' Download DatabaseConnector JDBC Jar files
#'
#' Download the DatabaseConnector JDBC drivers from https://ohdsi.github.io/DatabaseConnectorJars/
#'
#' @param pathToDriver The full path to the folder where the JDBC driver .jar files should be downloaded to.
#'        By default the value of the environment variable "DATABASECONNECTOR_JAR_FOLDER" is used.
#' @param dbms The type of DBMS to download Jar files for.
#'  
#' - "postgresql" for PostgreSQL
#' - "redshift" for Amazon Redshift
#' - "sql server", "pdw" or "synapse" for Microsoft SQL Server
#' - "oracle" for Oracle
#' - "spark" for Spark
#' - "snowflake" for Snowflake
#'  
#' @param method The method used for downloading files. See `?download.file` for details and options.
#' @param ... Further arguments passed on to `download.file`.
#'
#' @details
#' The following versions of the JDBC drivers are currently used:
#' 
#' - PostgreSQL: V42.2.18
#' - RedShift: V2.1.0.9
#' - SQL Server: V8.4.1.zip
#' - Oracle: V19.8
#' - Spark: V2.6.21
#' - Snowflake: V3.13.22
#' 
#' @return Invisibly returns the destination if the download was successful.
#' @export
#'
#' @examples
#' \dontrun{
#' downloadJdbcDrivers("redshift")
#' }
downloadJdbcDrivers <- function(dbms, pathToDriver = Sys.getenv("DATABASECONNECTOR_JAR_FOLDER"), method = "auto", ...) {
  if (is.null(pathToDriver) || is.na(pathToDriver) || pathToDriver == "") {
    abort("The pathToDriver argument must be specified. Consider setting the DATABASECONNECTOR_JAR_FOLDER environment variable, for example in the .Renviron file.")
  }

  if (pathToDriver != Sys.getenv("DATABASECONNECTOR_JAR_FOLDER")) {
    if (Sys.getenv("DATABASECONNECTOR_JAR_FOLDER") != pathToDriver) {
      inform(paste0(
        "Consider adding `DATABASECONNECTOR_JAR_FOLDER='",
        pathToDriver,
        "'` to ",
        path.expand("~/.Renviron"), " and restarting R."
      ))
    }
  }

  pathToDriver <- path.expand(pathToDriver)

  if (!dir.exists(pathToDriver)) {
    if (file.exists(pathToDriver)) {
      abort(paste0("The folder location pathToDriver = '", pathToDriver, "' points to a file, but should point to a folder."))
    }
    warn(paste0("The folder location '", pathToDriver, "' does not exist. Attempting to create."))
    dir.create(pathToDriver, recursive = TRUE)
  }

  stopifnot(is.character(dbms), length(dbms) == 1, dbms %in% c("all", "postgresql", "redshift", "sql server", "oracle", "pdw", "snowflake", "spark"))

  if (dbms == "pdw" || dbms == "synapse") {
    dbms <- "sql server"
  }

  baseUrl <- "https://ohdsi.github.io/DatabaseConnectorJars/"

  jdbcDriverNames <- c(
    "postgresql" = "postgresqlV42.2.18.zip",
    "redshift" = "redShiftV2.1.0.9.zip",
    "sql server" = "sqlServerV9.2.0.zip",
    "oracle" = "oracleV19.8.zip",
    "spark" = "SimbaSparkV2.6.21.zip",
    "snowflake" = "SnowflakeV3.13.22.zip"
  )
  
  if (dbms == "all") {
    dbms <- names(jdbcDriverNames)
  }

  for (db in dbms) {
    if (db == "redshift") {
      oldFiles <- list.files(pathToDriver, "Redshift")
      if (length(oldFiles) > 0) {
        message(sprintf("Prior JAR files have already been detected: '%s'. Do you want to delete them?", paste(oldFiles, collapse = "', '")))
        if (utils::menu(c("Yes", "No")) == 1) {
          unlink(file.path(pathToDriver, oldFiles))
        }
      }
    }
    
    driverName <- jdbcDriverNames[[db]]
    result <- download.file(
      url = paste0(baseUrl, driverName),
      destfile = paste(pathToDriver, driverName, sep = "/"),
      method = method
    )

    extractedFilename <- unzip(file.path(pathToDriver, driverName), exdir = pathToDriver)
    unzipSuccess <- is.character(extractedFilename)

    if (unzipSuccess) {
      file.remove(file.path(pathToDriver, driverName))
    }
    if (unzipSuccess && result == 0) {
      inform(paste0("DatabaseConnector ", db, " JDBC driver downloaded to '", pathToDriver, "'."))
    } else {
      abort(paste0("Downloading and unzipping of ", db, " JDBC driver to '", pathToDriver, "' has failed."))
    }
  }

  invisible(pathToDriver)
}

loadJdbcDriver <- function(driverClass, classPath) {
  rJava::.jaddClassPath(classPath)
  if (nchar(driverClass) && rJava::is.jnull(rJava::.jfindClass(as.character(driverClass)[1]))) {
    abort("Cannot find JDBC driver class ", driverClass)
  }
  jdbcDriver <- rJava::.jnew(driverClass, check = FALSE)
  rJava::.jcheck(TRUE)
  return(jdbcDriver)
}

# Singleton pattern to ensure driver is instantiated only once
getJbcDriverSingleton <- function(driverClass = "", classPath = "") {
  key <- paste(driverClass, classPath)
  if (key %in% ls(jdbcDrivers)) {
    driver <- get(key, jdbcDrivers)
    if (rJava::is.jnull(driver)) {
      driver <- loadJdbcDriver(driverClass, classPath)
      assign(key, driver, envir = jdbcDrivers)
    }
  } else {
    driver <- loadJdbcDriver(driverClass, classPath)
    assign(key, driver, envir = jdbcDrivers)
  }
  driver
}

checkPathToDriver <- function(pathToDriver, dbms) {
  if (!is.null(dbms) && dbms %in% c("sqlite", "sqlite extended")) {
    return()
  }
  if (pathToDriver == "") {
    abort(paste(
      "The `pathToDriver` argument hasn't been specified.",
      "Please set the path to the location containing the JDBC driver.",
      "See `?jdbcDrivers` for instructions on downloading the drivers."
    ))
  }
  if (!dir.exists(pathToDriver)) {
    if (file.exists(pathToDriver)) {
      abort(sprintf(
        "The folder location pathToDriver = '%s' points to a file, but should point to a folder.",
        pathToDriver
      ))
    } else {
      abort(paste(
        "The folder location pathToDriver = '", pathToDriver, "' does not exist.",
        "Please set the path to the location containing the JDBC driver.",
        "See `?jdbcDrivers` for instructions on downloading the drivers."
      ))
    }
  }
}

findPathToJar <- function(name, pathToDriver) {
  checkPathToDriver(pathToDriver, NULL)
  files <- list.files(path = pathToDriver, pattern = name, full.names = TRUE)
  if (length(files) == 0) {
    abort(paste(
      sprintf("No drivers matching pattern '%s'found in folder '%s'.", name, pathToDriver),
      "\nPlease download the JDBC drivers for your database to the folder.",
      "See `?jdbcDrivers` for instructions on downloading the drivers."
    ))
  } else {
    return(files)
  }
}
