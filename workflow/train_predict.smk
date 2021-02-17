# The data processing and analysis steps to train the PREPRINT classifier and
# to predict the genome-wide enhancers.
# ---------------------------------------------------------------------------

# The default rule that will do 5-fold crossvalidation on the K562 cell line
cv_files = (
	f'{data_dir}/results/model_promoters_and_random_combined/{{{{cell_line}}}}/{{{{distance_measure}}}}'
	f'/{config["create_training_data_combined"]["k"]}-fold_CV_{{i}}'
	f'/NSamples_{config["extract_enhancers"]["N"]}_window_{config["window"]}_bin_{config["binSize"]}_{config["create_training_data_combined"]["k"]}fold_cv_{{i}}'
)
rule train_predict:
	input:
		expand(expand(f'{cv_files}_predicted_data.txt', i=[1, 2, 3, 4, 5]), distance_measure=['ML', 'Bayes_estimated_priors'], cell_line='K562')

# First, define transcription start sites (TSS) of protein coding genes 
rule define_TSS:
	input:
		f'{code_dir}/define_TSS.R',
		f'{gencode_dir}/gencode.v27lift37.annotation.gtf.gz',
	output:
		f'{gencode_dir}/GENCODE.RData',
		f'{gencode_dir}/GR_Gencode_protein_coding_TSS.RDS',
		f'{gencode_dir}/GR_Gencode_protein_coding_TSS_positive.RDS',
		f'{gencode_dir}/GR_Gencode_TSS.RDS',
		f'{gencode_dir}/GR_Gencode_TSS_positive.RDS'
	shell:
		'Rscript {code_dir}/define_TSS.R --pathToDir={data_dir}'

# Rules for downloading various files
rule download_gencode:
	input:
	output: f'{gencode_dir}/gencode.v27lift37.annotation.gtf.gz'
	shell: 'wget ftp://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_27/GRCh37_mapping/gencode.v27lift37.annotation.gtf.gz -O {output}'

rule download_blacklists:
	input:
	output: f'{blacklists_dir}/{{file}}'
	shell: 'wget http://hgdownload.cse.ucsc.edu/goldenpath/hg19/encodeDCC/wgEncodeMapability/{wildcards.file} -O {output}'

# Definition and extraction of the training and test data enhancers
# 
# The size of ChIP-seq coverage profile window centered at enhancers and
# resolution of the enhancer pattern can be defined. Also the number of enhancers
# can vary. Enhancers whose distance to promoters is less than 2000 are removed.
# This is time and memory consuming step, can be done in less than 4 hours using
# 17 cpus and 3G mem per cpu. Example whown for the K562 cell line data. The data
# is not normalized wrt. data from any other cell line ( normalizeBool=FALSE).
def all_bam_files(wildcards):
	return [
		f'{data_dir}/{wildcards.cell_line}/bam_shifted/{data_type}.bam'
		for data_type in all_data_types(wildcards.cell_line)
	]

rule extract_enhancers:
	input:
		code=f'{code_dir}/extract_enhancers.R',
		bam_files=all_bam_files,
		p300=f'{data_dir}/{{cell_line}}/raw_data/wgEncodeAwgTfbsSydhK562P300IggrabUniPk.narrowPeak.gz',
		DNase=f'{data_dir}/{{cell_line}}/raw_data/wgEncodeOpenChromDnaseK562PkV2.narrowPeak.gz',
		blacklist_Dac=f'{blacklists_dir}/wgEncodeDacMapabilityConsensusExcludable.bed.gz',
		blacklist_Duke=f'{blacklists_dir}/wgEncodeDukeMapabilityRegionsExcludable.bed.gz',
		protein_coding_positive=f'{gencode_dir}/GR_Gencode_protein_coding_TSS_positive.RDS',
	output:
		f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData'
	shell:
		r'''
		Rscript {code_dir}/extract_enhancers.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_enhancers][N]} \
			--distToPromoter={config[extract_enhancers][distToPromotor]} \
			--pathToDir={data_dir} \
			--cellLine={wildcards.cell_line} \
			--p300File={input.p300} \
			--DNaseFile={input.DNase} \
			--normalize=FALSE \
			--NormCellLine=""
		'''

# Definition and extraction of training and test data promoters
rule extract_promoters:
	input:
		code=f'{code_dir}/extract_promoters.R',
		bam_files=all_bam_files,
		DNase=f'{data_dir}/{{cell_line}}/raw_data/wgEncodeOpenChromDnaseK562PkV2.narrowPeak.gz',
		blacklist_Dac=f'{blacklists_dir}/wgEncodeDacMapabilityConsensusExcludable.bed.gz',
		blacklist_Duke=f'{blacklists_dir}/wgEncodeDukeMapabilityRegionsExcludable.bed.gz',
		protein_coding=f'{gencode_dir}/GR_Gencode_protein_coding_TSS.RDS',
		protein_coding_positive=f'{gencode_dir}/GR_Gencode_protein_coding_TSS_positive.RDS',
	output:
		f'{data_dir}/{{cell_line}}/data_R/{config["extract_promoters"]["N"]}_promoters_bin_{config["binSize"]}_window_{config["window"]}.RData',
	shell:
		r'''
		Rscript {code_dir}/extract_promoters.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_promoters][N]} \
			--tssdist={config[extract_promoters][between_TSS_distance]} \
			--pathToDir={data_dir} \
			--cellLine={wildcards.cell_line} \
			--DNaseFile={input.DNase} \
			--normalize=FALSE \
			--NormCellLine=""
		'''

# Process whole-genome data
#
# Generate the data for the whole genome using bin size 100 (resolution). The
# files generated by this step are needed to generate the random genomic
# locations.
chroms=["chr1", "chr2", "chr3", "chr4", "chr5", "chr6", "chr7", "chr8", "chr9",
		"chr10", "chr11", "chr12", "chr13", "chr14", "chr15", "chr16", "chr17",
		"chr18", "chr19", "chr20", "chr21", "chr22", "chrX"]
rule create_intervals_whole_genome:
	input: f'{code_dir}/create_intervals_whole_genome.R'
	output: expand(f'{intervals_dir}/{{chrom}}.bed', chrom=chroms)
	shell: 'Rscript {code_dir}/create_intervals_whole_genome.R --binSize={config[binSize]} --output={intervals_dir}'


rule bedtools_multicov:
	input:
		bam_file=f'{data_dir}/{{cell_line}}/bam_shifted/{{mod}}.bam',
		bai_file=f'{data_dir}/{{cell_line}}/bam_shifted/{{mod}}.bam.bai',
		intervals=f'{intervals_dir}/{{chrom}}.bed',
	output:
		f'{data_dir}/{{cell_line}}/intervals_data_{config["binSize"]}/{{mod}}/{{chrom}}.bed'
	shell:
		r'''
		bedtools multicov \
			-bams {input.bam_file} \
			-bed {input.intervals} \
		| sort -k 1,1 -k2,2 -n \
		| cut -f 1-3,7 \
		> {output}
		'''

# Combine all data for each chromosome, do this for all chromosomes
union_bedgraph_names = ' '.join(all_data_types('K562'))
def all_bed_files(wildcards):
	return [
		f'{data_dir}/{wildcards.cell_line}/intervals_data_{config["binSize"]}/{data_type}/{wildcards.crom}.bed'
		for data_type in all_data_types(wildcards.cell_line)
	]
rule union_bedgraph:
	input:
		code=f'{code_dir}/union_bedgraph.sh',
		bed_files=all_bed_files,
	output:
		f'{data_dir}/{{cell_line}}/intervals_data_{config["binSize"]}/all_{{chrom}}.bedGraph'
	shell:
		'bedtools unionbedg -header -i {input.bed_files} -names {union_bedgraph_names} > {output}'

rule extract_nonzero_bins:
	input:
		f'{data_dir}/{{cell_line}}/intervals_data_{config["binSize"]}/all_{{chrom}}.bedGraph'
	output:
		f'{data_dir}/{{cell_line}}/intervals_data_{config["binSize"]}/nozero_regions_only_{{chrom}}.bed'
	shell:
		'bash {code_dir}/extract_nonzero_bins.sh {wildcards.chrom} {cell_line} {config[binSize]} {intervals_dir}'

# Process the whole genome data into an R object and normalize the data. Quite
# fast (30min) but requires a lot of memory. The following steps require 4
# hours and 30 G of memory.
rule whole_genome_data:
	input:
		f'{code_dir}/whole_genome_data.R',
		f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData',
		expand(f'{data_dir}/{{{{cell_line}}}}/intervals_data_{config["binSize"]}/all_{{chrom}}.bedGraph', chrom=chroms),
	output:
		f'{data_dir}/{{cell_line}}/data_R/whole_genome_coverage.RData'
	shell:
		r'''
		Rscript {code_dir}/whole_genome_data.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_enhancers][N]} \
			--pathToDir={data_dir} \
			--cellLine={wildcards.cell_line} \
			--normalize=FALSE \
			--normCellLine=""
		'''

# Training data random region definition: Pure random regions
#
# This step has similar time and memory requirements as extracting the training
# or test data enhancers and promoters. p300 sites, TSS and ENCODE blacklists
# are removed from the random regions.
rule extract_random_pure:
	input:
		code=f'{code_dir}/extract_random_pure.R',
		p300=f'{data_dir}/{{cell_line}}/raw_data/wgEncodeAwgTfbsSydhK562P300IggrabUniPk.narrowPeak.gz',
		enhancers=f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData',
		protein_coding=f'{gencode_dir}/GR_Gencode_protein_coding_TSS.RDS',
		protein_coding_positive=f'{gencode_dir}/GR_Gencode_protein_coding_TSS_positive.RDS',
		bam_files=expand(f'{data_dir}/{{{{cell_line}}}}/bam_shifted/{{data_type}}.bam', data_type=all_data_types),
	output:
		f'{data_dir}/{{cell_line}}/data_R/pure_random_{config["extract_random_pure"]["N"]}_bin_{config["binSize"]}_window_{config["window"]}.RData',
	shell:
		r'''
		Rscript {code_dir}/extract_random_pure.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_random_pure][N]} \
			--pathToDir={data_dir} \
			--p300File={input.p300} \
			--cellLine={wildcards.cell_line} \
			--normalize=FALSE
		'''

# Random region definition: Random regions with signal
# 
# 1. Remove MNase-seq from the data table, convert negative values to positive
# 2. Compute the sum of signals over different chromatin features
# 3. Define 100 bp bins whose sum is greater than threshold, for example, 5
# 4. Remove bins overlapping ENCODE blacklists, bins having distance 5000/2 to any p300 peaks, bins having distance 2 kb or less to any protein coding TSS
# 5. Reduce the subsequent bins to larger regions
# 6. Select regions with width equal or larger than 2000 bp, this is 4 % of the whole genome
# 7. Compute probability for each region, and sample N regions
# 8. Select a random location within the sampled regions
rule define_random_with_signal:
	input:
		code=f'{code_dir}/define_random_with_signal.R',
		p300=f'{data_dir}/{{cell_line}}/raw_data/wgEncodeAwgTfbsSydhK562P300IggrabUniPk.narrowPeak.gz',
		whole_genome_coverage=f'{data_dir}/{{cell_line}}/data_R/whole_genome_coverage.RData',
		protein_coding=f'{gencode_dir}/GR_Gencode_protein_coding_TSS.RDS',
		protein_coding_positive=f'{gencode_dir}/GR_Gencode_protein_coding_TSS_positive.RDS',
	output:
		f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_randomRegions_with_signal_bin_{config["binSize"]}_window_{config["window"]}.RData',
	shell:
		r'''
		Rscript {code_dir}/define_random_with_signal.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_enhancers][N]} \
			--threshold={config[define_random_with_signal][threshold]} \
			--pathToDir={data_dir} \
			--cellLine={wildcards.cell_line} \
			--p300File={input.p300}
		'''

rule extract_random_with_signal:
	input:
		code=f'{code_dir}/extract_random_with_signal.R',
		enhancers=f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData',
		random_with_signal=f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_randomRegions_with_signal_bin_{config["binSize"]}_window_{config["window"]}.RData',
		bam_files=all_bam_files,
	output:
		f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_random_with_signal_bin_{config["binSize"]}_window_{config["window"]}.RData',
	shell:
		r'''
		Rscript {code_dir}/extract_random_with_signal.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_enhancers][N]} \
			--pathToDir={data_dir} \
			--cellLine={wildcards.cell_line} \
			--normalize=FALSE
		'''

# Training
# --------
#
# Probabilistic modelling of the ChIP-seq signal patterns. Compute the probabilistic scores. The genomic coordinates of the training data are provided as enhancers_sorted.txt and non-enhancers_sorted.txt.
# Training data for K562

# Generate data for 5-fold cross-validation
rule create_training_data_combined:
	input:
		code=f'{code_dir}/create_training_data_combined.R',
		enhancers=f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData',
		promoters=f'{data_dir}/{{cell_line}}/data_R/{config["extract_promoters"]["N"]}_promoters_bin_{config["binSize"]}_window_{config["window"]}.RData',
		random_with_signal=f'{data_dir}/{{cell_line}}/data_R/{config["extract_enhancers"]["N"]}_random_with_signal_bin_{config["binSize"]}_window_{config["window"]}.RData',
	output:
		rdata=expand(f'{cv_files}_training_data.RData', i=[1, 2, 3, 4, 5]),
		train=expand(f'{cv_files}_train_data.txt', i=[1, 2, 3, 4, 5]),
		test=expand(f'{cv_files}_test_data.txt', i=[1, 2, 3, 4, 5]),
	shell:
		r'''
		Rscript {code_dir}/create_training_data_combined.R \
			--window={config[window]} \
			--binSize={config[binSize]} \
			--N={config[extract_enhancers][N]} \
			--k={config[create_training_data_combined][k]} \
			--pathToDir={data_dir} \
			--distanceMeasure={wildcards.distance_measure} \
			--cellLine={wildcards.cell_line}
		'''

rule cv_train_predict:
	input:
		code=f'{code_dir}/grid.py',
		train=expand(f'{cv_files}_train_data.txt', i=[1, 2, 3, 4, 5]),
		test=expand(f'{cv_files}_test_data.txt', i=[1, 2, 3, 4, 5]),
	output:
		expand(f'{cv_files}_predicted_data.txt', i=[1, 2, 3, 4, 5])
	run:
		# Run for all folds
		for train, test, out in zip(input.train, input.test, output):
			shell(r'''
				python {code_dir}/grid.py \
					-log2c {config[cv_train_predict][log2c]} \
					-log2g {config[cv_train_predict][log2g]} \
					-out {out} \
					{train} {test}
				''')

# rule create_test_data_combined:
# 	shell:
# 		r'''
# 		Rscript code/create_test_data_combined.R \
# 			--window={config[window]} \
# 			--binSize={config[binSize} \
# 			--N={config[extract_promoters][N]} \
# 			--pathToDir={data_dir} \
# 			--distanceMeasure={wildcards.distance_measure} \
# 			--cellLine=Gm12878 \
# 			--normalize=TRUE \
# 			--NormCellLine=K562
# 		'''
# 
# rule train_whole_genome:
# 	input:
# 		code=f'{code_dir}/grid.py',
# 		train=f'{data_dir}/results/model_promoters_and_random_combined/{cell_line}/{{distance_measure}}/NSamples_{config["extract_enhancers"]["N"]}_window_{config["window"]}_bin_{config["binSize"]}_train_data.txt',
# 	output:
# 		range=f'{data_dir}/results/model_promoters_and_random_combined/{cell_line}/{{distance_measure}}/NSamples_{config["extract_enhancers"]["N"]}_window_{config["window"]}_bin_{config["binSize"]}_train_data.txt.range',
# 		model=f'{data_dir}/results/model_promoters_and_random_combined/{cell_line}/{{distance_measure}}/NSamples_{config["extract_enhancers"]["N"]}_window_{config["window"]}_bin_{config["binSize"]}_train_data.txt.model',
# 	shell:
# 		'python {code_dir}/grid.py {input.train}'
# 
# rule create_data_whole_genome:
# 	input:
# 		code=f'{code_dir}/create_data_predict_whole_genome_combined.R',
# 		enhancers=f'{data_r_dir}/{config["extract_enhancers"]["N"]}_enhancers_bin_{config["binSize"]}_window_{config["window"]}.RData',
# 		promoters=f'{data_r_dir}/{config["extract_promopters"]["N"]}_promoters_bin_{config["binSize"]}_window_{config["window"]}.RData',
# 		pure_random=f'{data_r_dir}/pure_random_{config["extract_random_pure"]["N"]}_bin_{config["binSize"]}_window_{config["window"]}.RData',
# 		random_with_signal=f'{data_r_dir}/{config["extract_enhancers"]["N"]}_randomRegions_with_signal_bin_{config["binSize"]}_window_{config["window"]}.RData',
# 		whole_genome=f'{data_r_dir}/whole_genome_coverage.RData',
# 	output:
# 		train=f'{data_dir}/results/model_promoters_and_random_combined/{cell_line}/{{distance_measure}}/bin_{config["binSize"]}_train_data.txt',
# 		whole_genome=f'{data_dir}/results/model_promoters_and_random_combined/{cell_line}/{{distance_measure}}/whole_genome_data.RData',
# 	shell:
# 		r'''
# 		Rscript code/create_data_predict_whole_genome_combined.R \
# 			--window={config[window]} \
# 			--binSize={config[binSize]} \
# 			--N={config[extract_enhancers][N]} \
# 			--distanceMeasure={wildcards.distance_measure} \
# 			--cellLine={cell_line} \
# 			--pathToDir={data_dir} \
# 			--NormCellLine=K562
# 		'''
