/*******************************************************************************
File qd1.h is a header file for program qd1.c.
*******************************************************************************/
#define NX 4992   /* Number of mesh points */

/* Function prototypes ********************************************************/
void init_param();
void init_prop();
void init_wavefn();
void pot_prop();
void kin_prop(int);
void periodic_bc();
void calc_energy();

/* Input parameters ***********************************************************/
double LX;       /* Simulation box length */
double DT;       /* Time discretization unit */
int NSTEP;       /* Number of simulation steps */
int NECAL;       /* Interval to calculate energies */
double X0,S0,E0; /* Center-of-mass, spread & energy of initial wave packet */
double BH,BW;    /* Barrier height & width */
double EH;       /* Edge potential height */

/* Arrays **********************************************************************
psi[NX+2][2]:    psi[i][0|1] is the real|imaginary part of the wave function
                 on mesh point i
wrk[NX+2][2]:    Work array for a wave function
al[2][2]:        al[0|1][0|1] is the half|full-step diagonal kinetic propagator
                 (real|imaginary part)
bux[2][NX+2][2]: bux[0|1][i][] is the half|full-step upper off-diagonal kinetic
                 propagator on mesh i (real|imaginary part)
blx[2][NX+2][2]: blx[0|1][i][] is the half|full-step lower off-diagonal kinetic
                 propagator on mesh i (real|imaginary part)
v[NX+2]:         v[i] is the potential energy at mesh point i
u[NX+2][2]:      u[i][] is the potential propagator on i (real|imaginary part)
*******************************************************************************/
double psi[NX+2][2];
double wrk[NX+2][2];
double al[2][2];
double bux[2][NX+2][2],blx[2][NX+2][2];
double v[NX+2];
double u[NX+2][2];

/* Variables *******************************************************************
dx   = Mesh spacing
ekin = Kinetic energy
epot = Potential energy
etot = Total energy
*******************************************************************************/
double dx;
double ekin,epot,etot;



void init_param();
void init_prop();
void init_wavefn();
void host2device(double *d1, double h2[NX + 2][2], int offset, int nx);
void device2host(double h2[NX + 2][2], double* d1, int offset, int nx);
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
    double* dev_u);
void pot_prop(int offset, int nx, double* dev_psi, double* dev_u);
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
    double* dev_bux1);