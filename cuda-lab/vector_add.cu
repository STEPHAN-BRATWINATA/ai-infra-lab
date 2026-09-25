// vector_add.cu — Primeiro "Hello GPU" em CUDA
// Soma dois vetores (C = A + B) usando a GPU NVIDIA (RTX 3050).
// Compilar:  nvcc vector_add.cu -o vector_add.exe
// Rodar:     .\vector_add.exe

#include <cstdio>
#include <cuda_runtime.h>

// Macro simples pra checar erros de chamadas CUDA
#define CUDA_OK(call)                                                      \
    do {                                                                   \
        cudaError_t _e = (call);                                           \
        if (_e != cudaSuccess) {                                           \
            printf("Erro CUDA em %s:%d -> %s\n", __FILE__, __LINE__,       \
                   cudaGetErrorString(_e));                                \
            return 1;                                                      \
        }                                                                  \
    } while (0)

// KERNEL: roda na GPU. Cada thread soma um elemento do vetor.
__global__ void vectorAdd(const float *A, const float *B, float *C, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;  // índice global da thread
    if (i < n) {
        C[i] = A[i] + B[i];
    }
}

int main() {
    // --- 1) Mostra qual GPU está sendo usada ---
    int dev = 0;
    cudaDeviceProp prop;
    CUDA_OK(cudaGetDeviceProperties(&prop, dev));
    printf("GPU em uso: %s (compute capability %d.%d, %zu MB)\n",
           prop.name, prop.major, prop.minor,
           prop.totalGlobalMem / (1024 * 1024));

    // --- 2) Prepara os dados na CPU (host) ---
    const int N = 1 << 20;                 // 1.048.576 elementos
    const size_t bytes = N * sizeof(float);
    float *h_A = (float *)malloc(bytes);
    float *h_B = (float *)malloc(bytes);
    float *h_C = (float *)malloc(bytes);
    for (int i = 0; i < N; i++) {
        h_A[i] = 1.0f;                     // tudo 1
        h_B[i] = 2.0f;                     // tudo 2  -> esperado: C = 3
    }

    // --- 3) Aloca memória na GPU (device) e copia os dados ---
    float *d_A, *d_B, *d_C;
    CUDA_OK(cudaMalloc(&d_A, bytes));
    CUDA_OK(cudaMalloc(&d_B, bytes));
    CUDA_OK(cudaMalloc(&d_C, bytes));
    CUDA_OK(cudaMemcpy(d_A, h_A, bytes, cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemcpy(d_B, h_B, bytes, cudaMemcpyHostToDevice));

    // --- 4) Lança o kernel na GPU ---
    int threadsPerBlock = 256;
    int blocks = (N + threadsPerBlock - 1) / threadsPerBlock;
    vectorAdd<<<blocks, threadsPerBlock>>>(d_A, d_B, d_C, N);
    CUDA_OK(cudaGetLastError());           // erro de lançamento?
    CUDA_OK(cudaDeviceSynchronize());      // espera a GPU terminar

    // --- 5) Traz o resultado de volta pra CPU e verifica ---
    CUDA_OK(cudaMemcpy(h_C, d_C, bytes, cudaMemcpyDeviceToHost));
    bool ok = true;
    for (int i = 0; i < N; i++) {
        if (h_C[i] != 3.0f) { ok = false; break; }
    }
    printf("Resultado: C[0]=%.1f, C[%d]=%.1f -> %s\n",
           h_C[0], N - 1, h_C[N - 1],
           ok ? "CORRETO (a GPU somou os vetores!)" : "ERRADO");

    // --- 6) Libera memória ---
    cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
    free(h_A); free(h_B); free(h_C);
    return ok ? 0 : 1;
}
