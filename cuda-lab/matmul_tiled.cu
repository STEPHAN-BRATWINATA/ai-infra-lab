// matmul_tiled.cu — HPC: hierarquia de memoria (shared memory tiling)
// Compara dois kernels de multiplicacao de matrizes na GPU:
//   NAIVE : cada thread le A e B direto da memoria GLOBAL (lenta) N vezes
//   TILED : o bloco carrega "ladrilhos" (tiles) de A e B na SHARED MEMORY
//           (ultrarrapida, no chip) e REUTILIZA -> muito menos trafego global
// Metrica HPC: GFLOP/s (throughput aritmetico). FLOPs do matmul = 2*N^3.
// Compilar/rodar:  build.bat matmul_tiled.cu

#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

#define N    1024     // matrizes N x N (multiplo de TILE)
#define TILE 16       // ladrilho 16x16 = tamanho do bloco

// ---------- Kernel NAIVE: tudo da memoria global ----------
__global__ void matmulNaive(const float *A, const float *B, float *C, int n) {
    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    if (row < n && col < n) {
        float soma = 0.0f;
        for (int k = 0; k < n; k++)
            soma += A[row * n + k] * B[k * n + col]; // 2 leituras globais por k
        C[row * n + col] = soma;
    }
}

// ---------- Kernel TILED: usa shared memory e reutiliza dados ----------
__global__ void matmulTiled(const float *A, const float *B, float *C, int n) {
    __shared__ float As[TILE][TILE];   // ladrilho de A no chip
    __shared__ float Bs[TILE][TILE];   // ladrilho de B no chip

    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    float soma = 0.0f;

    // Percorre os ladrilhos ao longo da dimensao k
    for (int t = 0; t < n / TILE; t++) {
        // Cada thread carrega 1 elemento de A e 1 de B para a shared memory
        As[threadIdx.y][threadIdx.x] = A[row * n + (t * TILE + threadIdx.x)];
        Bs[threadIdx.y][threadIdx.x] = B[(t * TILE + threadIdx.y) * n + col];
        __syncthreads();               // espera o bloco terminar de carregar

        // Agora calcula usando dados da SHARED (rapida) -> reutiliza TILE vezes
        for (int k = 0; k < TILE; k++)
            soma += As[threadIdx.y][k] * Bs[k][threadIdx.x];
        __syncthreads();               // espera antes de sobrescrever o tile
    }
    if (row < n && col < n) C[row * n + col] = soma;
}

// Roda um kernel, mede tempo e GFLOP/s, verifica resultado
static float run(const char *nome, void (*launch)(const float*,const float*,float*,int),
                 const float *dA, const float *dB, float *dC, float *hC, int n) {
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);

    cudaEventRecord(a);
    launch(dA, dB, dC, n);             // chama o kernel (via wrapper abaixo)
    cudaEventRecord(b); cudaEventSynchronize(b);
    float ms = 0; cudaEventElapsedTime(&ms, a, b);

    cudaMemcpy(hC, dC, (size_t)n * n * sizeof(float), cudaMemcpyDeviceToHost);
    double gflops = (2.0 * n * n * n) / (ms / 1000.0) / 1.0e9;
    printf("  %-6s | %7.2f ms | %8.1f GFLOP/s | C[0]=%.0f\n", nome, ms, gflops, hC[0]);

    cudaEventDestroy(a); cudaEventDestroy(b);
    return ms;
}

// Wrappers pra passar o kernel como ponteiro de funcao
void launchNaive(const float *A, const float *B, float *C, int n) {
    dim3 th(TILE, TILE), bl(n / TILE, n / TILE);
    matmulNaive<<<bl, th>>>(A, B, C, n);
}
void launchTiled(const float *A, const float *B, float *C, int n) {
    dim3 th(TILE, TILE), bl(n / TILE, n / TILE);
    matmulTiled<<<bl, th>>>(A, B, C, n);
}

int main() {
    size_t bytes = (size_t)N * N * sizeof(float);
    float *A = (float *)malloc(bytes), *B = (float *)malloc(bytes), *hC = (float *)malloc(bytes);
    for (int i = 0; i < N * N; i++) { A[i] = 1.0f; B[i] = 2.0f; } // esperado C = 2*N = 2048

    float *dA, *dB, *dC;
    cudaMalloc(&dA, bytes); cudaMalloc(&dB, bytes); cudaMalloc(&dC, bytes);
    cudaMemcpy(dA, A, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(dB, B, bytes, cudaMemcpyHostToDevice);

    printf("Matmul %dx%d  (esperado C[0]=%d)\n", N, N, 2 * N);
    printf("  Kernel |    tempo   |    throughput   | verifica\n");
    printf("  -------+------------+-----------------+---------\n");
    float msNaive = run("NAIVE", launchNaive, dA, dB, dC, hC, N);
    float msTiled = run("TILED", launchTiled, dA, dB, dC, hC, N);

    printf("\n==> TILED foi %.2fx mais rapido que NAIVE (gracas ao reuso em shared memory)\n",
           msNaive / msTiled);

    cudaFree(dA); cudaFree(dB); cudaFree(dC);
    free(A); free(B); free(hC);
    return 0;
}
