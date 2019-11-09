#!/bin/bash
#SBATCH --ntasks-per-node=2
#SBATCH --nodes=1
#SBATCH --gres=gpu:2
#SBATCH --time=00:00:59
#SBATCH --output=mpi_simple.out
#SBATCH -A lc_an2
WORK_HOME=/home/rcf-proj/an2/nlukic
cd $WORK_HOME
srun -n 1 ./qd
