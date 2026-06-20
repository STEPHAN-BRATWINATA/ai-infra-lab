// cublas_matmul.cu — HPC: kernel "a mao" vs BIBLIOTECA otimizada (cuBLAS)
// Compara NAIVE vs TILED vs cuBLAS (SGEMM) com benchmarking decente:
//   - warmup (descarta a 1a execucao)
//   - media de R execucoes (reduz variancia de medicao)
// Metrica: GFLOP/s. FLOPs do matmul = 2*N^3.
// Licao AI Factory: em producao voce NAO escreve o kernel; usa cuBLAS/cuDNN.
// Compilar:  (precisa linkar a cuBLAS)
//   nvcc -arch=sm_86 cublas_matmul.cu -lcublas -o cublas_matmul.exe

#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <cublas_v2.h>

#define N    1024
#define TILE 16
#define R    30          // repeticoes para a media

__global__ void matmulNaive(const float *A, const float *B, float *C, int n) {
    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    if (row < n && col < n) {
        float s = 0.0f;
        for (int k = 0; k < n; k++) s += A[row * n + k] * B[k * n + col];
        C[row * n + col] = s;
    }
}

__global__ void matmulTiled(const float *A, const float *B, float *C, int n) {
    __shared__ float As[TILE][TILE], Bs[TILE][TILE];
    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    float s = 0.0f;
    for (int t = 0; t < n / TILE; t++) {
        As[threadIdx.y][threadIdx.x] = A[row * n + (t * TILE + threadIdx.x)];
        Bs[threadIdx.y][threadIdx.x] = B[(t * TILE + threadIdx.y) * n + col];
        __syncthreads();
        for (int k = 0; k < TILE; k++) s += As[threadIdx.y][k] * Bs[k][threadIdx.x];
        __syncthreads();
    }
    if (row < n && col < n) C[row * n + col] = s;
}

// Mede o tempo medio (ms) de uma funcao de lancamento, com warmup + R runs
template <typename F>
static float bench(F launch) {
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    launch(); cudaDeviceSynchronize();          // warmup (descartado)
    cudaEventRecord(a);
    for (int i = 0; i < R; i++) launch();
    cudaEventRecord(b); cudaEventSynchronize(b);
    float ms = 0; cudaEventElapsedTime(&ms, a, b);
    cudaEventDestroy(a); cudaEventDestroy(b);
    return ms / R;                               // media
}

static void report(const char *nome, float ms, float c0) {
    double gflops = (2.0 * N * N * N) / (ms / 1000.0) / 1.0e9;
    printf("  %-7s | %7.3f ms | %9.1f GFLOP/s | C[0]=%.0f\n", nome, ms, gflops, c0);
}

int main() {
    size_t bytes = (size_t)N * N * sizeof(float);
    float *A = (float *)malloc(bytes), *B = (float *)malloc(bytes), *hC = (float *)malloc(bytes);
    for (int i = 0; i < N * N; i++) { A[i] = 1.0f; B[i] = 2.0f; } // esperado 2*N = 2048

    float *dA, *dB, *dC;
    cudaMalloc(&dA, bytes); cudaMalloc(&dB, bytes); cudaMalloc(&dC, bytes);
    cudaMemcpy(dA, A, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(dB, B, bytes, cudaMemcpyHostToDevice);

    dim3 th(TILE, TILE), bl(N / TILE, N / TILE);
    cublasHandle_t h; cublasCreate(&h);
    const float alpha = 1.0f, beta = 0.0f;

    printf("Matmul %dx%d | media de %d runs + warmup | esperado C[0]=2048\n\n", N, N, R);
    printf("  Kernel  |   tempo    |    throughput   | verifica\n");
    printf("  --------+------------+-----------------+---------\n");

    float msN = bench([&]{ matmulNaive<<<bl, th>>>(dA, dB, dC, N); });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("NAIVE", msN, hC[0]);

    float msT = bench([&]{ matmulTiled<<<bl, th>>>(dA, dB, dC, N); });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("TILED", msT, hC[0]);

    // cuBLAS e column-major; com A,B constantes o resultado (2048) independe do layout
    float msC = bench([&]{
        cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N, &alpha, dA, N, dB, N, &beta, dC, N);
    });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("cuBLAS", msC, hC[0]);

    printf("\n==> TILED  %.2fx vs naive | cuBLAS %.1fx vs naive | cuBLAS %.2fx vs tiled\n",
           msN / msT, msN / msC, msT / msC);

    cublasDestroy(h);
    cudaFree(dA); cudaFree(dB); cudaFree(dC); free(A); free(B); free(hC);
    return 0;
}
