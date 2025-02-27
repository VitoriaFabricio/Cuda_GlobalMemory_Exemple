#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#define filterWidth 3
#define filterHeight 3

void checkCUDAError(cudaError_t cudaStatus, const char* errorMessage) {
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "%s: %s\n", errorMessage, cudaGetErrorString(cudaStatus));
        exit(1);
    }
}

__global__ void filter(const unsigned int* input_image, unsigned int* output_image, unsigned int height, unsigned int width) {

    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    int filter[filterWidth][filterHeight] = {
        {1, 1, 1},
        {1, 3, 1},
        {1, 1, 1}
    };

    int filter_sum = 0;
    for (int i = 0; i < filterWidth; i++) {
        for (int j = 0; j < filterHeight; j++) {
            filter_sum += filter[i][j];
        }
    }

    int sum = 0;

    if (y == 0 && x == 0) { // Top-left corner
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[(y + 1) * width + (x + 1)] * filter[2][2];
    } else if (y == 0 && x == width - 1) { // Top-right corner
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[(y + 1) * width + (x - 1)] * filter[2][0];
    } else if (y == height - 1 && x == 0) { // Bottom-left corner
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y - 1) * width + (x + 1)] * filter[0][2];
    } else if (y == height - 1 && x == width - 1) { // Bottom-right corner
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y - 1) * width + (x - 1)] * filter[0][0];
    } else if (y == 0) { // Top edge
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[(y + 1) * width + (x - 1)] * filter[2][0];
        sum += input_image[(y + 1) * width + (x + 1)] * filter[2][2];
    } else if (y == height - 1) { // Bottom edge
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y - 1) * width + (x - 1)] * filter[0][0];
        sum += input_image[(y - 1) * width + (x + 1)] * filter[0][2];
    } else if (x == 0) { // Left edge
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y - 1) * width + (x + 1)] * filter[0][2];
        sum += input_image[(y + 1) * width + (x + 1)] * filter[2][2];
    } else if (x == width - 1) { // Right edge
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[(y - 1) * width + (x - 1)] * filter[0][0];
        sum += input_image[(y + 1) * width + (x - 1)] * filter[2][0];
    } else { // Center
        sum += input_image[(y - 1) * width + (x - 1)] * filter[0][0];
        sum += input_image[(y - 1) * width + x] * filter[0][1];
        sum += input_image[(y - 1) * width + (x + 1)] * filter[0][2];
        sum += input_image[y * width + (x - 1)] * filter[1][0];
        sum += input_image[y * width + x] * filter[1][1];
        sum += input_image[y * width + (x + 1)] * filter[1][2];
        sum += input_image[(y + 1) * width + (x - 1)] * filter[2][0];
        sum += input_image[(y + 1) * width + x] * filter[2][1];
        sum += input_image[(y + 1) * width + (x + 1)] * filter[2][2];
    }

    output_image[y * width + x] = sum / filter_sum;
}


int main() {

    // Image size
    unsigned int height = 1024;
    unsigned int width = 1920;
    size_t size = height * width * sizeof(unsigned int);

    // Allocate memory for images on host
    unsigned int* h_input_image = (unsigned int*)malloc(size);
    unsigned int* h_output_image = (unsigned int*)malloc(size);

    if (h_input_image == NULL || h_output_image == NULL) {
        fprintf(stderr, "Failed to allocate host memory.\n");
        exit(1);
    }

    // Initialize input image from file
    FILE* file = fopen("original_0.csv", "r");
    if (file == NULL) {
        fprintf(stderr, "Failed to open input file.\n");
        exit(1);
    }

    char line[10240];
    unsigned int row = 0;

    while (fgets(line, sizeof(line), file) && row < height) {
        char *token;
        unsigned int col = 0;

        token = strtok(line, ",");
        while (token != NULL && col < width) {
            h_input_image[row * width + col] = atoi(token);  // Use atoi to convert string to int
            token = strtok(NULL, ",");
            col++;
        }
        row++;
    }

    fclose(file);

    // Initialize output image
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            h_output_image[i * width + j] = 0;
        }
    }

    // Allocate memory for images on device
    unsigned int* d_input_image;
    unsigned int* d_output_image;
    cudaError_t cudaStatus;

    cudaStatus = cudaMalloc(&d_input_image, size);
    checkCUDAError(cudaStatus, "cudaMalloc failed for input image");

    cudaStatus = cudaMalloc(&d_output_image, size);
    checkCUDAError(cudaStatus, "cudaMalloc failed for output image");

    // Copy input image from host to device
    cudaStatus = cudaMemcpy(d_input_image, h_input_image, size, cudaMemcpyHostToDevice);
    checkCUDAError(cudaStatus, "cudaMemcpy failed from host to device");

    // Define block and grid sizes
    dim3 blockSize(16, 16);
    dim3 gridSize((width + blockSize.x - 1) / blockSize.x, (height + blockSize.y - 1) / blockSize.y);

    // Measure execution time
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    // Start recording
    cudaEventRecord(start);

    // Launch the filter kernel
    filter<<<gridSize, blockSize>>>(d_input_image, d_output_image, height, width);

    cudaStatus = cudaGetLastError();
    checkCUDAError(cudaStatus, "Kernel launch failed");

    // Stop recording
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    // Calculate elapsed time
    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    float microseconds = milliseconds * 1000.0f; // Convert milliseconds to microseconds
    float nanoseconds = microseconds * 1000.0f; // Convert microseconds to nanoseconds
    //printf("Execution time: %f", nanoseconds);

    printf("Execution time: %f nanoseconds\n", nanoseconds);

    // Copy output image from device to host
    cudaStatus = cudaMemcpy(h_output_image, d_output_image, size, cudaMemcpyDeviceToHost);
    checkCUDAError(cudaStatus, "cudaMemcpy failed from device to host");

    // Save output image to CSV file
    FILE* outFile = fopen("result.csv", "w");
    if (outFile == NULL) {
        fprintf(stderr, "Failed to open result file.\n");
        exit(1);
    }

    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            fprintf(outFile, "%d", h_output_image[i * width + j]);
            if (j < width - 1) {
                fprintf(outFile, ",");
            }
        }
        fprintf(outFile, "\n");
    }

    fclose(outFile);

    // Free device memory
    cudaFree(d_input_image);
    cudaFree(d_output_image);

    // Free host memory
    free(h_input_image);
    free(h_output_image);

    return 0;
}
