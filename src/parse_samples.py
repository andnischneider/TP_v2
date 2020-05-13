#!/usr/bin/env python

import pandas as pd
from os.path import join as opj


def get_samples(f, config):
    samples = {}
    pools = {}
    df = pd.read_csv(f, sep="\t", header=0)
    for i in df.index:
        r = df.loc[i]
        try:
            run_id = r.run_id
        except KeyError:
            run_id = "1"
        pool_id = r.sample_name
        sample_id = "{}.{}".format(pool_id, run_id)
        if "url" in df.columns:
            source = r["url"]
            config["source"] = "url"
        elif "sra_id" in df.columns:
            source = r["sra_id"]
            config["source"] = "sra"
        else:
            source = ""
            config["source"] = ""
        samples[sample_id] = source
        if pool_id not in pools.keys():
            pools[pool_id] = {"R1": [], "R2": []}
        pools[pool_id]["R1"].append(opj(config["data_dir"],
                                        "{}_R1.fastq.gz".format(sample_id)))
        pools[pool_id]["R2"].append(opj(config["data_dir"],
                                        "{}_R2.fastq.gz".format(sample_id)))
    return samples, pools, config
