// matmul.cu — Multiplicacao de matrizes: CPU vs GPU (com tempo e speedup)
// Mostra na pratica o ganho da GPU em trabalho paralelo.
// Compilar/rodar:  build.bat matmul.cu
//
// Conceito-chave: cada elemento C[i][j] e independente -> a GPU calcula
// milhares deles ao mesmo tempo (1 thread por elemento), enquanto a CPU
// faz um de cada vez (3 lacos aninhados).

#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <cuda_runtime.h>

#define N 1024                 // matrizes N x N
#define TILE 16                // bloco de 16x16 threads

// ---- Kernel GPU: cada thread calcula UM elemento de C ----
__global__ void matmulGPU(const float *A, const float *B, float *C, int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (row < n && col < n) {
        float soma = 0.0f;
        for (int k = 0; k < n; k++)
            soma += A[row * n + k] * B[k * n + col];
        C[row * n + col] = soma;
    }
}

// ---- Versao CPU (referencia): 3 lacos aninhados, um elemento por vez ----
void matmulCPU(const float *A, const float *B, float *C, int n) {
    for (int row = 0; row < n; row++)
        for (int col = 0; col < n; col++) {
            float soma = 0.0f;
            for (int k = 0; k < n; k++)
                soma += A[row * n + k] * B[k * n + col];
            C[row * n + col] = soma;
        }
}

int main() {
    size_t bytes = (size_t)N * N * sizeof(float);
    float *A = (float *)malloc(bytes);
    float *B = (float *)malloc(bytes);
    float *C_cpu = (float *)malloc(bytes);
    float *C_gpu = (float *)malloc(bytes);

    // Dados de teste
    for (int i = 0; i < N * N; i++) { A[i] = 1.0f; B[i] = 2.0f; }
    // Esperado: cada C[i][j] = soma de N (1*2) = 2*N = 2048

    printf("Multiplicando matrizes %d x %d (%d elementos por matriz)\n\n", N, N, N * N);

    // ---------- CPU ----------
    auto t0 = std::chrono::high_resolution_clock::now();
    matmulCPU(A, B, C_cpu, N);
    auto t1 = std::chrono::high_resolution_clock::now();
    double msCPU = std::chrono::duration<double, std::milli>(t1 - t0).count();
    printf("CPU : %.1f ms\n", msCPU);

    // ---------- GPU ----------
    float *dA, *dB, *dC;
    cudaMalloc(&dA, bytes); cudaMalloc(&dB, bytes); cudaMalloc(&dC, bytes);
    cudaMemcpy(dA, A, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(dB, B, bytes, cudaMemcpyHostToDevice);

    dim3 threads(TILE, TILE);
    dim3 blocks((N + TILE - 1) / TILE, (N + TILE - 1) / TILE);

    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    cudaEventRecord(a);
    matmulGPU<<<blocks, threads>>>(dA, dB, dC, N);
    cudaEventRecord(b);
    cudaEventSynchronize(b);
    float msGPU = 0; cudaEventElapsedTime(&msGPU, a, b);

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) { printf("Erro CUDA: %s\n", cudaGetErrorString(err)); return 1; }

    cudaMemcpy(C_gpu, dC, bytes, cudaMemcpyDeviceToHost);
    printf("GPU : %.1f ms  (so o calculo do kernel)\n", msGPU);

    // ---------- Verificacao ----------
    bool ok = true;
    for (int i = 0; i < N * N; i++)
        if (C_cpu[i] != C_gpu[i]) { ok = false; break; }
    printf("\nResultado igual ao da CPU? %s (C[0]=%.0f, esperado %d)\n",
           ok ? "SIM" : "NAO", C_gpu[0], 2 * N);

    if (msGPU > 0)
        printf("==> SPEEDUP: a GPU foi %.1fx mais rapida que a CPU\n", msCPU / msGPU);

    cudaEventDestroy(a); cudaEventDestroy(b);
    cudaFree(dA); cudaFree(dB); cudaFree(dC);
    free(A); free(B); free(C_cpu); free(C_gpu);
    return ok ? 0 : 1;
}
