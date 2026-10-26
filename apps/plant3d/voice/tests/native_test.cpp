// wdp_voice's native test (voice/build.sh native-test): the code at the network boundary, built with the address and
// undefined-behaviour sanitizers against the same pinned libopus and resampler, fed what a hostile peer could send.
// Every buffer is allocated at its exact length, so reading one byte past it stops the test.
//   1. wdp_packet_has_fec on every 1- and 2-byte packet and on random ones (libopus 1.5.2's opus_packet_has_lbrr
//      alone read past a 1-byte packet such as 0x08: the check must parse first);
//   2. opus_decode_float, as wdp_voice calls it (a 120 ms buffer, then 20 ms for FEC and concealment), on random
//      packets up to WDP_MAX_PACKET;
//   3. the resampling loop between 8 and 192 kHz both ways, inputs of 0 to 20,000 samples: the output length is
//      what the ratio says, give or take the filter.
// Exits 0 when all pass; the sanitizers abort on a fault.
#include "../src/wdp_core.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <random>

static int failures = 0;
#define CHECK(c, ...) do { if (!(c)) { std::fprintf(stderr, "FAIL: " __VA_ARGS__); std::fprintf(stderr, "\n"); failures++; } } while (0)

static bool has_fec_exact(const unsigned char *bytes, int len) {
	// a heap copy of exactly len bytes: an over-read hits the sanitizer's red zone
	std::unique_ptr<unsigned char[]> p(new unsigned char[len]);
	std::memcpy(p.get(), bytes, (size_t)len);
	return wdp_packet_has_fec(p.get(), len);
}

int main() {
	// 1. the FEC check on short and random packets
	for (int a = 0; a < 256; a++) {
		unsigned char b1[1] = {(unsigned char)a};
		has_fec_exact(b1, 1);
		for (int b = 0; b < 256; b++) {
			unsigned char b2[2] = {(unsigned char)a, (unsigned char)b};
			has_fec_exact(b2, 2);
		}
	}
	CHECK(!wdp_packet_has_fec(nullptr, 3), "a null packet has FEC");
	unsigned char empty_silk[1] = {0x08};
	CHECK(!has_fec_exact(empty_silk, 1), "a SILK packet with an empty frame has FEC");
	// only 20 ms packets are decoded: SILK NB 20 ms yes; 10 ms, 60 ms, and a code-3 packet of 6 x 20 ms no
	unsigned char p20[1] = {0x08}, p10[1] = {0x00}, p60[1] = {0x18}, p120[2] = {0x0B, 0x06};
	CHECK(wdp_packet_is_20ms(p20, 1), "a 20 ms packet refused");
	CHECK(!wdp_packet_is_20ms(p10, 1) && !wdp_packet_is_20ms(p60, 1) && !wdp_packet_is_20ms(p120, 2),
	      "a packet of 10, 60 or 120 ms taken");
	std::mt19937 rng(2026);
	for (int k = 0; k < 20000; k++) {
		int len = 1 + (int)(rng() % 64);
		std::unique_ptr<unsigned char[]> p(new unsigned char[len]);
		for (int i = 0; i < len; i++) p[i] = (unsigned char)rng();
		wdp_packet_has_fec(p.get(), len);
		wdp_packet_is_20ms(p.get(), len);
	}

	// 2. decoding hostile packets as wdp_voice does
	int err = 0;
	OpusDecoder *dec = opus_decoder_create(16000, 1, &err);
	CHECK(dec != nullptr && err == OPUS_OK, "no decoder");
	float pcm[16000 * 120 / 1000];
	for (int k = 0; k < 20000; k++) {
		int len = 1 + (int)(rng() % (k % 50 == 0 ? WDP_MAX_PACKET : 300));
		std::unique_ptr<unsigned char[]> p(new unsigned char[len]);
		for (int i = 0; i < len; i++) p[i] = (unsigned char)rng();
		int mode = k % 3;
		int n = opus_decode_float(dec, p.get(), len, pcm, mode == 0 ? 1920 : 320, mode == 1 ? 1 : 0);
		CHECK(n <= (mode == 0 ? 1920 : 320), "decoded %d samples into a smaller buffer", n);
		if (mode == 2) {
			n = opus_decode_float(dec, nullptr, 0, pcm, 320, 0);
			CHECK(n == 320, "concealment gave %d samples", n);
		}
		for (int i = 0; i < n; i++) {
			if (!std::isfinite(pcm[i])) {
				CHECK(false, "a sample is not finite");
				break;
			}
		}
	}
	opus_decoder_destroy(dec);

	// 3. the resampling loop
	const int rates[] = {8000, 16000, 22050, 44100, 48000, 96000, 192000};
	for (int from : rates) {
		for (int to : {16000, 44100, 48000, 8000, 192000}) {
			for (int n : {0, 1, 7, 320, 1023, 1024, 1025, 4096, 20000}) {
				SpeexResamplerState *rs = make_resampler(from, to);
				CHECK((rs == nullptr) == (from == to), "resampler %d -> %d", from, to);
				std::unique_ptr<float[]> in(new float[n > 0 ? n : 1]);
				for (int i = 0; i < n; i++) in[i] = std::sin(0.01f * (float)i);
				std::vector<float> out;
				resample(rs, from, to, in.get(), (size_t)n, out);
				double want = (double)n * to / from;
				// the filter's delay (skipped at the start) shortens the output by up to its length
				CHECK(std::fabs((double)out.size() - want) <= 64.0 * to / from + 64.0 || n < 64,
				      "%d -> %d, %d in: %zu out (%.0f expected)", from, to, n, out.size(), want);
				if (rs != nullptr) speex_resampler_destroy(rs);
			}
		}
	}
	std::printf("wdp_voice native test: %s\n", failures ? "FAILED" : "all passed");
	return failures ? 1 : 0;
}
