#' @importFrom dplyr select
#' @importFrom dplyr filter
#' @importFrom dplyr %>%
#' @importFrom dplyr left_join
#' @importFrom tidyr gather
#' @importFrom tidyr spread
#' @importFrom MSstats dataProcess
#' @importFrom stats medpolish
#' @importFrom matrixStats colMedians
#' @importFrom data.table :=

.protein.summarization.function <- function(data,
                                           method,
                                           normalization,
                                           MBimpute,
                                           maxQuantileforCensored){

    ProteinName = runchannel = MSRun = log2Intensity = Run = . = NULL
    v = Channel = Run.Protein = NULL

    data <- as.data.table(data)
    ## make sure the protein ID is character
    data$ProteinName <- as.character(data$ProteinName)
    ## make new column: combination of run and channel
    data$runchannel <- paste(data$Run, data$Channel, sep = '_')
    data$log2Intensity <- log2(data$Intensity)
    ## Number of negative values : if intensity is less than 1
    ## replace with zero
    ## then we don't need to worry about -Inf = log2(0)
    if (nrow(data[!is.na(data$Intensity) & data$Intensity < 1]) > 0){
        data[!is.na(data$Intensity) & data$Intensity < 1, 'log2Intensity'] <- 0
        message('** Negative log2 intensities were replaced with zero.')
    }

    ## Record the group information
    annotation <- unique(data[ , c('Run', 'Channel', 'BioReplicate',
                                   'Condition', 'Mixture', 'runchannel')])

    # Prepare the information for protein summarization
    runs <- unique(data$Run) # record runs
    num.run <- length(runs) # number of runs
    runchannel.id <- unique(data$runchannel) # record runs X channels
    data$PSM <- as.character(data$PSM)

    if (method == 'msstats'){
        ## need to change the column for MSstats
        colnames(data)[colnames(data) == 'Charge'] <- 'PrecursorCharge'
        colnames(data)[colnames(data) == 'Run'] <- 'MSRun'
        colnames(data)[colnames(data) == 'runchannel'] <- 'Run'
        ## channel should be 'Run' for MSstats

        data$FragmentIon <- NA
        data$ProductCharge <- NA
        data$IsotopeLabelType <- 'L'

        proteins <- unique(data$ProteinName)
        num.protein <- length(proteins)
        runs <- unique(data$MSRun)
        runchannel.id <- unique(data$runchannel)
        num.run <- length(runs)

        res <- NULL
        for (i in 1:num.run) {
            ## For each run, use msstats dataprocess
            message(paste("Summarizing for Run :", runs[i] ,
                          "(", i, " of ", num.run, ")"))
            sub_data <- data %>% filter(MSRun == runs[i])
            output.msstats <- dataProcess(sub_data,
                                          normalization=FALSE,
                                          summaryMethod = 'TMP',
                                          censoredInt= 'NA',
                                          MBimpute = MBimpute,
                                          maxQuantileforCensored = maxQuantileforCensored)
            ## output.msstats$RunlevelData : include the protein level summary
            res.sub <- output.msstats$RunlevelData
            res.sub <- res.sub[which(colnames(res.sub) %in% c('Protein',
                                                              'LogIntensities', 'originalRUN'))]
            colnames(res.sub)[colnames(res.sub) == 'LogIntensities'] <- 'Abundance'
            colnames(res.sub)[colnames(res.sub) == 'originalRUN'] <- 'runchannel'
            res.sub$runchannel <- as.character(res.sub$runchannel)
            annotation$runchannel <- as.character(annotation$runchannel)
            res.sub <- left_join(res.sub, annotation, by='runchannel')

            ## remove runchannel column
            res.sub <- res.sub[, -which(colnames(res.sub) %in% 'runchannel')]
            res <- rbind(res, res.sub)

        }

        if (normalization & length(runs) > 1) { # Do normalization based on group 'Norm'
            res <- .protein.normalization(res)
        }

    } else if (method == "MedianPolish"){
        #Method MedianPolish
        #add NAs to make every protein appear in all the channels

        ## add more annotation and block
        data <- data[, c('ProteinName', 'PSM', 'log2Intensity', 'Run', 'Channel',
                         'BioReplicate', 'runchannel')]
        channels <- as.character(unique(data$Channel))

        #Create a annotation to make sure there are no missing Channels for each protein in data
        anno <- unique(data[, c("Run", "ProteinName")])#name of each run and protein
        anno.len <- nrow(anno)
        channel.len <- length(channels)
        mat <- matrix(rep(channels,anno.len), nrow = channel.len)
        dt <- as.data.frame(t(mat))
        anno <- cbind(anno, dt)#attach channels to each run and protein

        anno <- anno %>% unite("Run.Protein", Run,ProteinName,sep = " ") %>%
            gather(v, Channel, -Run.Protein) %>%
            separate(Run.Protein, into = c("Run", "ProteinName"),sep = " ")
        anno$Run <- as.character(anno$Run)
        data <- right_join(data, anno)

        #Create a annotation to make sure there are no missing PSMs for each Run and Protein
        anno1 <- unique(data[, c("Run", "ProteinName", "PSM")])
        anno2 <- full_join(anno,anno1) %>%
            select("Run", "ProteinName", "Channel", "PSM")
        data <- right_join(data, anno2) #runchannel+1 after this line

        #Create a annotation for "runchannel" sorted by Run and ProteinName
        data$runchannel <- paste(data$Run, data$Channel, sep = '_')
        data <- as.data.table(data)
        data <- data[order(data$Run, data$ProteinName), ]
        anno3 <- unique(data[, c("runchannel", "ProteinName" ,"Run")])
        anno3 <- anno3[order(anno3$Run, anno3$ProteinName), ]

        #Computer by each Run and ProteinName
        res <- data[, .(MedianPolish = .medianPolish(log2Intensity,
                                                           channel.len)), by = .(Run, ProteinName)]
        colnames(res) <- c("Run", "ProteinName", "Abundance")
        res$runchannel <- anno3$runchannel
        res <- left_join(res, annotation, by = 'runchannel')
        res$Run <- res$Run.x #delete x and y

        #Protein Normalization
        if (normalization & length(runs) > 1) {
            # Do normalization based on group 'Norm'
            res <- .protein.normalization(res)
        }
        res$Protein <- res$ProteinName

    } else if (method == "LogSum"){

        #Method LogSum
        data <- data[, c('ProteinName', 'PSM', 'log2Intensity', 'Run', 'Channel',
                         'BioReplicate', 'runchannel')]
        res <- data[, .(LogSum = log2(sum(2^log2Intensity))), by = .(Run,ProteinName,
                                                                   runchannel)] # calculate the logsum for each protein and channel
        colnames(res) <- c("Run", "ProteinName", "runchannel", "Abundance")
        res <- left_join(res, annotation, by = 'runchannel')
        # add the annotation information to the results
        res$Run <- res$Run.x #delete x and y

        if (normalization & length(runs) > 1) {
            # Do normalization based on group 'Norm'
            res <- .protein.normalization(res)
        }
        res$Protein <- res$ProteinName

    } else if (method == "Median"){
        #Method Median
        data <- data[, c('ProteinName', 'PSM', 'log2Intensity', 'Run', 'Channel',
                         'BioReplicate', 'runchannel')]
        res <- data[, .(Median = median(log2Intensity)), by = .(Run,ProteinName,
                                                              runchannel)] # calculate the median for each protein and channel
        colnames(res) <- c("Run", "ProteinName", "runchannel", "Abundance")
        res <- left_join(res, annotation, by = 'runchannel')
        # add the annotation information to the results
        res$Run <- res$Run.x #delete x and y

        if (normalization & length(runs) > 1) {
            # Do normalization based on group 'Norm'
            res <- .protein.normalization(res)
        }
        res$Protein <- res$ProteinName
    }

    res <- res[, c("Run", "Protein", "Abundance", "Channel", "BioReplicate",
                   "Condition", "Mixture")]

    res$Run <- as.factor(res$Run) # make sure Run is factor
    res$Channel <- as.factor(res$Channel) # make sure Channel is factor
    res$Condition <- as.factor(res$Condition) # make sure Condition is factor
    res$Mixture <- as.factor(res$Mixture) # make sure mixture is factor

    return(res)
}



###########################################
## function for normalization between MS runs
## Do normalization after protein summarization.
## Normalization are based on the channels which have group 'Norm'.
## data: protein level data, which has columns Protein, Group, Subject, Run, Channel, Abundance

.protein.normalization <- function(data) {

    Run <- Abundance <- . <- Condition <- Protein <- NULL

    ## check whethere there are 'Norm' info or not.
    group.info <- unique(data$Condition)

    ## if there is 'Norm' available in Condition column,
    if (is.element('Norm', group.info)) {

        data$Protein <- as.character(data$Protein)

        # make sure protein names are character
        proteins <- unique(data$Protein) # proteins
        num.protein <- length(proteins)
        data <- as.data.table(data)

        # make suree the input data is with data table format
        norm.data <- list()

        # do inference for each protein individually
        for (i in 1:length(proteins)) {

            message(paste("Normalization between MS runs for Protein :",
                          proteins[i] , "(", i, " of ", num.protein, ")"))

            sub_data <- data[Protein == proteins[i]] # data for protein i
            sub_data <- na.omit(sub_data)
            norm.channel <- sub_data[Condition == "Norm"]
            norm.channel <- norm.channel[, .(Abundance = mean(Abundance, na.rm = TRUE)),
                                         by = .(Protein, Run)]
            norm.channel$diff <- median(norm.channel$Abundance, na.rm = TRUE) -
                norm.channel$Abundance
            setkey(sub_data, Run)
            setkey(norm.channel, Run)
            norm.sub_data <- merge(sub_data, norm.channel[, .(Run, diff)], all.x = TRUE)
            norm.sub_data$Abundance <- norm.sub_data$Abundance + norm.sub_data$diff
            norm.sub_data[, diff:=NULL]
            norm.data[[proteins[i]]] <- norm.sub_data
        }
        norm.data <- rbindlist(norm.data)

    } else {
        message("** 'Norm' information in Condition is required for normalization.
                Please check it. At this moment, normalization is not performed.")
        norm.data <- data
    }

    return(norm.data)
}


###########################################
## function for MedianPolish calculation
## depend on "stats:medpolish"
## input: a vector of log2intensity per Protein, Run; number of channels

.medianPolish <- function(c, num.channels){
    #take a vector
    #transfor to a matrix
    #perform MedianPolish
    #return a vector

    len <- length(c)
    # if(len%%num.channels){
    #   print("channel violation")
    # }
    #print(num.channels)
    mat <- as.matrix(c)
    dim(mat) <- c(len / num.channels,num.channels)
    meddata  <-  stats::medpolish(mat, na.rm = TRUE, trace.iter = FALSE)
    tmpresult <- meddata$overall + meddata$col
    return(tmpresult)
}
