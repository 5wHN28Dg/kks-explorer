// wdp_voice's parts that need no Godot, so that the native test (tests/native_test.cpp) runs them under the address
// and undefined-behaviour sanitizers: the packet check done before libopus parses anything from the network, and the
// resampling loop.
#pragma once

#include <opus.h>
#include <speex_resampler.h>

#include <cstddef>
#include <vector>

// Our own limit on a packet's length: libopus takes longer ones (a code-3 packet of 48 frames), our encoder never
// makes one over 1,276 bytes, and a decoder refuses anything over this without parsing it.
#define WDP_MAX_PACKET 3825

// Whether `packet` carries in-band FEC (LBRR) for the frame before it; false for anything not a valid packet.
// libopus 1.5.2's opus_packet_has_lbrr reads the first frame's first byte without checking that the frame has one:
// a SILK packet whose first frame is empty (a 1-byte packet such as 0x08) made it read past the buffer. So the
// packet is parsed here first, and only a first frame of at least one byte goes on to libopus.
static inline bool wdp_packet_has_fec(const unsigned char *packet, int len) {
	if (packet == nullptr || len <= 0 || len > WDP_MAX_PACKET) {
		return false;
	}
	const unsigned char *frames[48];
	opus_int16 size[48];
	const int n = opus_packet_parse(packet, (opus_int32)len, nullptr, frames, size, nullptr);
	if (n <= 0 || size[0] <= 0) {
		return false;
	}
	return opus_packet_has_lbrr(packet, (opus_int32)len) == 1;
}

static constexpr int RESAMPLE_QUALITY = SPEEX_RESAMPLER_QUALITY_VOIP;

// Resamples `in` (mono) into `out` (appended), consuming all of it. The resampler may not take every input sample
// at once, so this loops with an output buffer sized from the ratio.
static inline void resample(SpeexResamplerState *rs, int in_rate, int out_rate, const float *in, size_t n, std::vector<float> &out) {
	if (rs == nullptr) {
		out.insert(out.end(), in, in + n);
		return;
	}
	size_t done = 0;
	float buf[4096];
	while (done < n) {
		spx_uint32_t in_len = (spx_uint32_t)((n - done) > 1024 ? 1024 : (n - done));
		// 1024 input samples at most become 1024 * out_rate / in_rate (+ a few in the filter): ≤ 1024 * 24 + 64
		// for 8 kHz to 192 kHz, more than buf holds, so the output length is also capped at buf's size; the
		// resampler then takes fewer input samples (in_len is updated to what it used)
		spx_uint32_t out_len = (spx_uint32_t)(sizeof(buf) / sizeof(buf[0]));
		if (speex_resampler_process_float(rs, 0, in + done, &in_len, buf, &out_len) != RESAMPLER_ERR_SUCCESS) {
			return;
		}
		out.insert(out.end(), buf, buf + out_len);
		if (in_len == 0 && out_len == 0) {
			return; // (cannot happen with a valid state: never loop for ever)
		}
		done += in_len;
	}
}

static inline SpeexResamplerState *make_resampler(int from, int to) {
	if (from == to) {
		return nullptr;
	}
	int err = 0;
	SpeexResamplerState *rs = speex_resampler_init(1, (spx_uint32_t)from, (spx_uint32_t)to, RESAMPLE_QUALITY, &err);
	if (rs == nullptr || err != RESAMPLER_ERR_SUCCESS) {
		if (rs != nullptr) {
			speex_resampler_destroy(rs);
		}
		return nullptr;
	}
	speex_resampler_skip_zeros(rs);
	return rs;
}

