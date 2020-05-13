include: "src/common.smk"

rule all:
    """
    Collect the main outputs of the workflow
    """
    input:
        #expand(opj(config["results_dir"],"dada2","ITS","dada_{x}.rds"), x=["f","r"]),
        #expand(opj(config["results_dir"],"dada2","ITS","{y}.rds"), y=["mergers","seqtab"])
        expand(opj(config["results_dir"], "intermediate",
                 "cutadapt", "R1", "{pool_id}_R1.fastq.gz"),
               pool_id = pools.keys())

rule fastq_dump:
    output:
        R1 = opj(config["data_dir"], "{sample_id}_R1.fastq.gz"),
        R2 = opj(config["data_dir"], "{sample_id}_R2.fastq.gz")
    log:
        opj("logs","sra-tools", "{sample_id}.log")
    params:
        data_dir = lambda wildcards, output: os.path.dirname(output.R1),
        acc = lambda wildcards: samples[wildcards.sample_id],
        spots = config["maxSpotId"]
    conda:
        "envs/sratools.yml"
    shell:
        """
        fastq-dump {params.spots} --split-3 --gzip -O {params.data_dir} \
            {params.acc} > {log} 2>&1
        mv {params.data_dir}/{params.acc}_1.fastq.gz {output.R1}
        mv {params.data_dir}/{params.acc}_2.fastq.gz {output.R2}
        """

rule pool:
    """Collect all samples with same sampleName but different runID"""
    input:
        lambda wildcards: pools[wildcards.pool_id][wildcards.R]
    output:
        opj(config["results_dir"], "intermediate", "pooled", "{pool_id}_{R}.fastq.gz"),
    message:
        "Pooling {wildcards.pool_id}_R{wildcards.R}.fastq.gz"
    run:
        if len(input) == 1:
            src = os.path.abspath(input[0])
            dst = os.path.abspath(output[0])
            shell("ln -s {src} {dst}")
        else:
            shell("gunzip -c {input} | gzip -c > {output}")

rule prefilter:
    """Runs the ITS prefiltering step for ambiguous bases"""
    input:
        R1 = opj(config["results_dir"], "intermediate", "pooled",
                 "{pool_id}_R1.fastq.gz"),
        R2 = opj(config["results_dir"], "intermediate", "pooled",
                 "{pool_id}_R2.fastq.gz")
    output:
        R1 = opj(config["results_dir"], "intermediate", "prefilter", "{pool_id}_R1.fastq.gz"),
        R2 = opj(config["results_dir"], "intermediate", "prefilter", "{pool_id}_R2.fastq.gz")
    log:
        opj("logs", "prefilter", "{pool_id}.log")
    threads: config["threads"]
    params:
        truncLen = config["dada2"]["truncLen"],
        maxN = config["dada2"]["maxN"],
        maxEE = config["dada2"]["maxEE"],
        rm_phix = config["dada2"]["rm_phix"],
        minLen = config["dada2"]["minLen"],
        truncQ = config["dada2"]["truncQ"]
    conda:
        "envs/dada2.yml"
    script:
        "src/R/prefilter.R"

rule generate_revcomp:
    output:
        fwd_rc = temp(opj(config["results_dir"], "intermediate", "fwd_rc")),
        rev_rc = temp(opj(config["results_dir"], "intermediate", "rev_rc"))
    params:
        fwd = config["cutadapt"]["FWD"],
        rev = config["cutadapt"]["REV"]
    conda:
        "envs/biopython.yml"
    shell:
        """
        python src/revcomp.py {params.fwd} > {output.fwd_rc}
        python src/revcomp.py {params.rev} > {output.rev_rc}
        """

rule cut_ITS_primers:
    """Removes primers from ITS data using cutadapt"""
    input:
        R1 = opj(config["results_dir"], "intermediate", "prefilter", "{pool_id}_R1.fastq.gz"),
        R2 = opj(config["results_dir"], "intermediate", "prefilter", "{pool_id}_R2.fastq.gz"),
        fwd_rc = opj(config["results_dir"], "intermediate", "fwd_rc"),
        rev_rc = opj(config["results_dir"], "intermediate", "rev_rc")
    output:
        R1 = opj(config["results_dir"], "intermediate", "cutadapt", "R1", "{pool_id}_R1.fastq.gz"),
        R2 = opj(config["results_dir"], "intermediate", "cutadapt", "R2", "{pool_id}_R2.fastq.gz")
    log:
        opj("logs", "cutadapt", "{pool_id}.log")
    params:
        FWD = config["cutadapt"]["FWD"],
        REV = config["cutadapt"]["REV"],
        n = config["cutadapt"]["n"]
    conda:
        "envs/cutadapt.yml"
    shell:
        """
        A=$(cat {input.fwd_rc})
        a=$(cat {input.rev_rc})
        
        cutadapt -g {params.FWD} -a $a -G {params.REV} -A $A \
         -n {params.n} -o {output.R1} -p {output.R2} {input.R1} {input.R2} > {log} 2>&1
        """

rule dada2:
    """Calls DADA2 Rscript with trimmed input"""
    input:
        expand(opj(config["results_dir"], "intermediate", "cutadapt",
                         "{pool_id}_R1.fastq.gz"),
                     pool_id = pools.keys()),
        expand(opj(config["results_dir"], "intermediate", "cutadapt",
                         "{pool_id}_R1.fastq.gz"),
                     pool_id = pools.keys())
    output:
        expand(opj(config["results_dir"], "dada2", "dada_{x}.rds"), x=["f", "r"]),
        expand(opj(config["results_dir"], "dada2", "{y}.rds"), y=["mergers", "seqtab"])
    log:
        opj("logs", "dada2", "dada2.log")
    params:
        fw_dir = lambda wildcards, input: os.path.dirname(input[0][0]),
        rv_dir = lambda wildcards, input: os.path.dirname(input[1][0]),
        out_dir = opj(config["results_dir"], "dada2")
    resources:
        runtime = lambda wildcards, attempt: attempt**2*60*4
    threads: config["threads"]
    shell:
        """
        rundada2.R {params.fw_dir} {params.rv_dir} {params.out_dir} {threads} > {log} 2>&1
        """
