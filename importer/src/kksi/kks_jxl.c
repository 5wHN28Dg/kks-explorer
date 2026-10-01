/* Lossless JPEG XL for the path store's images (docs/PATHSTORE.md), over libjxl (decision 0019). */
#include <jxl/encode.h>
#include <jxl/decode.h>
#include <jxl/thread_parallel_runner.h>
#include <stdlib.h>
#include <string.h>

/* RGB (n=3) or RGBA (n=4), 8 bit, sRGB. distance 0 = lossless, else the Butteraugli distance (photos: 1.9, the
   user's choice 2026-09-27). Returns malloc'd bytes (*len), NULL on error. */
unsigned char *kks_jxl_encode_d(const unsigned char *pixels, int w, int h, int n, int effort, float distance, size_t *len);
unsigned char *kks_jxl_encode(const unsigned char *pixels, int w, int h, int n, int effort, size_t *len)
{
	return kks_jxl_encode_d(pixels, w, h, n, effort, 0, len);
}

unsigned char *kks_jxl_encode_d(const unsigned char *pixels, int w, int h, int n, int effort, float distance, size_t *len)
{
	JxlEncoder *enc = JxlEncoderCreate(NULL);
	unsigned char *out = NULL;
	if (!enc) return NULL;
	/* libjxl's own thread pool: the output does not depend on the thread count */
	void *runner = JxlThreadParallelRunnerCreate(NULL, JxlThreadParallelRunnerDefaultNumWorkerThreads());
	if (runner) JxlEncoderSetParallelRunner(enc, JxlThreadParallelRunner, runner);
	JxlBasicInfo info;
	JxlEncoderInitBasicInfo(&info);
	info.xsize = w; info.ysize = h;
	info.bits_per_sample = 8;
	info.num_color_channels = 3;
	info.num_extra_channels = n == 4 ? 1 : 0;
	info.alpha_bits = n == 4 ? 8 : 0;
	info.uses_original_profile = distance == 0 ? JXL_TRUE : JXL_FALSE;   /* lossless needs the original profile */
	JxlColorEncoding ce;
	JxlColorEncodingSetToSRGB(&ce, JXL_FALSE);
	JxlPixelFormat pf = {(uint32_t)n, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
	JxlEncoderFrameSettings *fs;
	if (JxlEncoderSetBasicInfo(enc, &info) != JXL_ENC_SUCCESS) goto fail;
	if (JxlEncoderSetColorEncoding(enc, &ce) != JXL_ENC_SUCCESS) goto fail;
	fs = JxlEncoderFrameSettingsCreate(enc, NULL);
	if (distance == 0) {
		if (JxlEncoderSetFrameLossless(fs, JXL_TRUE) != JXL_ENC_SUCCESS) goto fail;
	} else if (JxlEncoderSetFrameDistance(fs, distance) != JXL_ENC_SUCCESS) goto fail;
	if (JxlEncoderFrameSettingsSetOption(fs, JXL_ENC_FRAME_SETTING_EFFORT, effort) != JXL_ENC_SUCCESS) goto fail;
	if (JxlEncoderAddImageFrame(fs, &pf, pixels, (size_t)w * h * n) != JXL_ENC_SUCCESS) goto fail;
	JxlEncoderCloseInput(enc);
	size_t cap = 4096, used = 0;
	out = malloc(cap);
	for (;;) {
		uint8_t *next = out + used;
		size_t avail = cap - used;
		JxlEncoderStatus st = JxlEncoderProcessOutput(enc, &next, &avail);
		used = next - out;
		if (st == JXL_ENC_SUCCESS) break;
		if (st != JXL_ENC_NEED_MORE_OUTPUT) goto fail;
		cap *= 2;
		out = realloc(out, cap);
	}
	JxlEncoderDestroy(enc);
	if (runner) JxlThreadParallelRunnerDestroy(runner);
	*len = used;
	return out;
fail:
	free(out);
	JxlEncoderDestroy(enc);
	if (runner) JxlThreadParallelRunnerDestroy(runner);
	return NULL;
}

/* Decode to RGBA 8 bit (tests, viewers). *w, *h set; returns malloc'd w*h*4 bytes or NULL. */
unsigned char *kks_jxl_decode(const unsigned char *data, size_t len, int *w, int *h, int *has_alpha)
{
	JxlDecoder *dec = JxlDecoderCreate(NULL);
	unsigned char *pix = NULL;
	if (!dec) return NULL;
	void *runner = JxlThreadParallelRunnerCreate(NULL, JxlThreadParallelRunnerDefaultNumWorkerThreads());
	if (runner) JxlDecoderSetParallelRunner(dec, JxlThreadParallelRunner, runner);
	if (JxlDecoderSubscribeEvents(dec, JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS) goto fail;
	JxlDecoderSetInput(dec, data, len);
	JxlDecoderCloseInput(dec);
	JxlPixelFormat pf = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
	for (;;) {
		JxlDecoderStatus st = JxlDecoderProcessInput(dec);
		if (st == JXL_DEC_BASIC_INFO) {
			JxlBasicInfo info;
			if (JxlDecoderGetBasicInfo(dec, &info) != JXL_DEC_SUCCESS) goto fail;
			*w = info.xsize; *h = info.ysize; *has_alpha = info.alpha_bits > 0;
		} else if (st == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
			size_t sz;
			if (JxlDecoderImageOutBufferSize(dec, &pf, &sz) != JXL_DEC_SUCCESS) goto fail;
			pix = malloc(sz);
			if (JxlDecoderSetImageOutBuffer(dec, &pf, pix, sz) != JXL_DEC_SUCCESS) goto fail;
		} else if (st == JXL_DEC_FULL_IMAGE) {
			continue;
		} else if (st == JXL_DEC_SUCCESS) {
			break;
		} else goto fail;
	}
	JxlDecoderDestroy(dec);
	if (runner) JxlThreadParallelRunnerDestroy(runner);
	return pix;
fail:
	free(pix);
	JxlDecoderDestroy(dec);
	if (runner) JxlThreadParallelRunnerDestroy(runner);
	return NULL;
}
