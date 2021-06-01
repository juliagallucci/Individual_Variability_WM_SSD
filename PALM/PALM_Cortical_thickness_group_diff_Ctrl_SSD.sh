#!/bin/bash
#SBATCH --partition=low-moby
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --time=12:00:00
#SBATCH --export=ALL
#SBATCH --job-name PALM
#SBATCH --output=/projects/jgallucci/PALM/PALM_conmat_simple_T_thickness_group_diff_Ctrl_SSD%j.txt
#SBATCH --array=1

module load matlab/R2017b
module load palm/alpha111
module load connectome-workbench/1.4.1
#Assign DIR to the root directory for PALM analysis
DIR="/projects/jgallucci/PALM/"
#users should input the directory of sublistids
#sublistids is in the format of "subid_site_number", eg: sub-CMHWM003
sublistids="${DIR}/sub_ids/Ctrl_Scz.txt"
#assign full path for filename files, which is a list of path to GLM output in surface space
filename="$(find $DIR/file_ls/Ctrl_Scz/thick.txt -type f | head -n $SLURM_ARRAY_TASK_ID | tail -n 1)"
truncname="$(echo $(basename `echo "$filename"`) | sed 's/thick/PALM_group_diff_Ctrl_Scz_cortical_thick/;s/.txt//')"
outdir="${DIR}/Results/$truncname"
desmat="${DIR}/con_design_matrix/groupdiff_Ctrl_Scz_design_age_sex.csv"
conmat="${DIR}/con_design_matrix/contrast_matrix_age_sex.csv"
#outdier is the place where users want to save results in
echo output directory is $outdir
mkdir -p $outdir
cd $outdir

#assign path to where the midthickness and vertex files are located
HCP_DATA=/projects/ttan
infile=allsubs_merged.dscalar.nii
fname=merge_split
#extracting the first element of sublistids file
exampleSubid=$(head -n 1 ${sublistids})
#first Instance of sublistids file, change these path to approriate path
surfL=${HCP_DATA}/NEUR/in_progress/ciftify/${exampleSubid}/MNINonLinear/fsaverage_LR32k/${exampleSubid}.L.midthickness.32k_fs_LR.surf.gii
surfR=${HCP_DATA}/NEUR/in_progress/ciftify/${exampleSubid}/MNINonLinear/fsaverage_LR32k/${exampleSubid}.R.midthickness.32k_fs_LR.surf.gii

#stage 1 merge files (do a while loop reading a text file with a lsit of cifti files
mergefiles() {
    args=""
    while read ff
    do
	  args="${args} -cifti $ff"
    done < ${filename} #users need to specify the full path for filename file
    echo $args
    # allsubs_merged.dscalar.nii is the file that PALM will use
    wb_command -cifti-merge ${infile} ${args}
}

#stage 2 separate cifti into gifti
cifti2gifti() {
    wb_command -cifti-separate $infile COLUMN -metric CORTEX_LEFT ${fname}_L.func.gii -metric CORTEX_RIGHT ${fname}_R.func.gii
    wb_command -gifti-convert BASE64_BINARY ${fname}_L.func.gii ${fname}_L.func.gii
    wb_command -gifti-convert BASE64_BINARY ${fname}_R.func.gii ${fname}_R.func.gii
}
#stage 3 Calculate mean surface
meansurface() {
    MERGELIST=""
    while read subids; do
	  dir=/projects/jgallucci/VA_files/Ctrl_Scz
	  MERGELIST="${MERGELIST} -metric $dir/${subids}.L_midthick_va.shape.gii";
    done < ${sublistids}

    #wb_command will automatically save results in the current dir, which is outdir
    wb_command -metric-merge L_midthick_va.func.gii ${MERGELIST}
    wb_command -metric-reduce L_midthick_va.func.gii MEAN L_area.func.gii

    MERGELIST=""
    while read subids; do
	  dir=/projects/jgallucci/VA_files/Ctrl_Scz
	  MERGELIST="${MERGELIST} -metric $dir/${subids}.R_midthick_va.shape.gii";
    done < ${sublistids}

    wb_command -metric-merge R_midthick_va.func.gii ${MERGELIST}
    wb_command -metric-reduce R_midthick_va.func.gii MEAN R_area.func.gii
}

#stage 4: RUN PALM
runpalm() {
    palm -i ${fname}_L.func.gii -d $desmat -t $conmat -o results_L_cort -T -tfce2D -s $surfL L_area.func.gii -logp -n 1000 -precision "double"
    palm -i ${fname}_R.func.gii -d $desmat -t $conmat -o results_R_cort -T -tfce2D -s $surfR R_area.func.gii -logp -n 1000 -precision "double"

    wb_command -cifti-create-dense-from-template ${infile} results_cort_tfce_tstat_fwep_c1.dscalar.nii -metric CORTEX_LEFT results_L_cort_tfce_tstat_fwep_c1.gii -metric CORTEX_RIGHT results_R_cort_tfce_tstat_fwep_c1.gii
    wb_command -cifti-create-dense-from-template ${infile} results_cort_tfce_tstat_fwep_c2.dscalar.nii -metric CORTEX_LEFT results_L_cort_tfce_tstat_fwep_c2.gii -metric CORTEX_RIGHT results_R_cort_tfce_tstat_fwep_c2.gii
 

    wb_command -cifti-math '(x-y)' ${fname}_tstat_fwep_c12.dscalar.nii -var x results_cort_tfce_tstat_fwep_c1.dscalar.nii -var y results_cort_tfce_tstat_fwep_c2.dscalar.nii
}
#back to the previous directory

mergefiles &&
    cifti2gifti &&
    meansurface &&
    runpalm
