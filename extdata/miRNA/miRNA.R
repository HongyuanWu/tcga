######################################################################################
############  miRNA based deep-learning for drug-response prediction #################
######################################################################################
library("randomForest")
library("arm")
library("plyr") 
library("PredictABEL")
library("neuralnet")
source("https://raw.githubusercontent.com/Shicheng-Guo/GscRbasement/master/GscTools.R")
source("https://raw.githubusercontent.com/Shicheng-Guo/HowtoBook/master/TCGA/bin/id2phen4.R")

setwd("/home/guosa/hpc/project/TCGA/pancancer/miRNA/data")
file=list.files(pattern="*mirnas.quantification.txt$",recursive = TRUE)
manifest2barcode("gdc_manifest.pancancer.miRNA.2019-05-29.txt")
barcode<-read.table("/home/guosa/hpc/project/TCGA/pancancer/miRNA/data/barcode.txt",sep="\t",head=T)
data<-c()
for(i in 1:length(file)){
  tmp<-read.table(file[i],head=T,sep="\t",as.is=F)  
  data<-cbind(data,tmp[,3])
  print(paste(i,"in",length(file),file[i],sep=" "))
  rownames(data)<-tmp[,1]
}
colnames(data)<-id2phen4(barcode[match(unlist(lapply(file,function(x) unlist(strsplit(x,"[/]"))[2])),barcode$file_name),ncol(barcode)])
data<-data[,match(unique(colnames(data)),colnames(data))]
save(data,file="TCGA-Pancancer.miRNAseq.RData")
miRNA<-data[,grep("-01",colnames(data))]

setwd("/home/guosa/hpc/project/TCGA")
load("/home/guosa/hpc/project/TCGA/pancancer/miRNA/data/TCGA-Pancancer.miRNAseq.RData")

barcode$id4=id2phen4(barcode$cases.0.samples.0.portions.0.analytes.0.aliquots.0.submitter_id)
phen<-read.table("https://raw.githubusercontent.com/Shicheng-Guo/HowtoBook/master/TCGA/drug_response/pancancer.chemotherapy.response.txt",head=T,sep="\t")
phen$ID4<-paste(phen$bcr_patient_barcode,"-01",sep="")

miRNA<-miRNA[,colnames(miRNA) %in% phen$ID4]
phen<-phen[na.omit(unlist(lapply(colnames(miRNA),function(x) match(x,phen$ID)[1]))),]
dim(miRNA)
dim(phen)

head(sort(table(phen$bcr_patient_barcode)))
table(levels(phen$measure_of_response))
levels(phen$measure_of_response)<-c(0,1,1,0)

input<-data.frame(phen=phen$measure_of_response,t(miRNA))
input<-input[,unlist(apply(input,2,function(x) sd(x)>0))]
miRNA<-input
miRNA[1:5,1:5]                           
save(miRNA,file="pancancer.miRNA.drugResponse.RData")

set.seed(49)
cv.error <- NULL
k <- 10
rlt1<-c()
rlt2<-c()
for(i in 1:k){
  index <- sample(1:nrow(input),round(0.9*nrow(input)))
  train.cv <- input[index,]
  test.cv <- input[-index,]
  
  P=apply(train.cv[,2:ncol(train.cv)],2,function(x) summary(bayesglm(as.factor(train.cv[,1])~x,family=binomial))$coefficients[2,4])
  train.cv<-train.cv[,c(1,which(P<0.05/length(P))+1)]
  
  RF <- randomForest(as.factor(phen) ~ ., data=train.cv, importance=TRUE,proximity=T)
  imp<-RF$importance
  head(imp)
  imp<-imp[order(imp[,4],decreasing = T),]
  write.table(imp,file=paste("RandomForest.VIP.",i,".txt",sep=""),sep="\t",quote=F,row.names = T,col.names = NA)
  topvar<-match(rownames(imp)[1:30],colnames(input))
  
  train.cv <- input[index,c(1,topvar)]
  test.cv <- input[-index,c(1,topvar)]
  
  n <- colnames(train.cv)
  f <- as.formula(paste("phen ~", paste(n[!n %in% "phen"], collapse = " + ")))
  
  nn <- neuralnet(f,data=train.cv,hidden=c(10,3),act.fct = "logistic",linear.output = F)
  pr.nn <- neuralnet::compute(nn,test.cv)
  trainRlt<-data.frame(phen=train.cv[,1],pred=unlist(nn$net.result[[1]][,1]))
  testRlt<-data.frame(phen=test.cv[,1],pred=unlist(pr.nn$net.result[,1]))
  rownames(trainRlt)=row.names(train.cv)
  rownames(testRlt)=row.names(test.cv)
  rlt1<-rbind(rlt1,trainRlt)  
  rlt2<-rbind(rlt2,testRlt)
  print(i)
}
data1<-na.omit(data.frame(rlt1))
data2<-na.omit(data.frame(rlt2))
model.glm1 <- bayesglm(phen~.,data=rlt1,family=binomial(),na.action=na.omit)
model.glm2 <- bayesglm(phen~.,data=rlt2,family=binomial(),na.action=na.omit)
pred1 <- predRisk(model.glm1)
pred2 <- predRisk(model.glm2)
par(mfrow=c(2,2),cex.lab=1.5,cex.axis=1.5)
plotROC(data=data1,cOutcome=1,predrisk=cbind(pred1))
plotROC(data=data2,cOutcome=1,predrisk=cbind(pred2))
 
## heatmap
source("https://raw.githubusercontent.com/Shicheng-Guo/GscRbasement/master/HeatMap.R")
P=apply(input[,2:ncol(input)],2,function(x) summary(glm(as.factor(input[,1])~x,family=binomial))$coefficients[2,4])
input<-input[,c(1,match(names(P[head(order(P),n=200)]),colnames(input)))]
RF <- randomForest(as.factor(phen) ~ ., data=input, importance=TRUE,proximity=T)
imp<-RF$importance
head(imp)
imp<-imp[order(imp[,4],decreasing = T),]
topvar<-match(rownames(imp)[1:50],colnames(input))
        
miRNA2<-input[,c(1,topvar)] 
save(miRNA2,file="miRNA2.triple.RData")

newinput <- t(input[,topvar])
colnames(newinput)<-input[,1]
newinput[1:5,1:5]
source("https://raw.githubusercontent.com/Shicheng-Guo/GscRbasement/master/HeatMap.R")
pdf("meth.heatmap.randomForest.n2.pdf")
HeatMap(newinput)
dev.off()
        
source("https://raw.githubusercontent.com/Shicheng-Guo/GscRbasement/master/HeatMap.R")
newinput<-t(log(input[,match(rownames(imp)[1:50],colnames(input))]+1,2))
colnames(newinput)<-input[,1]
pdf("mRNA.heatmap.randomForest.pdf")
HeatMap(newinput)
dev.off()
save.image("miRNAseq-N2.RF.heatmap.RData")
