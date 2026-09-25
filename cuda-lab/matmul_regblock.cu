// matmul_regblock.cu — HPC: REGISTER BLOCKING (a tecnica que aproxima do cuBLAS)
// Compara: TILED (1 saida/thread) -> REGBLOCK (16 saidas/thread) -> cuBLAS
// Diagnostico do Nsight: tiled era MIO-bound (muitas leituras de shared memory).
// Register blocking carrega vetores de A e B em REGISTRADORES e os reutiliza
// num produto externo -> menos loads de shared -> desafoga o pipe MIO.
// Compilar:  nvcc -arch=sm_86 matmul_regblock.cu -lcublas -o matmul_regblock.exe

#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <cublas_v2.h>

#define N    1024
#define R    30          // repeticoes p/ media (benchmarking decente)

// ---------- Kernel TILED simples (referencia, 1 saida por thread) ----------
#define TILE 16
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

// ---------- Kernel REGISTER BLOCKING ----------
// Cada BLOCO calcula um tile BM x BN de C. Cada THREAD calcula TM x TN saidas.
#define BM 64
#define BN 64
#define BK 8
#define TM 4
#define TN 4
// threads por bloco = (BM/TM) * (BN/TN) = 16 * 16 = 256

__global__ void matmulRegBlock(const float *A, const float *B, float *C, int n) {
    int cRow = blockIdx.y;   // qual faixa de linhas (BM) este bloco cobre
    int cCol = blockIdx.x;   // qual faixa de colunas (BN) este bloco cobre

    __shared__ float As[BM * BK];   // tile de A na shared (64x8)
    __shared__ float Bs[BK * BN];   // tile de B na shared (8x64)

    // Posicao desta thread DENTRO do tile de saida (grade 16x16 de threads)
    int threadRow = threadIdx.x / (BN / TN);   // 0..15
    int threadCol = threadIdx.x % (BN / TN);   // 0..15

    // Acumuladores em REGISTRADORES: o micro-tile TM x TN desta thread
    float acc[TM * TN] = {0.0f};
    float regM[TM];   // pedaco de uma coluna de A (registradores)
    float regN[TN];   // pedaco de uma linha  de B (registradores)

    // Indices para CARREGAR os tiles para a shared (cada thread carrega 2 elementos)
    int innerRowA = threadIdx.x / BK, innerColA = threadIdx.x % BK; // p/ As (64x8)
    int innerRowB = threadIdx.x / BN, innerColB = threadIdx.x % BN; // p/ Bs (8x64)

    // Percorre K em passos de BK
    for (int bk = 0; bk < n; bk += BK) {
        // Carrega tile de A (BM x BK = 512 elem / 256 threads = 2 cada)
        for (int off = 0; off < BM; off += 32)
            As[(innerRowA + off) * BK + innerColA] =
                A[(cRow * BM + innerRowA + off) * n + bk + innerColA];
        // Carrega tile de B (BK x BN = 512 elem / 256 threads = 2 cada)
        for (int off = 0; off < BK; off += 4)
            Bs[(innerRowB + off) * BN + innerColB] =
                B[(bk + innerRowB + off) * n + cCol * BN + innerColB];
        __syncthreads();

        // Produto externo: para cada passo do dot-product...
        for (int d = 0; d < BK; d++) {
            // ...carrega TM valores de A e TN de B em REGISTRADORES (1 vez)
            for (int i = 0; i < TM; i++) regM[i] = As[(threadRow * TM + i) * BK + d];
            for (int j = 0; j < TN; j++) regN[j] = Bs[d * BN + threadCol * TN + j];
            // ...e os reutiliza em TM x TN FMAs (cada valor usado TN/TM vezes)
            for (int i = 0; i < TM; i++)
                for (int j = 0; j < TN; j++)
                    acc[i * TN + j] += regM[i] * regN[j];
        }
        __syncthreads();
    }

    // Escreve o micro-tile de volta em C
    for (int i = 0; i < TM; i++)
        for (int j = 0; j < TN; j++) {
            int row = cRow * BM + threadRow * TM + i;
            int col = cCol * BN + threadCol * TN + j;
            C[row * n + col] = acc[i * TN + j];
        }
}

template <typename F>
static float bench(F launch) {
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    launch(); cudaDeviceSynchronize();              // warmup
    cudaEventRecord(a);
    for (int i = 0; i < R; i++) launch();
    cudaEventRecord(b); cudaEventSynchronize(b);
    float ms = 0; cudaEventElapsedTime(&ms, a, b);
    cudaEventDestroy(a); cudaEventDestroy(b);
    return ms / R;
}

static void report(const char *nome, float ms, float c0) {
    double gflops = (2.0 * N * N * N) / (ms / 1000.0) / 1.0e9;
    double pico = 8867.0; // ~pico FP32 da RTX 3050
    printf("  %-9s | %7.3f ms | %9.1f GFLOP/s | %4.1f%% do pico | C[0]=%.0f\n",
           nome, ms, gflops, 100.0 * gflops / pico, c0);
}

int main() {
    size_t bytes = (size_t)N * N * sizeof(float);
    float *A = (float *)malloc(bytes), *B = (float *)malloc(bytes), *hC = (float *)malloc(bytes);
    for (int i = 0; i < N * N; i++) { A[i] = 1.0f; B[i] = 2.0f; } // esperado 2*N = 2048

    float *dA, *dB, *dC;
    cudaMalloc(&dA, bytes); cudaMalloc(&dB, bytes); cudaMalloc(&dC, bytes);
    cudaMemcpy(dA, A, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(dB, B, bytes, cudaMemcpyHostToDevice);

    cublasHandle_t h; cublasCreate(&h);
    const float alpha = 1.0f, beta = 0.0f;

    printf("Matmul %dx%d | media de %d runs | esperado C[0]=2048\n\n", N, N, R);
    printf("  Kernel    |   tempo    |    throughput   |   eficiencia | verifica\n");
    printf("  ----------+------------+-----------------+--------------+---------\n");

    dim3 thT(TILE, TILE), blT(N / TILE, N / TILE);
    float msT = bench([&]{ matmulTiled<<<blT, thT>>>(dA, dB, dC, N); });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("TILED", msT, hC[0]);

    dim3 thR(256), blR(N / BN, N / BM);
    float msR = bench([&]{ matmulRegBlock<<<blR, thR>>>(dA, dB, dC, N); });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("REGBLOCK", msR, hC[0]);

    float msC = bench([&]{
        cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N, &alpha, dA, N, dB, N, &beta, dC, N);
    });
    cudaMemcpy(hC, dC, bytes, cudaMemcpyDeviceToHost); report("cuBLAS", msC, hC[0]);

    printf("\n==> REGBLOCK %.2fx vs tiled | cuBLAS %.2fx vs regblock\n", msT / msR, msR / msC);

    cublasDestroy(h);
    cudaFree(dA); cudaFree(dB); cudaFree(dC); free(A); free(B); free(hC);
    return 0;
}
