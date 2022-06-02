# The default rule that will do the entire prediction pipeline
rule predict:
	input: f'{data_dir}/K562/data_R/profiles.rds'

# Rules for downloading various files

# Function that finds all the available BAM files
def all_bam_files(wildcards):
	print(wildcards.cell_line)
	return [
		f'{data_dir}/{wildcards.cell_line}/bam_shifted/{data_type}.bam'
		for data_type in all_data_types(wildcards.cell_line)
	]

# The steps needed for the analysis
rule whole_genome_coverage:
	input:
		code=f'{scripts_dir}/1_whole_genome_coverage.R',
		bam_files=all_bam_files,
	output:
		f'{data_dir}/{{cell_line}}/data_R/whole_genome_coverage.rds'
	shell:
		f'Rscript {scripts_dir}/1_whole_genome_coverage.R'

rule make_profiles:
	input:
		code=f'{scripts_dir}/2_make_profiles.R',
		bam_files=all_bam_files,
		p300=f'{data_dir}/{{cell_line}}/raw_data/ENCFF702XPO-p300.narrowPeak.gz',
		DNase=f'{data_dir}/{{cell_line}}/raw_data/ENCFF274YGF-dnaseq.narrowPeak.gz',
		blacklist_Dac=f'{data_dir}/blacklists/hg38-blacklist.v2.bed.gz',
		TSS_annotation=f'{data_dir}/GENCODE_TSS/gencode.v40.annotation.gtf.gz',
		whole_genome_cov=f'{data_dir}/{{cell_line}}/data_R/whole_genome_coverage.rds',
	output:
		f'{data_dir}/{{cell_line}}/data_R/profiles.rds'
	shell:
		f'Rscript {scripts_dir}/2_make_profiles.R'


