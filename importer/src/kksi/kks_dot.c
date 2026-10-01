/* The float32 sums of the Python reader's kNN step, in OpenBLAS 0.3.34's Haswell kernel order (decision 0026):
 *   X @ v   (sgemv_t, sgemv_kernel_4x4): 8 lanes, lane l accumulates a[l], a[l+8], … with FMA; then
 *           lanes j and j+4 added, then (t0+t1)+(t2+t3). The 1–3 rows after the last group of 4 use the SSE
 *           kernels 4x2 / 4x1 (multiply, then add).
 *   v · v   (sdot_kernel_16): 4 × 8 lanes over 32-element blocks with FMA; per accumulator lo+hi halves,
 *           then (u0+u1)+(u2+u3) lane-wise, then (w0+w1)+(w2+w3).
 * fmaf is exact on every CPU; the AVX2 build only makes it fast. */
#pragma GCC optimize("fp-contract=off")   /* the order of operations above is the point: never fuse */
#include <math.h>
#include <stddef.h>

#define KKS_DOT_BODY \
	float acc[8] = {0}; \
	for (size_t i = 0; i < n; i += 8) \
		for (int l = 0; l < 8; l++) acc[l] = fmaf(a[i + l], x[i + l], acc[l]); \
	float t0 = acc[0] + acc[4], t1 = acc[1] + acc[5], t2 = acc[2] + acc[6], t3 = acc[3] + acc[7]; \
	return (t0 + t1) + (t2 + t3);

__attribute__((target("avx2,fma"))) static float dot8_fma(const float *a, const float *x, size_t n) { KKS_DOT_BODY }
static float dot8_plain(const float *a, const float *x, size_t n) { KKS_DOT_BODY }

/* The rows after the last group of 4 (sgemv_kernel_4x2, sgemv_kernel_4x1): SSE, separate multiply and add, no FMA. */
static float dot4x2(const float *a, const float *x, size_t n)
{
	float acc[4] = {0};
	for (size_t i = 0; i < n; i += 4)
		for (int l = 0; l < 4; l++) { float p = a[i + l] * x[i + l]; acc[l] = acc[l] + p; }
	return (acc[0] + acc[1]) + (acc[2] + acc[3]);
}

static float dot4x1(const float *a, const float *x, size_t n)
{
	float acc0[4] = {0}, acc1[4] = {0};
	for (size_t i = 0; i < n; i += 8)
		for (int l = 0; l < 4; l++) {
			float p = a[i + l] * x[i + l], q = a[i + 4 + l] * x[i + 4 + l];
			acc0[l] = acc0[l] + p;
			acc1[l] = acc1[l] + q;
		}
	float t[4];
	for (int l = 0; l < 4; l++) t[l] = acc0[l] + acc1[l];
	return (t[0] + t[1]) + (t[2] + t[3]);
}

/* out[r] = rows[r] · x for r < nrows (single-threaded sgemv_t: groups of 4 rows, then 2, then 1); n % 8 == 0 */
void kks_gemv(const float *rows, size_t nrows, const float *x, size_t n, float *out)
{
	int fast = __builtin_cpu_supports("fma") && __builtin_cpu_supports("avx2");
	size_t r = 0, n4 = nrows & ~(size_t)3;
	for (; r < n4; r++)
		out[r] = fast ? dot8_fma(rows + r * n, x, n) : dot8_plain(rows + r * n, x, n);
	if ((nrows - n4) & 2) {
		out[r] = dot4x2(rows + r * n, x, n); r++;
		out[r] = dot4x2(rows + r * n, x, n); r++;
	}
	if ((nrows - n4) & 1) { out[r] = dot4x1(rows + r * n, x, n); r++; }
}

/* v · v; n is a multiple of 32 */
float kks_sdot(const float *v, size_t n)
{
	float acc[4][8] = {{0}};
	for (size_t i = 0; i < n; i += 32)
		for (int k = 0; k < 4; k++)
			for (int l = 0; l < 8; l++) acc[k][l] = fmaf(v[i + 8 * k + l], v[i + 8 * k + l], acc[k][l]);
	float u[4][4], w[4];
	for (int k = 0; k < 4; k++)
		for (int j = 0; j < 4; j++) u[k][j] = acc[k][j] + acc[k][j + 4];
	for (int j = 0; j < 4; j++) w[j] = (u[0][j] + u[1][j]) + (u[2][j] + u[3][j]);
	return (w[0] + w[1]) + (w[2] + w[3]);
}
