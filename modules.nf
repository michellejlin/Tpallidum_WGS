// Adapter trim with Trimmomatic
process trimReads { 
    container "quay.io/biocontainers/trimmomatic:0.35--6"

	// Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 1

    input:
        tuple val(base), file(Rr1), file(Rr2), file(Rr300_R1), file(Rr300_R2) // from input_read_ch
        file ADAPTERS
    output: 
        tuple val(base), file("${base}.R1.paired.fastq.gz"), file("${base}.R2.paired.fastq.gz"), file("${base}_300.R1.paired.fastq.gz"), file("${base}_300.R2.paired.fastq.gz"), file("${base}_300.R1.unpaired.fastq.gz") // into Trim_out_ch
    
    publishDir "${params.OUTDIR}trimmed_fastqs", mode: 'copy', pattern: '*.paired.fastq.gz'

    script:
    """
    #!/bin/bash

    ls -latr
    trimmomatic PE -threads ${task.cpus} ${Rr1} ${Rr2} ${base}.R1.paired.fastq.gz ${base}.R1.unpaired.fastq.gz ${base}.R2.paired.fastq.gz ${base}.R2.unpaired.fastq.gz \
    ILLUMINACLIP:${ADAPTERS}:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:20

    trimmomatic PE -threads ${task.cpus} ${Rr300_R1} ${Rr300_R2} ${base}_300.R1.paired.fastq.gz ${base}_300.R1.unpaired.fastq.gz ${base}_300.R2.paired.fastq.gz ${base}_300.R2.unpaired.fastq.gz \
    ILLUMINACLIP:${ADAPTERS}:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:20

    """
}

// Use bbduk to filter reads that match rRNA more stringently
process filterTp {
    container "staphb/bbtools:latest"

    // Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 2

    input:
        tuple val(base), file("${base}.R1.paired.fastq.gz"), file("${base}.R2.paired.fastq.gz"), file("${base}_300.R1.paired.fastq.gz"), file("${base}_300.R2.paired.fastq.gz"), file("${base}_300.R1.unpaired.fastq.gz") // from Trim_out_ch
        file REF_FASTAS
    output:
        tuple val(base),file("${base}_matched_rRNA_r1.fastq.gz"), file("${base}_matched_rRNA_r2.fastq.gz"),file("${base}_300_matched_rRNA_r1.fastq.gz"), file("${base}_300_matched_rRNA_r2.fastq.gz"), file("${base}_300_matched_unpaired_rRNA_r1.fastq.gz")// into Trimmed_filtered_reads_ch1
        tuple val(base),file("${base}_unmatched_rRNA_r1.fastq.gz"), file("${base}_unmatched_rRNA_r2.fastq.gz"),file("${base}_300_unmatched_rRNA_r1.fastq.gz"), file("${base}_300_unmatched_rRNA_r2.fastq.gz"), file("${base}_300_unmatched_unpaired_rRNA_r1.fastq.gz")// into Trimmed_unmatched_reads
    
    publishDir "${params.OUTDIR}rRNA_filtered_fastqs", mode: 'copy', pattern: '*matched_rRNA*.fastq.gz'

    script:
    """
    #!/bin/bash

    ls -latr
    echo "Filtering trimmed reads of ${base} against TPA rRNA reference..."
    /bbmap/bbduk.sh in1='${base}.R1.paired.fastq.gz' in2='${base}.R2.paired.fastq.gz' out1='${base}_unmatched_rRNA_r1.fastq.gz' out2='${base}_unmatched_rRNA_r2.fastq.gz' outm1='${base}_matched_rRNA_r1.fastq.gz' outm2='${base}_matched_rRNA_r2.fastq.gz' ref=${REF_FASTAS} k=31 hdist=1 mcf=0.98 rieb=f stats='${base}_stats_tp.txt' overwrite=TRUE t=16 -Xmx50g
    /bbmap/bbduk.sh in1='${base}_300.R1.paired.fastq.gz' in2='${base}_300.R2.paired.fastq.gz' out1='${base}_300_unmatched_rRNA_r1.fastq.gz' out2='${base}_300_unmatched_rRNA_r2.fastq.gz' outm1='${base}_300_matched_rRNA_r1.fastq.gz' outm2='${base}_300_matched_rRNA_r2.fastq.gz' ref=${REF_FASTAS} k=31 hdist=1 mcf=0.98 rieb=f stats='${base}_300_stats_tp.txt' overwrite=TRUE t=16 -Xmx50g
    /bbmap/bbduk.sh in='${base}_300.R1.unpaired.fastq.gz' out='${base}_300_unmatched_unpaired_rRNA_r1.fastq.gz' outm='${base}_300_matched_unpaired_rRNA_r1.fastq.gz' ref=${REF_FASTAS} k=31 hdist=1 mcf=0.98 rieb=f stats='${base}_300_unpaired_stats_tp.txt' overwrite=TRUE t=16 -Xmx50g

    """
}

// Take unmatched reads from rRNA filter and map to TPA genome less stringently
process mapUnmatchedReads {
    container "staphb/bbtools:latest"

    // Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 2

    input:
        tuple val(base),file("${base}_unmatched_rRNA_r1.fastq.gz"), file("${base}_unmatched_rRNA_r2.fastq.gz"),file("${base}_300_unmatched_rRNA_r1.fastq.gz"), file("${base}_300_unmatched_rRNA_r2.fastq.gz"), file("${base}_300_unmatched_unpaired_rRNA_r1.fastq.gz")// from Trimmed_unmatched_reads
        file REF_FASTAS_MASKED
    output:
        tuple val(base),file("${base}_matched_tpa_r1.fastq.gz"), file("${base}_matched_tpa_r2.fastq.gz"),file("${base}_300_matched_tpa_r1.fastq.gz"), file("${base}_300_matched_tpa_r2.fastq.gz"), file("${base}_300_matched_unpaired_tpa_r1.fastq.gz")// into TPA_matched_reads
        tuple val(base),file("${base}_matched_tpa_r1.fastq.gz"), file("${base}_matched_tpa_r2.fastq.gz"),file("${base}_300_matched_tpa_r1.fastq.gz"), file("${base}_300_matched_tpa_r2.fastq.gz"), file("${base}_300_matched_unpaired_tpa_r1.fastq.gz")// into TPA_matched_reads2

        // tuple val(base),file("${base}_unmatched_tpa_r1.fastq.gz"), file("${base}_unmatched_tpa_r2.fastq.gz")// into TPA_unmatched_reads
    
    publishDir "${params.OUTDIR}TPA_filtered_fastqs", mode: 'copy', pattern: '*_matched_tpa*.fastq.gz'

    script:
    """
    #!/bin/bash

    ls -latr
    /bbmap/bbduk.sh in1='${base}_unmatched_rRNA_r1.fastq.gz' in2='${base}_unmatched_rRNA_r2.fastq.gz' out1='${base}_unmatched_tpa_r1.fastq.gz' out2='${base}_unmatched2_tpa_r2.fastq.gz' outm1='${base}_matched_tpa_r1.fastq.gz' outm2='${base}_matched_tpa_r2.fastq.gz' ref=${REF_FASTAS_MASKED} k=31 hdist=2 stats='${base}_stats_tp.txt' overwrite=TRUE t=14 -Xmx105g
    /bbmap/bbduk.sh in1='${base}_300_unmatched_rRNA_r1.fastq.gz' in2='${base}_300_unmatched_rRNA_r2.fastq.gz' out1='${base}_300_unmatched_tpa_r1.fastq.gz' out2='${base}_300_unmatched2_tpa_r2.fastq.gz' outm1='${base}_300_matched_tpa_r1.fastq.gz' outm2='${base}_300_matched_tpa_r2.fastq.gz' ref=${REF_FASTAS_MASKED} k=31 hdist=2 stats='${base}_stats_tp.txt' overwrite=TRUE t=14 -Xmx105g
    /bbmap/bbduk.sh in='${base}_300_unmatched_unpaired_rRNA_r1.fastq.gz' out='${base}_300_unmatched_unpaired_tpa_r1.fastq.gz' outm='${base}_300_matched_unpaired_tpa_r1.fastq.gz' ref=${REF_FASTAS_MASKED} k=31 hdist=2 stats='${base}_stats_tp.txt' overwrite=TRUE t=14 -Xmx105g

    """
}

// Take matched reads and map to NC_021508 reference
process mapReads {
    container "quay.io/biocontainers/bowtie2:2.4.1--py37h8270d21_3"

    // Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 1

    input:
        tuple val(base),file("${base}_matched_tpa_r1.fastq.gz"), file("${base}_matched_tpa_r2.fastq.gz"),file("${base}_300_matched_tpa_r1.fastq.gz"), file("${base}_300_matched_tpa_r2.fastq.gz"), file("${base}_300_matched_unpaired_tpa_r1.fastq.gz")// from TPA_matched_reads
        tuple val(base),file("${base}_matched_rRNA_r1.fastq.gz"), file("${base}_matched_rRNA_r2.fastq.gz"),file("${base}_300_matched_rRNA_r1.fastq.gz"), file("${base}_300_matched_rRNA_r2.fastq.gz"), file("${base}_300_matched_unpaired_rRNA_r1.fastq.gz")// from Trimmed_filtered_reads_ch1
        //tuple val(base),file("${base}_matched_tpa_r1.fastq.gz"), file("${base}_matched_tpa_r2.fastq.gz")// from Trimmed_filtered_reads_ch1
        //tuple val(base),file("${base}_matched_rRNA_r1.fastq.gz"), file("${base}_matched_rRNA_r2.fastq.gz")// from TPA_matched_reads
        file(NC_021508)
        file(NC_021508_1)
        file(NC_021508_2)
        file(NC_021508_3)
        file(NC_021508_4)
        file(NC_021508_5)
        file(NC_021508_6)
    output:
        tuple val(base),file("${base}.sam")// into Aligned_sam_ch
        // output deduped fastqs instead
        // tuple val(base),file("${base}_matched_r1.fastq.gz"),file("${base}_matched_r2.fastq.gz") into Matched_cat_reads
        // tuple val(base),file("${base}_matched_r1.fastq.gz"),file("${base}_matched_r2.fastq.gz") into Matched_cat_reads_ch2

    script:
    """
    #!/bin/bash

    ls -latr
    echo "Concatenating TPA and rRNA reads for ${base}..."
    cat ${base}_matched_tpa_r1.fastq.gz ${base}_matched_rRNA_r1.fastq.gz > ${base}_matched_r1.fastq.gz
    cat ${base}_matched_tpa_r2.fastq.gz ${base}_matched_rRNA_r2.fastq.gz > ${base}_matched_r2.fastq.gz
    cat ${base}_300_matched_tpa_r1.fastq.gz ${base}_300_matched_rRNA_r1.fastq.gz > ${base}_300_matched_r1.fastq.gz
    cat ${base}_300_matched_tpa_r2.fastq.gz ${base}_300_matched_rRNA_r2.fastq.gz > ${base}_300_matched_r2.fastq.gz
    cat ${base}_300_matched_unpaired_tpa_r1.fastq.gz ${base}_300_matched_unpaired_rRNA_r1.fastq.gz > ${base}_300_matched_unpaired_r1.fastq.gz

    bowtie2 -x NC_021508 -1 '${base}_matched_r1.fastq.gz, ${base}_300_matched_r1.fastq.gz' -2 '${base}_matched_r2.fastq.gz, ${base}_300_matched_r2.fastq.gz' -U '${base}_300_matched_unpaired_r1.fastq.gz' -p ${task.cpus} > ${base}.sam
    """
}

// Convert sam to bam
process samToBam {
    container "quay.io/biocontainers/samtools:1.6--h9dace67_6"

    input:
        tuple val(base),file("${base}.sam")// from Aligned_sam_ch
    output:
        tuple val(base),file("${base}_firstmap.sorted.bam")// into Sorted_bam_ch
    
    script:
    """
    #!/bin/bash

    ls -latr
    /usr/local/bin/samtools view -bS ${base}.sam > ${base}.bam
    /usr/local/bin/samtools sort -o ${base}_firstmap.sorted.bam ${base}.bam
    """

}

// Use Picard to remove duplicates and convert bam back to fastq for downstream remapping
process removeDuplicates{
    container "quay.io/biocontainers/picard:2.23.3--0"

    input:
        tuple val(base),file("${base}_firstmap.sorted.bam")// from Sorted_bam_ch
    output:
        tuple val(base),file("${base}_firstmap_dedup.bam")// into Sorted_dedup_bam_ch
        tuple val(base),file("${base}_firstmap_dedup.bam")// into Sorted_dedup_bam_ch2
        tuple val(base),file("${base}_firstmap_dedup.bam")// into Sorted_dedup_bam_ch3
        tuple val(base),file("${base}_firstmap_dedup.bam")// into Sorted_dedup_bam_ch4
        
        tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// into Deduped_reads
        tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// into Deduped_reads_ch2
        tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// into Deduped_reads_ch3

    
    publishDir "${params.OUTDIR}deduped_bams", mode: 'copy', pattern: '*_firstmap_dedup.bam'
    publishDir ("${params.OUTDIR}deduped_fastqs", mode: 'copy', pattern: '*.fastq')

    script:
    """
    #!/bin/bash

    ls -latr
    /usr/local/bin/picard MarkDuplicates INPUT=${base}_firstmap.sorted.bam OUTPUT=${base}_firstmap_dedup.bam METRICS_FILE=${base}_metrics.txt REMOVE_DUPLICATES=true VALIDATION_STRINGENCY=SILENT
    /usr/local/bin/picard SamToFastq I=${base}_firstmap_dedup.bam FASTQ=${base}_deduped_r1.fastq SECOND_END_FASTQ=${base}_deduped_r2.fastq VALIDATION_STRINGENCY=SILENT
    """
}

// Call variants with Freebayes
process callVariants {
    container "quay.io/biocontainers/freebayes:1.3.2--py37h26878c9_2"

    input:
        tuple val(base),file("${base}_firstmap_dedup.bam")// from Sorted_dedup_bam_ch3
        file(NC_021508)
    output:
        file("${base}.vcf")// into Freebayes_vcf
    
    publishDir "${params.OUTDIR}vcfs", mode: 'copy', pattern: '*.vcf'
    
    script:
    """
    #!/bin/bash

    ls -latr
    /usr/local/bin/freebayes -f ${NC_021508} -p 1 ${base}_firstmap_dedup.bam -v ${base}.vcf
    """
}

// De novo assemble matched reads with Unicycler 
process deNovoAssembly {
    container "quay.io/biocontainers/unicycler:0.4.4--py37h13b99d1_3"

    // Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 1

    input:
//        tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq") from Deduped_reads
        tuple val(base),file("${base}_matched_tpa_r1.fastq.gz"), file("${base}_matched_tpa_r2.fastq.gz"),file("${base}_300_matched_tpa_r1.fastq.gz"), file("${base}_300_matched_tpa_r2.fastq.gz"), file("${base}_300_matched_unpaired_tpa_r1.fastq.gz")// from TPA_matched_reads2
    output:
        tuple val(base),file("${base}_assembly.gfa"),file("${base}_assembly.fasta")// into Unicycler_ch
        file("*")// into Unicycler_dump_ch

    publishDir "${params.OUTDIR}unicycler_output/${base}/", mode: 'copy', pattern: '*'
        
    script:
    """
    #!/bin/bash

    ls -latr
    
    cat ${base}_matched_tpa_r1.fastq.gz ${base}_300_matched_tpa_r1.fastq.gz > ${base}_cat_matched_tpa_r1.fastq.gz
    cat ${base}_matched_tpa_r2.fastq.gz ${base}_300_matched_tpa_r2.fastq.gz > ${base}_cat_matched_tpa_r2.fastq.gz
    #/usr/local/bin/unicycler --pe1-1 ${base}_matched_tpa_r1.fastq.gz --pe1-2 ${base}_matched_tpa_r2.fastq.gz --pe2-1 ${base}_300_matched_tpa_r1.fastq.gz --pe2-2 ${base}_300_matched_tpa_r2.fastq.gz --s2 ${base}_300_matched_tpa_r1.fastq.gz -o ./ -t ${task.cpus}
    #/usr/local/bin/unicycler -1 ${base}_matched_tpa_r1.fastq.gz,${base}_300_matched_tpa_r1.fastq.gz -2 ${base}_matched_tpa_r2.fastq.gz,${base}_300_matched_tpa_r2.fastq.gz -s ${base}_300_matched_tpa_r1.fastq.gz -o ./ -t ${task.cpus}
    /usr/local/bin/unicycler -1 ${base}_cat_matched_tpa_r1.fastq.gz -2 ${base}_cat_matched_tpa_r2.fastq.gz -s ${base}_300_matched_tpa_r1.fastq.gz -o ./ -t ${task.cpus}

    cp assembly.gfa ${base}_assembly.gfa
    cp assembly.fasta ${base}_assembly.fasta

    """
}

// Merges assembly and mapping to make consensus sequence
process mergeAssemblyMapping {
    container "quay.io/michellejlin/tpallidum_wgs:latest"

    // Retry on fail at most three times 
    errorStrategy 'retry'
    maxRetries 1

    input:
        tuple val(base),file("${base}_assembly.gfa"),file("${base}_assembly.fasta"),file("${base}_firstmap_dedup.bam")// from Unicycler_ch
        //tuple val(base),file("${base}_firstmap_dedup.bam")// from Sorted_dedup_bam_ch
        file(NC_021508)
        file(NC_021508_BWA1)
        file(NC_021508_BWA2)
        file(NC_021508_BWA3)
        file(NC_021508_BWA4)
        file(NC_021508_BWA5)
        file(TP_MAKE_SEQ)
    output:
        tuple val(base),file("${base}_consensus.fasta")// into Consensus_ch
        tuple val(base),file("${base}_consensus.fasta")// into Consensus_ch2
        tuple val(base),file("*.sorted.bam")// into Scaffold_bams_ch
        tuple val(base),file("*assembly*")// into Assembly_ch

    publishDir "${params.OUTDIR}merged_assembly_mapping_consensus", mode: 'copy', pattern: '*_consensus.fasta'
    publishDir "${params.OUTDIR}scaffold_bams", mode: 'copy', pattern: '*.sorted.bam'

    script:
    """
    #!/bin/bash
    echo ${base}
    ls -latr

    cp ${base}_assembly.gfa assembly.gfa
    cp ${base}_assembly.fasta assembly.fasta

    Rscript --vanilla ${TP_MAKE_SEQ} \'${base}\' \'NC_021508\'
    """
}

process remapReads {
    container "quay.io/michellejlin/tpallidum_wgs"

    input:
        tuple val(base),file("${base}_consensus.fasta"),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// from Consensus_ch
        //tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// from Deduped_reads_ch2
    output:
        tuple val(base),file("${base}_remapped.sorted.bam")// into Remapped_bam_ch
        tuple val(base),file("${base}_remapped.sorted.bam"),file("${base}_remapped.sorted.bam.bai"),file("${base}_consensus.fasta")// into Pilon_ch
        tuple val(base),file("*")// into Remap_reads_all_ch

    publishDir "${params.OUTDIR}remapped_bams", mode: 'copy', pattern: '*_remapped.sorted.bam'
    publishDir "${params.OUTDIR}remapped_bams/${base}/", mode: 'copy', pattern: '*'


    script:
    """
    ls -latr

    /usr/local/miniconda/bin/bowtie2-build -q ${base}_consensus.fasta ${base}_aligned_scaffolds_NC_021508
    /usr/local/miniconda/bin/bowtie2 -x ${base}_aligned_scaffolds_NC_021508 -1 ${base}_deduped_r1.fastq -2 ${base}_deduped_r2.fastq -p ${task.cpus} | /usr/src/samtools-1.9/samtools view -bS - > ${base}_remapped.bam 
    /usr/src/samtools-1.9/samtools sort -o ${base}_remapped.sorted.bam ${base}_remapped.bam

    /usr/src/samtools-1.9/samtools index -b ${base}_remapped.sorted.bam ${base}_remapped.sorted.bam.bai
    """
}

process pilonPolishing {
    container "staphb/pilon"

    input: 
        tuple val(base),file("${base}_remapped.sorted.bam"),file("${base}_remapped.sorted.bam.bai"),file("${base}_consensus.fasta")// from Pilon_ch
    output:
        tuple val(base),file("${base}_pilon.fasta")// into Pilon_fasta_ch
        tuple val(base),file("${base}_pilon.fasta")// into Pilon_fasta_ch2
    
    publishDir "${params.OUTDIR}pilon", mode: 'copy', pattern: '*'

    script:
    """
    ls -latr

    /pilon/pilon --genome ${base}_consensus.fasta --frags ${base}_remapped.sorted.bam --output ${base}_pilon --vcf --changes
    """
}

process remapPilon {
    container "quay.io/michellejlin/tpallidum_wgs"

    input:
        tuple val(base),file("${base}_pilon.fasta"),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// from Pilon_fasta_ch
        //tuple val(base),file("${base}_deduped_r1.fastq"),file("${base}_deduped_r2.fastq")// from Deduped_reads_ch3
    output:
        tuple val(base),file("${base}_pilon_remapped.sorted.bam")// into Pilon_bam_ch
        tuple val(base),file("*")// into Remap_pilon_all_ch

    publishDir "${params.OUTDIR}remapped_pilon_bams", mode: 'copy', pattern: '*pilon_remapped.sorted.bam'
    publishDir "${params.OUTDIR}remapped_pilon_bams/${base}", mode: 'copy', pattern: '*'
    

    script:
    """
    ls -latr

    /usr/local/miniconda/bin/bowtie2-build -q ${base}_pilon.fasta ${base}_pilon_aligned_scaffolds_NC_021508
    /usr/local/miniconda/bin/bowtie2 -x ${base}_pilon_aligned_scaffolds_NC_021508 -1 ${base}_deduped_r1.fastq -2 ${base}_deduped_r2.fastq -p ${task.cpus} | /usr/src/samtools-1.9/samtools view -bS - > ${base}_pilon_remapped.bam 
    /usr/src/samtools-1.9/samtools sort -o ${base}_pilon_remapped.sorted.bam ${base}_pilon_remapped.bam

    /usr/src/samtools-1.9/samtools index -b ${base}_pilon_remapped.sorted.bam ${base}_pilon_remapped.sorted.bam.bai
    """
}


process generateConsensus {
    container "quay.io/michellejlin/tpallidum_wgs"

    input:
        tuple val(base),file("${base}_remapped.sorted.bam"),file("${base}_consensus.fasta"),file("${base}_firstmap_dedup.bam")// from Remapped_bam_ch
        //tuple val(base),file("${base}_consensus.fasta")// from Consensus_ch2
        //tuple val(base),file("${base}_firstmap_dedup.bam")// from Sorted_dedup_bam_ch2
        file(TP_GENERATE_CONSENSUS)
    output:
        tuple val(base),file("${base}_finalconsensus.fasta"),file("${base}_mappingstats.csv")// into Prokka_consensus_ch

    publishDir "${params.OUTDIR}finalconsensus", mode: 'copy', pattern: '*_finalconsensus.fasta'

    script:
    """
    ls -latr

    Rscript --vanilla ${TP_GENERATE_CONSENSUS} \'${base}' \'NC_021508\'
    """

}

process generatePilonConsensus {
    container "quay.io/michellejlin/tpallidum_wgs"

    input:
        tuple val(base),file("${base}_pilon_remapped.sorted.bam"),file("${base}_pilon.fasta"),file("${base}_firstmap_dedup.bam")// from Pilon_bam_ch
        //tuple val(base),file("${base}_pilon.fasta")// from Pilon_fasta_ch2
        //tuple val(base),file("${base}_firstmap_dedup.bam")// from Sorted_dedup_bam_ch4
        file(TP_GENERATE_CONSENSUS)
    output:
        tuple val(base),file("${base}_pilon_finalconsensus.fasta"),file("${base}_pilon_mappingstats.csv")// into Prokka_pilon_consensus_ch

    publishDir "${params.OUTDIR}finalconsensus", mode: 'copy', pattern: '*_finalconsensus.fasta'

    script:
    """
    cp ${base}_firstmap_dedup.bam ${base}_pilon_firstmap_dedup.bam

    ls -latr    
    Rscript --vanilla ${TP_GENERATE_CONSENSUS} \'${base}_pilon' \'NC_021508\'
    """
}

// Annotate final consensus with prokka
process annotateConsensus {
    container "quay.io/biocontainers/prokka:1.14.6--pl526_0"

    input:
    tuple val(base),file("${base}_finalconsensus.fasta"),file("${base}_mappingstats.csv")// from Prokka_consensus_ch
    file(REF_GB)

    output:
        file("*")// into Annotated_ch

    publishDir "${params.OUTDIR}finalconsensus_prokka_annotations", mode: 'copy', pattern: '*'

    script:
    """
    ls -latr
 
    #prokka --outdir ./ --force --kingdom 'Bacteria' --genus 'Treponema' --usegenus --prefix ${base} ${base}_finalconsensus.fasta
    prokka --proteins ${REF_GB} --outdir ./ --force --prefix ${base} ${base}_finalconsensus.fasta

    """
}

// Annotate final consensus with prokka
process annotatePilonConsensus {
    container "quay.io/biocontainers/prokka:1.14.6--pl526_0"

    input:
    tuple val(base),file("${base}_pilon_finalconsensus.fasta"),file("${base}_pilon_mappingstats.csv")// from Prokka_pilon_consensus_ch
    file(REF_GB)

    output:
        file("*")//// into Annotated_pilon_ch

    publishDir "${params.OUTDIR}finalconsensus_pilon_prokka_annotations", mode: 'copy', pattern: '*'

    script:
    """
    ls -latr
 
    prokka --proteins ${REF_GB} --outdir ./ --force --prefix ${base} ${base}_pilon_finalconsensus.fasta

    """
}