#!/bin/bash
#Pipeline for whole genome sequence assembly and annotation for T pallidum 
#Feb 2020
#Pavitra Roychoudhury

#### Load required modules ####
#do this before submitting the sbatch command
# cd /fh/fast/jerome_k/Tpallidum
# SLURM_CPUS_PER_TASK=14
# module load BBMap/38.44-foss-2016b
# module load FastQC/0.11.8-Java-1.8
# module load BWA/0.7.17-foss-2016b
# module load bowtie2/2.2.5
# module load SAMtools/1.8-foss-2016b 
# module load R/3.6.1-foss-2016b-fh1
# module load prokka/1.13-foss-2016b-BioPerl-1.7.0
# module load parallel/20170222-foss-2016b
# module load BLAST+/2.7.1-foss-2016b
# wget https://github.com/tseemann/prokka/raw/master/binaries/linux/tbl2asn -O $HOME/.local/bin/tbl2asn

#### One time: First build reference for bowtie and make a copy of the ref seqs ####
# module load bowtie2/2.2.5
# module load BWA/0.7.17-foss-2016b
# bowtie2-build './refs/Tp_refs.fasta' ./refs/Tp_refs
# bowtie2-build './refs/NC_021508.fasta' ./refs/NC_021508
# bwa index ./refs/NC_021508.fasta
# prokka-genbank_to_fasta_db ./refs/NC_021508.gb ./refs/NC_018722.gb ./refs/NC_021508.gb > ./refs/Tp_proteins.faa


#### Usage ####
#For paired-end library
#		hsv1_pipeline.sh -1 yourreads_r1.fastq.gz -2 yourreads_r2.fastq.gz
#For single-end library
#		hsv1_pipeline.sh -s yourreads.fastq.gz
#This is meant to be run on the cluster (typically through sbatch) so if run locally,
#first set the environment variable manually, e.g.
#		SLURM_CPUS_PER_TASK=8
#or whatever is the number of available processors 
 
#Load required tools
#Note that spades and last are all locally installed and need to be updated manually as required


#Test run
# in_fastq_r1='/fh/fast/jerome_k/SR/ngs/illumina/proychou/190222_D00300_0682_BHTMLLBCX2/Unaligned/Project_jboonyar/Sample_GH100084/GH100084_GGAGATTC-GTTCAGAC_L002_R1_001.fastq.gz'
# in_fastq_r2='/fh/fast/jerome_k/SR/ngs/illumina/proychou/190222_D00300_0682_BHTMLLBCX2/Unaligned/Project_jboonyar/Sample_GH100084/GH100084_GGAGATTC-GTTCAGAC_L002_R2_001.fastq.gz'
# SLURM_CPUS_PER_TASK=8


PATH=$PATH:$HOME/.local/bin:$HOME/SPAdes-3.14.0-Linux/bin:
export PATH=$PATH:$EBROOTPROKKA/bin:$EBROOTPROKKA/db:
echo "Number of cores used: "$SLURM_CPUS_PER_TASK
# echo "Path: "$PATH

while getopts ":1:2:s:f" opt; do
	case $opt in
		1) in_fastq_r1="$OPTARG"
			paired="true"
		;;
		2) in_fastq_r2="$OPTARG"
			paired="true"
		;;
		s) in_fastq="$OPTARG"
			paired="false"
		;;
		f) filter="true"
		;;
		\?) echo "Invalid option -$OPTARG" >&2
    	;;
	esac
done

printf "Input arguments:\n\n"
echo $@


##  PAIRED-END  ##
if [[ $paired == "true" ]]
then
if [ -z $in_fastq_r1 ] || [ -z $in_fastq_r2 ]
then
echo "Missing input argument."
fi

sampname=$(basename ${in_fastq_r1%%_R1*.fastq*})

#FastQC report on raw reads
printf "\n\nFastQC report on raw reads ... \n\n\n"
mkdir -p ./fastqc_reports_raw
fastqc $in_fastq_r1 $in_fastq_r2 -o ./fastqc_reports_raw -t $SLURM_CPUS_PER_TASK  

#Adapter trimming with bbduk
printf "\n\nAdapter trimming ... \n\n\n"
mkdir -p ./preprocessed_fastq
bbduk.sh in1=$in_fastq_r1 in2=$in_fastq_r2  out1='./preprocessed_fastq/'$sampname'_trimmed_r1_tmp.fastq.gz' out2='./preprocessed_fastq/'$sampname'_trimmed_r2_tmp.fastq.gz' ref=adapters,artifacts k=21 ktrim=r mink=4 hdist=2 overwrite=TRUE t=$SLURM_CPUS_PER_TASK 
bbduk.sh in1='./preprocessed_fastq/'$sampname'_trimmed_r1_tmp.fastq.gz' in2='./preprocessed_fastq/'$sampname'_trimmed_r2_tmp.fastq.gz'  out1='./preprocessed_fastq/'$sampname'_trimmed_r1.fastq.gz' out2='./preprocessed_fastq/'$sampname'_trimmed_r2.fastq.gz' ref=adapters,artifacts k=21 ktrim=l mink=4 hdist=2 overwrite=TRUE t=$SLURM_CPUS_PER_TASK 
rm './preprocessed_fastq/'$sampname'_trimmed_r1_tmp.fastq.gz' './preprocessed_fastq/'$sampname'_trimmed_r2_tmp.fastq.gz'

#Quality trimming
printf "\n\nQuality trimming ... \n\n\n"
mkdir -p ./preprocessed_fastq
bbduk.sh in1='./preprocessed_fastq/'$sampname'_trimmed_r1.fastq.gz' in2='./preprocessed_fastq/'$sampname'_trimmed_r2.fastq.gz' out1='./preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' out2='./preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' t=$SLURM_CPUS_PER_TASK qtrim=rl trimq=20 maq=10 overwrite=TRUE minlen=20

#Delete the trimmed fastqs
rm './preprocessed_fastq/'$sampname'_trimmed_r1.fastq.gz' './preprocessed_fastq/'$sampname'_trimmed_r2.fastq.gz' 


#Use bbduk to filter reads that match Tp genomes
if [[ $filter == "true" ]]
then
printf "\n\nK-mer filtering using Tp_refs.fasta ... \n\n\n"

bbduk.sh in1='./preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' in2='./preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' out1='./preprocessed_fastq/'$sampname'_unmatched_r1.fastq.gz' out2='./preprocessed_fastq/'$sampname'_unmatched_r2.fastq.gz' outm1='./preprocessed_fastq/'$sampname'_matched_r1.fastq.gz' outm2='./preprocessed_fastq/'$sampname'_matched_r2.fastq.gz' ref='./refs/Tp_refs.fasta' k=31 hdist=2 stats='./preprocessed_fastq/'$sampname'_stats_tp.txt' overwrite=TRUE t=$SLURM_CPUS_PER_TASK

rm './preprocessed_fastq/'$sampname'_unmatched_r1.fastq.gz' './preprocessed_fastq/'$sampname'_unmatched_r2.fastq.gz'

#rename and keep original prior to filtering if needed later
mv './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' 
'./preprocessed_fastq/'$sampname'_preprocessed_paired_before_filter_r1.fastq.gz'
mv './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' 
'./preprocessed_fastq/'$sampname'_preprocessed_paired_before_filter_r2.fastq.gz'
mv './preprocessed_fastq/'$sampname'_matched_r1.fastq.gz' './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz'
mv './preprocessed_fastq/'$sampname'_matched_r2.fastq.gz' './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz'
fi


#FastQC report on processed reads
mkdir -p ./fastqc_reports_preprocessed
printf "\n\nFastQC report on preprocessed reads ... \n\n\n"
fastqc './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' -o ./fastqc_reports_preprocessed -t $SLURM_CPUS_PER_TASK 


#Map reads to reference
printf "\n\nMapping reads to reference ... \n\n\n"
mkdir -p ./mapped_reads
bowtie2 -x ./refs/NC_021508 -1 './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' -2 './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' -p ${SLURM_CPUS_PER_TASK} | samtools view -bS - > './mapped_reads/'$sampname'.bam'
samtools sort -o './mapped_reads/'$sampname'.sorted.bam' './mapped_reads/'$sampname'.bam' 
rm './mapped_reads/'$sampname'.bam' 

#Assemble with SPAdes 
printf "\n\nStarting de novo assembly ... \n\n\n"
mkdir -p './contigs/'$sampname
# spades.py -1 './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' -2 './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' -o './contigs/'$sampname --careful -t ${SLURM_CPUS_PER_TASK}

~/Unicycler/unicycler-runner.py -1 './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' -2 './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' -o ./contigs/$sampname/ -t ${SLURM_CPUS_PER_TASK} --pilon_path ~/pilon-1.23.jar



##  SINGLE-END  ##
else 
if [[ $paired == "false" ]]
then

sampname=$(basename ${in_fastq%%_R1*.fastq*})

if [ -z $in_fastq ]
then
echo "Missing input argument."
fi

#FastQC report on raw reads
printf "\n\nFastQC report on raw reads ... \n\n\n"
mkdir -p ./fastqc_reports_raw
fastqc -o ./fastqc_reports_raw -t $SLURM_CPUS_PER_TASK $in_fastq 

#Adapter trimming with bbduk
printf "\n\nAdapter trimming ... \n\n\n"
mkdir -p ./preprocessed_fastq
tmp_fastq='./preprocessed_fastq/'$sampname'_trimmed_tmp.fastq.gz'
processed_fastq='./preprocessed_fastq/'$sampname'_trimmed.fastq.gz'

bbduk.sh in=$in_fastq out=$tmp_fastq ref=adapters,artifacts k=21 ktrim=r mink=4 hdist=2 overwrite=TRUE t=$SLURM_CPUS_PER_TASK 
bbduk.sh in=$tmp_fastq out=$processed_fastq ref=adapters,artifacts k=21 ktrim=l mink=4 hdist=2 overwrite=TRUE t=$SLURM_CPUS_PER_TASK 
rm $tmp_fastq

  
#Quality trimming
printf "\n\nQuality trimming ... \n\n\n"
mkdir -p ./preprocessed_fastq
processed_fastq_old=$processed_fastq
processed_fastq='./preprocessed_fastq/'$sampname'_preprocessed.fastq.gz'

bbduk.sh in=$processed_fastq_old out=$processed_fastq t=$SLURM_CPUS_PER_TASK qtrim=rl trimq=20 maq=10 overwrite=TRUE minlen=20


#Use bbduk to filter reads that match Tp genomes ## not tested for single-end!
if [[ $filter == "true" ]]
then
printf "\n\nK-mer filtering using Tp_refs.fasta ... \n\n\n"
processed_fastq_old=$processed_fastq
processed_fastq='./preprocessed_fastq/'$sampname'_matched.fastq.gz'
unmatched_fastq='./filtered_fastq/'$sampname'_unmatched.fastq.gz' 
filter_stats='./preprocessed_fastq/'$sampname'_stats_filtering.txt'
bbduk.sh in=$processed_fastq_old out=$unmatched_fastq outm=$processed_fastq ref='./refs/Tp_refs.fasta' k=31 hdist=2 stats=$filter_stats overwrite=TRUE t=$SLURM_CPUS_PER_TASK
mv $processed_fastq_old 
'./preprocessed_fastq/'$sampname'_preprocessed_before_filter.fastq.gz'
mv $processed_fastq './preprocessed_fastq/'$sampname'_preprocessed.fastq.gz'

else 
processed_fastq='./preprocessed_fastq/'$sampname'_preprocessed.fastq.gz'
fi



#FastQC report on processed reads
printf "\n\nFastQC report on preprocessed reads ... \n\n\n"
mkdir -p ./fastqc_reports_preprocessed
fastqc -o ./fastqc_reports_preprocessed -t $SLURM_CPUS_PER_TASK './preprocessed_fastq/'$sampname'_preprocessed.fastq.gz'


#Map reads to reference
printf "\n\nMapping reads to reference ... \n\n\n"
mkdir -p ./mapped_reads
mappedtoref_bam='./mapped_reads/'$sampname'.bam'
bowtie2 -x ./refs/NC_021508 -U './preprocessed_fastq/'$sampname'_preprocessed.fastq.gz' -p ${SLURM_CPUS_PER_TASK} | samtools view -bS - > $mappedtoref_bam
samtools sort -@ ${SLURM_CPUS_PER_TASK} -o './mapped_reads/'$sampname'.sorted.bam' $mappedtoref_bam 
rm $mappedtoref_bam 
mv './mapped_reads/'$sampname'.sorted.bam' $mappedtoref_bam 



#Assemble with SPAdes
printf "\n\nStarting de novo assembly ... \n\n\n"
mkdir -p './contigs/'$sampname
spades.py -s $processed_fastq -o './contigs/'$sampname --careful -t ${SLURM_CPUS_PER_TASK}


~/Unicycler/unicycler-runner.py -s './preprocessed_fastq/'$sampname'_preprocessed.fastq.gz' -o ./contigs/$sampname/ -t ${SLURM_CPUS_PER_TASK} --pilon_path ~/pilon-1.23.jar



fi
fi


# Now call an R script that merges assembly and mapping and ultimately makes the consensus sequence 
Rscript --vanilla tp_make_seq.R sampname=\"$sampname\" ref=\"NC_021508\"


#Remap reads to "new" reference
printf "\n\nRe-mapping reads to assembled sequence ... \n\n\n"
mkdir -p ./remapped_reads
ref='NC_021508'
bowtie2-build -q './ref_for_remapping/'$sampname'_aligned_scaffolds_'$ref'_consensus.fasta' './ref_for_remapping/'$sampname'_aligned_scaffolds_'$ref

if [[ $paired == "true" ]]
then
bowtie2 -x './ref_for_remapping/'$sampname'_aligned_scaffolds_'$ref -1 './preprocessed_fastq/'$sampname'_preprocessed_paired_r1.fastq.gz' -2 './preprocessed_fastq/'$sampname'_preprocessed_paired_r2.fastq.gz' -p ${SLURM_CPUS_PER_TASK} | samtools view -bS - > './remapped_reads/'$sampname'.bam'
samtools sort -o './remapped_reads/'$sampname'.sorted.bam' './remapped_reads/'$sampname'.bam'
fi

if [[ $paired == "false" ]]
then
bowtie2 -x './ref_for_remapping/'$sampname'_aligned_scaffolds_'$ref -U './preprocessed_fastq/'$sampname'_preprocessed.fastq.gz' -p ${SLURM_CPUS_PER_TASK} | samtools view -bS - > './remapped_reads/'$sampname'.bam'
samtools sort -o './remapped_reads/'$sampname'.sorted.bam' './remapped_reads/'$sampname'.bam'
fi


rm './remapped_reads/'$sampname'.bam'
mv './remapped_reads/'$sampname'.sorted.bam' './remapped_reads/'$sampname'.bam' 


#Call R script to generate a consensus sequence
printf "\n\nGenerating consensus sequence ... \n\n\n"
mkdir -p ./consensus_seqs_all
mkdir -p ./stats
Rscript --vanilla tp_generate_consensus.R sampname=\"$sampname\" ref=\"NC_021508\"


#Annotate
printf "\n\nAnnotating with prokka ... \n\n\n"
mkdir -p ./annotations_prokka
prokka --outdir './annotations_prokka/'$sampname'/' --force --kingdom 'Bacteria' --genus 'Treponema' --usegenus --prefix $sampname './annotations_prokka/'$sampname/*.fa


#Clean up some files
rm './ref_for_remapping/'$sampname*'.fai'
rm './ref_for_remapping/'$sampname*'.bt2'
