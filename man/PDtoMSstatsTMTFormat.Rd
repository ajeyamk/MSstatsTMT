% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/converters.R
\name{PDtoMSstatsTMTFormat}
\alias{PDtoMSstatsTMTFormat}
\title{Convert Proteome Discoverer output to MSstatsTMT format.}
\usage{
PDtoMSstatsTMTFormat(
  input,
  annotation,
  which.proteinid = "Protein.Accessions",
  useNumProteinsColumn = TRUE,
  useUniquePeptide = TRUE,
  rmPSM_withfewMea_withinRun = TRUE,
  rmProtein_with1Feature = FALSE,
  summaryforMultipleRows = sum,
  use_log_file = TRUE,
  append = FALSE,
  verbose = TRUE,
  log_file_path = NULL,
  session_info_path = NULL,
  ...
)
}
\arguments{
\item{input}{PD report or a path to it.}

\item{annotation}{annotation with Run, Fraction, TechRepMixture, Mixture, Channel, 
BioReplicate, Condition columns or a path to file. Refer to the example 'annotation' for the meaning of each column.}

\item{which.proteinid}{Use 'Proteins'(default) column for protein name. 'Leading.proteins' or 'Leading.razor.proteins' or 'Gene.names' can be used instead to get the protein ID with single protein. However, those can potentially have the shared peptides.}

\item{useNumProteinsColumn}{logical, if TRUE, shared peptides will be removed.}

\item{useUniquePeptide}{lgl, if TRUE (default) removes peptides that are assigned for more than one proteins. We assume to use unique peptide for each protein.}

\item{rmPSM_withfewMea_withinRun}{TRUE (default) will remove the features that have 1 or 2 measurements within each Run.}

\item{rmProtein_with1Feature}{TRUE will remove the proteins which have only 1 peptide and charge. Defaut is FALSE.}

\item{summaryforMultipleRows}{sum (default) or max - when there are multiple measurements for certain feature in certain run, select the feature with the largest summation or maximal value.}

\item{...}{additional parameters to `data.table::fread`.}
}
\value{
`data.frame` of class `MSstatsTMT`
}
\description{
Convert Proteome Discoverer output to MSstatsTMT format.
}
