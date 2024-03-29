/*******************************************************************************
Quantum dynamics (QD) simulation of an electron in one dimension.

USAGE

%cc -o qd1 qd1.c -lm
%qd1 (input file qd1.in required; see qd1.h for the input format)
*******************************************************************************/
#include <omp.h>
#include <mpi.h>
#include <cuda.h>
#include <stdio.h>
#include <math.h>
#include "qd1.h"

#define NUM_DEVICE 2
#define NUM_BLOCK 13
#define NUM_THREAD 192

dim3 dimGrid(NUM_BLOCK, 1, 1);
dim3 dimBlock(NUM_THREAD, 1, 1);

/*
    Allocate array on GPU and copy the values from CPU.

    This is used for arrays psi, wrk and u.
*/

void host2device(double *d1, double h2[NX + 2][2], int offset, int nx) {
    size_t size = sizeof(double) * (nx + 2) * 2;    
    double* h1 = (double *) malloc(size);
    int i, j;

    for (i = 0; i <= nx + 1; i++) {
        for (j = 0; j <= 1; j++) {
            h1[i * 2 + j] = h2[offset + i][j];
        }
    }

    cudaMemcpy(d1, h1, size, cudaMemcpyHostToDevice);
}

void device2host(double h2[NX + 2][2], double* d1, int offset, int nx) {
    size_t size = sizeof(double) * (nx + 2) * 2;    
    double* h1 = (double *) malloc(size);

    cudaMemcpy(h1, d1, size, cudaMemcpyHostToDevice);

    int i,j;
    for (i = 1; i <= nx; i++) {
        for (j = 0; j <= 1; j++) {
            h2[offset + i][j] = h1[2 * i + j];
        }
    }
}

static int myid;
static int nproc;

int main(int argc, char **argv) {
    int nx, step;

    MPI_Init(&argc, &argv); 
    MPI_Comm_rank(MPI_COMM_WORLD,&myid);
    MPI_Comm_size(MPI_COMM_WORLD,&nproc); 

	init_param();  /* Read input parameters */
	init_prop();   /* Initialize the kinetic & potential propagators */
	init_wavefn(); /* Initialize the electron wave function */
    
    omp_set_num_threads(NUM_DEVICE);
    nx = NX / NUM_DEVICE;
    #pragma omp parallel private(step) 
    {
        int mpid = omp_get_thread_num();
        int offset = nx * mpid;

        cudaSetDevice(mpid % NUM_DEVICE);

        double *dev_psi, *dev_wrk, *dev_u, *dev_blx0, *dev_blx1, *dev_bux0, *dev_bux1, *al0, *al1;

        size_t size = sizeof(double) * (nx + 2) * 2;
        
        // Allocate dev_psi.
        cudaMalloc((void **) &dev_psi, size);
        // Copy to dev_psi.
        host2device(dev_psi, psi, offset, nx);

        // Allocate dev_wrk.
        cudaMalloc((void **) &dev_wrk, size);
        // Copy to dev_wrk.
        host2device(dev_wrk, wrk, offset, nx);

        // Allocate dev_u.
        cudaMalloc((void **) &dev_u, size);
        // Copy to dev_u.
        host2device(dev_u, u, offset, nx);
        

        // Allocate al0.
        cudaMalloc((void **) &al0, sizeof(double));
        // ??????????    
        cudaMemcpy(al0, al[0], sizeof(double) * 2, cudaMemcpyHostToDevice);

        // Allocate al1.
        cudaMalloc((void **) &al1, sizeof(double));
        // ??????????    
        cudaMemcpy(al1, al[1], sizeof(double) * 2, cudaMemcpyHostToDevice);


        // Allocate dev_blx0.
        cudaMalloc((void **) &dev_blx0, size);
        // Copy to dev_blx0.
        host2device(dev_blx0, blx[0], offset, nx);

        // Allocate dev_blx1.
        cudaMalloc((void **) &dev_blx1, size);
        // Copy to dev_blx1.
        host2device(dev_blx1, blx[1], offset, nx);

        // Allocate dev_bux0.
        cudaMalloc((void **) &dev_bux0, size);
        // Copy to dev_bux0.
        host2device(dev_bux0, bux[0], offset, nx);

        // Allocate dev_bux1.
        cudaMalloc((void **) &dev_bux1, size);
        // Copy to dev_bux1.
        host2device(dev_bux1, bux[1], offset, nx);
        
        for (step = 1; step <= NSTEP; step++) {
		    single_step(
			offset, 
			nx, 
			dev_psi, 
			dev_wrk,
			al0,
			al1,
			dev_blx0,
			dev_blx1,
			dev_bux0,
			dev_bux1,
			dev_u); /* Time propagation for one step, DT */
		
		    if (step % NECAL == 0) {
			#pragma omp master 
                    		calc_energy();
			#pragma omp master
				if (myid == 0) printf("%le %le %le %le\n",DT*step,ekin,epot,etot);	
                	#pragma omp barrier
		    }
	}
    }

    MPI_Finalize();    
    return 0;
}

/*----------------------------------------------------------------------------*/
void init_param() {
/*------------------------------------------------------------------------------
	Initializes parameters by reading them from input file.
------------------------------------------------------------------------------*/
	FILE *fp;

	/* Read control parameters */
	fp = fopen("qd1.in","r");
	fscanf(fp,"%le",&LX);
	fscanf(fp,"%le",&DT);
	fscanf(fp,"%d",&NSTEP);
	fscanf(fp,"%d",&NECAL);
	fscanf(fp,"%le%le%le",&X0,&S0,&E0);
	fscanf(fp,"%le%le",&BH,&BW);
	fscanf(fp,"%le",&EH);
	fclose(fp);

	/* Calculate the mesh size */
	dx = LX/NX;
}

/*----------------------------------------------------------------------------*/
void init_prop() {
/*------------------------------------------------------------------------------
	Initializes the kinetic & potential propagators.
------------------------------------------------------------------------------*/
	int stp,s,i,up,lw;
	double a,exp_p[2],ep[2],em[2];
	double x;

	/* Set up kinetic propagators */
	a = 0.5/(dx*dx);

	for (stp=0; stp<2; stp++) { /* Loop over half & full steps */
		exp_p[0] = cos(-(stp+1)*DT*a);
		exp_p[1] = sin(-(stp+1)*DT*a);
		ep[0] = 0.5*(1.0+exp_p[0]);
		ep[1] = 0.5*exp_p[1];
		em[0] = 0.5*(1.0-exp_p[0]);
		em[1] = -0.5*exp_p[1];

		/* Diagonal propagator */
		for (s=0; s<2; s++) al[stp][s] = ep[s];

		/* Upper & lower subdiagonal propagators */
		for (i=1; i<=NX; i++) { /* Loop over mesh points */
			if (stp==0) { /* Half-step */
				up = i%2;     /* Odd mesh point has upper off-diagonal */
				lw = (i+1)%2; /* Even               lower              */
			}
			else { /* Full step */
				up = (i+1)%2; /* Even mesh point has upper off-diagonal */
				lw = i%2;     /* Odd                 lower              */
			}
			for (s=0; s<2; s++) {
				bux[stp][i][s] = up*em[s];
				blx[stp][i][s] = lw*em[s];
			}
		} /* Endfor mesh points, i */
	} /* Endfor half & full steps, stp */

	/* Set up potential propagator */
	for (i=1; i<=NX; i++) {
		x = dx*i + LX * myid;
		/* Construct the edge potential */
		if ((myid==0&i==1) || (myid==nproc&&i==NX)){
			v[i] = EH;
		}
		/* Construct the barrier potential */
		else if (0.5*(LX*nproc-BW)<x && x<0.5*(LX*nproc+BW)){
			v[i] = BH;
		}
		else{
			v[i] = 0.0;
		}
		/* Half-step potential propagator */
		u[i][0] = cos(-0.5*DT*v[i]);
		u[i][1] = sin(-0.5*DT*v[i]);
	}
}

void init_wavefn() {
/*------------------------------------------------------------------------------
    Initializes the wave function as a traveling Gaussian wave packet.
s------------------------------------------------------------------------------*/
    int sx,s;
    double x,gauss,psisq,norm_fac;
    
    /* Calculate the the wave function value mesh point-by-point */
    for (sx=1; sx<=NX; sx++) {
        //make it global by adding myid*LX
        x = myid*LX+dx*sx-X0;
        gauss = exp(-0.25*x*x/(S0*S0));
        psi[sx][0] = gauss*cos(sqrt(2.0*E0)*x);
        psi[sx][1] = gauss*sin(sqrt(2.0*E0)*x);
    }
    
        /* Normalize the wave function */
    psisq=0.0;
    for (sx=1; sx<=NX; sx++){
        for (s=0; s<2; s++){
            psisq += psi[sx][s]*psi[sx][s];
        }
    }
    MPI_Allreduce(&psisq, &psisq, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    MPI_Barrier(MPI_COMM_WORLD); 
    
    psisq *= dx;
        
    norm_fac = 1.0/sqrt(psisq);
    for (sx=1; sx<=NX; sx++){
        for (s=0; s<2; s++){
            psi[sx][s] *= norm_fac;
        }
    }
}

/*----------------------------------------------------------------------------*/
void single_step(
    int offset,
    int nx, 
    double* dev_psi, 
    double* dev_wrk, 
    double* dev_al0,
    double* dev_al1,
    double* dev_blx0,
    double* dev_blx1,
    double* dev_bux0,
    double* dev_bux1,
    double* dev_u) {
/*------------------------------------------------------------------------------
	Propagates the electron wave function for a unit time step, DT.
------------------------------------------------------------------------------*/
	pot_prop(offset, nx, dev_psi, dev_u);  /* half step potential propagation */

	kin_prop(
        0 /* t */, 
        offset, 
        nx, 
        dev_psi, 
        dev_wrk, 
        dev_al0,
        dev_al1,
        dev_blx0,
        dev_blx1,
        dev_bux0,
        dev_bux1 ); /* half step kinetic propagation   */

    kin_prop(
        1 /* t */, 
        offset, 
        nx, 
        dev_psi, 
        dev_wrk, 
        dev_al0,
        dev_al1,
        dev_blx0,
        dev_blx1,
        dev_bux0,
        dev_bux1 ); /* full step kinetic propagation   */
    
    kin_prop(
        0 /* t */, 
        offset, 
        nx, 
        dev_psi, 
        dev_wrk, 
        dev_al0,
        dev_al1,
        dev_blx0,
        dev_blx1,
        dev_bux0,
        dev_bux1 ); /* half step kinetic propagation   */

	pot_prop(offset, nx, dev_psi, dev_u);
}

/*----------------------------------------------------------------------------*/
__global__ void gpu_pot_prop(double* psi, double* u) {
/*------------------------------------------------------------------------------
	Potential propagator for a half time step, DT/2.
------------------------------------------------------------------------------*/
	// int sx;
	// double wr,wi;

	// for (sx=1; sx<=NX; sx++) {
	// 	wr=u[sx][0]*psi[sx][0]-u[sx][1]*psi[sx][1];
	// 	wi=u[sx][0]*psi[sx][1]+u[sx][1]*psi[sx][0];
	// 	psi[sx][0]=wr;
	// 	psi[sx][1]=wi;
	// }

    int tid = blockIdx.x * blockDim.x + threadIdx.x; 
    int sx = tid + 1; 
    double wr, wi; 

    // for(sx; sx <= NX; sx++){
        wr = u[2 * sx + 0] * psi[2 * sx + 0] - u [2 * sx + 1] * psi[2 * sx + 1];
        wi = u[2 * sx + 0] * psi[2 * sx + 1] + u [2 * sx + 1] * psi[2 * sx + 0];
        psi[2 * sx + 0] = wr;
        psi[2 * sx + 1] = wi;
    // }
}

void pot_prop(int offset, int nx, double* dev_psi, double* dev_u) {
    host2device(dev_psi, psi, offset, nx);
    gpu_pot_prop <<<dimGrid, dimBlock>>> (dev_psi, dev_u);
    device2host(psi, dev_psi, offset, nx);

    #pragma omp barrier
}

/*----------------------------------------------------------------------------*/
__global__ void gpu_kin_prop(
    double* psi, 
    double* wrk, 
    double* al, 
    double* blx, 
    double* bux) {
/*----------------------------------------------------------------------------*/
    int tid = blockIdx.x * blockDim.x + threadIdx.x; 
    int sx = tid + 1; 
    double wr, wi; 

    // for (sx = 1; sx <= NX; sx++) {
		wr = al[0] * psi[2 * sx + 0] - al[1] * psi[2 * sx + 1];
		wi = al[0] * psi[2 * sx + 1] + al[1] * psi[2 * sx + 0];
		wr += (blx[2 * sx + 0] * psi[2 * (sx - 1) + 0] - blx[2 * sx + 1] * psi[2 * (sx - 1) + 1]);
		wi += (blx[2 * sx + 0] * psi[2 * (sx - 1) + 1] + blx[2 * sx + 1] * psi[2 * (sx - 1) + 0]);
		wr += (bux[2 * sx + 0] * psi[2 * (sx + 1) + 0] - bux[2 * sx + 1] * psi[2 * (sx + 1) + 1]);
		wi += (bux[2 * sx + 0] * psi[2 * (sx + 1) + 1] + bux[2 * sx + 1] * psi[2 * (sx + 1) + 0]);
		wrk[2 * sx + 0] = wr;
		wrk[2 * sx + 1] = wi;
	// }
}

void kin_prop(
    int t,
    int offset,
    int nx,
    double* dev_psi,
    double* dev_wrk,
    double* dev_al0,
    double* dev_al1,
    double* dev_blx0,
    double* dev_blx1,
    double* dev_bux0,
    double* dev_bux1) {
/*------------------------------------------------------------------------------
	Kinetic propagation for t (=0 for DT/2--half; 1 for DT--full) step.
--------------------------------------------------------------------------------*/
	/* Apply the periodic boundary condition */
    	#pragma omp master
		periodic_bc();
    	#pragma omp barrier

	host2device(dev_psi, psi, offset, nx);

    if (t == 0) {
        gpu_kin_prop <<<dimGrid, dimBlock>>> (dev_psi, dev_wrk, dev_al0, dev_blx0, dev_bux0);
    } else {
        gpu_kin_prop <<<dimGrid, dimBlock>>> (dev_psi, dev_wrk, dev_al1, dev_blx1, dev_bux1);
    }

	/* Copy the new wave function back to PSI */
	// for (sx=1; sx<=NX; sx++)
	// 	for (s=0; s<=1; s++)
	// 		psi[sx][s] = wrk[sx][s];
    device2host(psi, dev_wrk, offset, nx);

    #pragma omp barrier
}

/*----------------------------------------------------------------------------*/
void periodic_bc() {
/*------------------------------------------------------------------------------
	Applies the periodic boundary condition to wave function PSI, by copying
	the boundary values to the auxiliary array positions at the other ends.
------------------------------------------------------------------------------*/
//	int s;
//
//	/* Copy boundary wave function values */
//	for (s=0; s<=1; s++) {
//		psi[0][s] = psi[NX][s];
//		psi[NX+1][s] = psi[1][s];
//	}


	MPI_Request request;
	MPI_Status status; 

	int x, y;
	double sendMessage[2], receiveMessage[2];
	
	x = (myid + 1) % nproc; 
	y = (myid - 1 + nproc) % nproc; 

	sendMessage[0] = psi[NX][0];
	sendMessage[1] = psi[NX][1];

	MPI_Irecv(&receiveMessage, 2, MPI_DOUBLE, x, 666, MPI_COMM_WORLD, &request);
	MPI_Send(&sendMessage, 2, MPI_DOUBLE, y, 666, MPI_COMM_WORLD);
	MPI_Wait(&request, &status);

	psi[0][0] = receiveMessage[0]; 
	psi[0][1] = receiveMessage[1]; 

	MPI_Irecv(&receiveMessage, 2, MPI_DOUBLE, y, 667, MPI_COMM_WORLD, &request);
	MPI_Send(&sendMessage, 2, MPI_DOUBLE, x, 667, MPI_COMM_WORLD);
	MPI_Wait(&request, &status);

	psi[NX+1][0] = receiveMessage[0]; 
	psi[NX+1][1] = receiveMessage[1]; 
}

/*----------------------------------------------------------------------------*/
void calc_energy() {
/*------------------------------------------------------------------------------
	Calculates the kinetic, potential & total energies, EKIN, EPOT & ETOT.
------------------------------------------------------------------------------*/
	int sx,s;
	double a,bx;

	/* Apply the periodic boundary condition */
	periodic_bc();

	/* Tridiagonal kinetic-energy operators */
	a =   1.0/(dx*dx);
	bx = -0.5/(dx*dx);

	/* |WRK> = (-1/2)Laplacian|PSI> */
	for (sx=1; sx<=NX; sx++)
		for (s=0; s<=1; s++)
			wrk[sx][s] = a*psi[sx][s]+bx*(psi[sx-1][s]+psi[sx+1][s]);

	/* Kinetic energy = <PSI|(-1/2)Laplacian|PSI> = <PSI|WRK> */
	ekin = 0.0;
	for (sx=1; sx<=NX; sx++)
		ekin += (psi[sx][0]*wrk[sx][0]+psi[sx][1]*wrk[sx][1]);
	ekin *= dx;
    	MPI_Allreduce(&ekin, &ekin, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    

	/* Potential energy */
	epot = 0.0;
	for (sx=1; sx<=NX; sx++)
		epot += v[sx]*(psi[sx][0]*psi[sx][0]+psi[sx][1]*psi[sx][1]);
	epot *= dx;
    	MPI_Allreduce(&epot, &epot, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    
    /* Total energy */
	etot = ekin+epot;
}
