#include <omp.h>
#include <cuda.h>

#include <qd1.h>

#define NUM_DEVICE 2
#define NUM_BLOCK 13
#define NUM_THREAD 192

//cudaMalloc((void**)&dev_psi, sizeof(double)*2*(nx+2));
//dev_wrk, dev_u, dev_blx0, dev_blx1, dev_bux0, dev_bux1) 
//cudaMalloc((void**)&dev_al0, sizeof(double)*2);
//al1


/*
    Allocate array on GPU and copy the values from CPU.

    This is used for arrays psi, wrk and u.
*/
void host2device(double *d1, double h2[NX + 2][2], int offset, int nx) {
    
    size_t size = sizeof(double) * (nx + 2) * 2;    
    double* h1 = (double *) malloc(size);
    int i, j;

    for (i = 0; i <= nx + 1; i++) {
        for (j = 0; j <= 1; i++) {
            h1[i * 2 + j] = h2[offset + i][j];
        }
    }

    cudaMemcpy(d1, h1, size, cudaMemcopyHostToDevice);
}

int main(int argc, char **arvg) {
    int nx, step;
    omp_set_num_threads(NUM_DEVICE);
    nx = NX / NUM_DEVICE;
    #pragma omp parallel private (step) {
        int mpid = omp_get_thread_num();
        int offset = nx * mpid;

        cudaSetDevice(mpid % NUM_DEVICE);

        double* dev_psi, dev_wrk, dev_u, dev_blx0, dev_blx1, dev_bux0, dev_bux1, al0, al1;

        size_t size = sizeof(double) * (nx + 2) * 2;
        
        // Allocate dev_psi.
        cudaMalloc((double *) &dev_psi, size);
        // Copy to dev_psi.
        host2device(dev_psi, psi, offset, nx);

        // Allocate dev_wrk.
        cudaMalloc((double *) &dev_wrk, size);
        // Copy to dev_wrk.
        host2device(dev_wrk, wrk, offset, nx);

        // Allocate dev_u.
        cudaMalloc((double *) &dev_u, size);
        // Copy to dev_u.
        host2device(dev_u, u, offset, nx);
        

        // Allocate al0.
        cudaMalloc((double *) &al0, 0);
        // ??????????    
        cudaMemcpy(al0, al[0], sizeof(double) * 2, cudaMemcopyHostToDevice);

        // Allocate al1.
        cudaMalloc((double *) &al1, 0);
        // ??????????    
        cudaMemcpy(al1, al[1], sizeof(double) * 2, cudaMemcopyHostToDevice);

        // Allocate dev_blx0.
        cudaMalloc((double *) &dev_blx0, size);
        // Copy to dev_blx0.
        host2device(dev_blx0, blx[0], offset, nx);

        // Allocate dev_blx1.
        cudaMalloc((double *) &dev_blx1, size);
        // Copy to dev_blx1.
        host2device(dev_blx1, blx[1], offset, nx);

        // Allocate dev_bux0.
        cudaMalloc((double *) &dev_bux0, size);
        // Copy to dev_bux0.
        host2device(dev_bux0, bux[0], offset, nx);

        // Allocate dev_bux1.
        cudaMalloc((double *) &dev_bux1, size);
        // Copy to dev_bux1.
        host2device(dev_bux1, bux[1], offset, nx);
        
        size_t size = NUM_BLOCK * NUM_THREAD * sizeof(float);  //Array memory size
	    sumHost = (float *)malloc(size);  //  Allocate array on host
	    cudaMalloc((void **) &sumDev, size);  // Allocate array on device
	    // Initialize array in device to 0
	    cudaMemset(sumDev, 0, size);

        for (step = 1; step <= NSTEP; step++) {
		    single_step(); /* Time propagation for one step, DT */

		    if (step % NECAL == 0) {
			    #pragma omp master
                    calc_energy();
                #pragma omp barrier
		    }
	    }
    }

}
