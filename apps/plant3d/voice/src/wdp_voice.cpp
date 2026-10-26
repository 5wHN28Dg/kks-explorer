// wdp_voice: Walkdown Plant's voice codec (decision 0069, docs/plant3d/MULTIPLAYER.md §8): libopus 1.5.2 for the
// codec, SpeexDSP 1.2.1's resampler between Godot's mix rate and Opus's 16 kHz. Two classes for GDScript:
//
//   WdpVoiceEncoder: setup(mix_rate) -> Error; encode(PackedVector2Array) -> PackedByteArray (one 20 ms packet or
//     empty while less than 20 ms is buffered); push_frames / pop_packet / packets_ready for more than one packet at
//     a time; bitrate (16000), expected_loss (per cent, in-band FEC's redundancy); reset().
//   WdpVoiceDecoder: setup(mix_rate) -> Error; decode(packet) -> PackedVector2Array at the mix rate (an empty packet
//     = a lost frame: Opus's loss concealment; a packet that is not 20 ms is refused); decode_fec(next_packet) rebuilds a lost frame from the in-band FEC
//     of the packet after it (concealment when it carries none); reset().
//
// Settings (§8.3): mono, 16 kHz, OPUS_APPLICATION_VOIP, 20 ms frames, 16 kbit/s, complexity 5, in-band FEC, no DTX.
// An instance is used by one thread at a time (the voice worker); two instances are independent.
//
// Everything from GDScript or the network is bounded here: a packet longer than an Opus packet can be is refused
// without being parsed, the encoder buffers at most MAX_PENDING_MS of audio, and a mix rate outside 8–192 kHz is
// refused. Every buffer handed to libopus or the resampler is sized for the call it is used in.

#include <gdextension_interface.h>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <opus.h>
#include <speex_resampler.h>

#include "wdp_core.h"

#include <cstdint>
#include <cstring>
#include <vector>

using namespace godot;

namespace {

constexpr int OPUS_RATE = 16000;                  // wideband (§8.3)
constexpr int FRAME = OPUS_RATE / 50;             // 20 ms = 320 samples
constexpr int MAX_PACKET = WDP_MAX_PACKET;        // our own limit (wdp_core.h): a longer packet is refused unparsed
constexpr int ENCODE_BUFFER = 1276;               // one 20 ms frame's packet: at most 1275 bytes + 1
constexpr int MAX_PENDING_MS = 30000;             // the floor's 30 s limit (§8.4): beyond it the input is dropped
constexpr int MIN_RATE = 8000;
constexpr int MAX_RATE = 192000;

} // namespace

class WdpVoiceEncoder : public RefCounted {
	GDCLASS(WdpVoiceEncoder, RefCounted)

	OpusEncoder *enc = nullptr;
	SpeexResamplerState *rs = nullptr;
	int mix_rate = 0;
	int bitrate = 16000;
	int complexity = 5;
	int expected_loss = 0;
	std::vector<float> pending; // mono, 16 kHz, not yet encoded
	size_t head = 0;            // pending[head:] is still to be encoded
	int64_t dropped = 0;        // samples dropped beyond MAX_PENDING_MS since setup or the last reset

	void free_all() {
		if (enc != nullptr) {
			opus_encoder_destroy(enc);
			enc = nullptr;
		}
		if (rs != nullptr) {
			speex_resampler_destroy(rs);
			rs = nullptr;
		}
		pending.clear();
		head = 0;
		dropped = 0;
		mix_rate = 0;
	}

	void apply_settings() {
		if (enc == nullptr) {
			return;
		}
		opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
		opus_encoder_ctl(enc, OPUS_SET_COMPLEXITY(complexity));
		opus_encoder_ctl(enc, OPUS_SET_INBAND_FEC(1));
		opus_encoder_ctl(enc, OPUS_SET_PACKET_LOSS_PERC(expected_loss));
		opus_encoder_ctl(enc, OPUS_SET_DTX(0));
		opus_encoder_ctl(enc, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
		opus_encoder_ctl(enc, OPUS_SET_MAX_BANDWIDTH(OPUS_BANDWIDTH_WIDEBAND));
	}

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("setup", "mix_rate"), &WdpVoiceEncoder::setup);
		ClassDB::bind_method(D_METHOD("encode", "frames"), &WdpVoiceEncoder::encode);
		ClassDB::bind_method(D_METHOD("push_frames", "frames"), &WdpVoiceEncoder::push_frames);
		ClassDB::bind_method(D_METHOD("pop_packet"), &WdpVoiceEncoder::pop_packet);
		ClassDB::bind_method(D_METHOD("packets_ready"), &WdpVoiceEncoder::packets_ready);
		ClassDB::bind_method(D_METHOD("reset"), &WdpVoiceEncoder::reset);
		ClassDB::bind_method(D_METHOD("set_bitrate", "bits_per_second"), &WdpVoiceEncoder::set_bitrate);
		ClassDB::bind_method(D_METHOD("get_bitrate"), &WdpVoiceEncoder::get_bitrate);
		ClassDB::bind_method(D_METHOD("set_expected_loss", "percent"), &WdpVoiceEncoder::set_expected_loss);
		ClassDB::bind_method(D_METHOD("get_expected_loss"), &WdpVoiceEncoder::get_expected_loss);
		ClassDB::bind_method(D_METHOD("get_lookahead_samples"), &WdpVoiceEncoder::get_lookahead_samples);
		ClassDB::bind_method(D_METHOD("get_dropped_samples"), &WdpVoiceEncoder::get_dropped_samples);
		ClassDB::bind_static_method("WdpVoiceEncoder", D_METHOD("opus_version"), &WdpVoiceEncoder::opus_version);
		ADD_PROPERTY(PropertyInfo(Variant::INT, "bitrate"), "set_bitrate", "get_bitrate");
		ADD_PROPERTY(PropertyInfo(Variant::INT, "expected_loss"), "set_expected_loss", "get_expected_loss");
	}

public:
	~WdpVoiceEncoder() { free_all(); }

	// The input's mix rate (AudioServer.get_input_mix_rate()). OK, or ERR_INVALID_PARAMETER for a rate outside
	// 8–192 kHz, ERR_CANT_CREATE when libopus or the resampler refuse.
	Error setup(int p_mix_rate) {
		free_all();
		if (p_mix_rate < MIN_RATE || p_mix_rate > MAX_RATE) {
			return ERR_INVALID_PARAMETER;
		}
		int err = 0;
		enc = opus_encoder_create(OPUS_RATE, 1, OPUS_APPLICATION_VOIP, &err);
		if (enc == nullptr || err != OPUS_OK) {
			enc = nullptr;
			return ERR_CANT_CREATE;
		}
		if (p_mix_rate != OPUS_RATE) {
			rs = make_resampler(p_mix_rate, OPUS_RATE);
			if (rs == nullptr) {
				free_all();
				return ERR_CANT_CREATE;
			}
		}
		mix_rate = p_mix_rate;
		apply_settings();
		return OK;
	}

	// Takes the mix rate's stereo frames (down-mixed to mono, resampled to 16 kHz) and keeps them until 20 ms are
	// there. Beyond MAX_PENDING_MS of unencoded audio, the rest of the input is dropped (get_dropped_samples).
	void push_frames(const PackedVector2Array &p_frames) {
		if (enc == nullptr) {
			return;
		}
		const int64_t n = p_frames.size();
		if (n <= 0) {
			return;
		}
		const Vector2 *src = p_frames.ptr();
		std::vector<float> mono;
		std::vector<float> out;
		const int64_t chunk = 4096;
		for (int64_t at = 0; at < n; at += chunk) {
			const int64_t m = (n - at) < chunk ? (n - at) : chunk;
			mono.resize((size_t)m);
			for (int64_t i = 0; i < m; i++) {
				mono[(size_t)i] = 0.5f * (src[at + i].x + src[at + i].y);
			}
			out.clear();
			resample(rs, mix_rate, OPUS_RATE, mono.data(), (size_t)m, out);
			const size_t room_total = (size_t)OPUS_RATE * MAX_PENDING_MS / 1000;
			const size_t have = pending.size() - head;
			const size_t room = have >= room_total ? 0 : room_total - have;
			const size_t take = out.size() < room ? out.size() : room;
			dropped += (int64_t)(out.size() - take);
			pending.insert(pending.end(), out.begin(), out.begin() + (std::ptrdiff_t)take);
		}
	}

	int packets_ready() const {
		return enc == nullptr ? 0 : (int)((pending.size() - head) / FRAME);
	}

	// The next 20 ms packet, or an empty array while less than 20 ms is buffered (or on an encoder error).
	PackedByteArray pop_packet() {
		PackedByteArray out;
		if (enc == nullptr || pending.size() - head < (size_t)FRAME) {
			return out;
		}
		unsigned char buf[ENCODE_BUFFER];
		const opus_int32 len = opus_encode_float(enc, pending.data() + head, FRAME, buf, (opus_int32)sizeof(buf));
		head += FRAME;
		if (head >= 16 * FRAME) { // keep the buffer from growing at its front
			pending.erase(pending.begin(), pending.begin() + (std::ptrdiff_t)head);
			head = 0;
		}
		if (len <= 0) {
			return out;
		}
		out.resize(len);
		std::memcpy(out.ptrw(), buf, (size_t)len);
		return out;
	}

	// push_frames, then pop_packet: §8.2's encode(frames) -> packet. Call pop_packet while packets_ready() > 0 when
	// more than 20 ms is pushed at once.
	PackedByteArray encode(const PackedVector2Array &p_frames) {
		push_frames(p_frames);
		return pop_packet();
	}

	// Starts a new talk spurt: the buffered audio, the encoder's and the resampler's history are dropped.
	void reset() {
		pending.clear();
		head = 0;
		dropped = 0;
		if (enc != nullptr) {
			opus_encoder_ctl(enc, OPUS_RESET_STATE);
		}
		if (rs != nullptr) {
			speex_resampler_reset_mem(rs);
			speex_resampler_skip_zeros(rs);
		}
	}

	// 6–64 kbit/s (clamped: our wideband mono voice never needs more).
	void set_bitrate(int p_bps) {
		bitrate = p_bps < 6000 ? 6000 : (p_bps > 64000 ? 64000 : p_bps);
		apply_settings();
	}
	int get_bitrate() const { return bitrate; }

	// The loss the sender expects, 0–100 per cent: the in-band FEC's redundancy follows it (§8.3).
	void set_expected_loss(int p_percent) {
		expected_loss = p_percent < 0 ? 0 : (p_percent > 100 ? 100 : p_percent);
		apply_settings();
	}
	int get_expected_loss() const { return expected_loss; }

	// The encoder's lookahead at 16 kHz (part of the codec's delay), or -1 before setup.
	int get_lookahead_samples() const {
		if (enc == nullptr) {
			return -1;
		}
		opus_int32 la = 0;
		opus_encoder_ctl(enc, OPUS_GET_LOOKAHEAD(&la));
		return (int)la;
	}

	int64_t get_dropped_samples() const { return dropped; }

	static String opus_version() { return String(opus_get_version_string()); }
};

class WdpVoiceDecoder : public RefCounted {
	GDCLASS(WdpVoiceDecoder, RefCounted)

	OpusDecoder *dec = nullptr;
	SpeexResamplerState *rs = nullptr;
	int mix_rate = 0;
	int last_error = 0;

	void free_all() {
		if (dec != nullptr) {
			opus_decoder_destroy(dec);
			dec = nullptr;
		}
		if (rs != nullptr) {
			speex_resampler_destroy(rs);
			rs = nullptr;
		}
		mix_rate = 0;
	}

	// pcm (16 kHz mono, n samples) -> stereo frames at the mix rate
	PackedVector2Array to_frames(const float *pcm, int n) {
		std::vector<float> out;
		out.reserve((size_t)n * (size_t)mix_rate / OPUS_RATE + 64);
		resample(rs, OPUS_RATE, mix_rate, pcm, (size_t)n, out);
		PackedVector2Array frames;
		frames.resize((int64_t)out.size());
		Vector2 *w = frames.ptrw();
		for (size_t i = 0; i < out.size(); i++) {
			w[i] = Vector2(out[i], out[i]);
		}
		return frames;
	}

	PackedVector2Array run(const PackedByteArray &p_packet, int fec) {
		last_error = 0;
		if (dec == nullptr) {
			last_error = OPUS_INVALID_STATE;
			return PackedVector2Array();
		}
		const int64_t len = p_packet.size();
		// at most MAX_PACKET bytes, and exactly 20 ms (wdp_core.h): anything else is refused before libopus decodes it
		if (len > MAX_PACKET || (len > 0 && !wdp_packet_is_20ms(p_packet.ptr(), (int)len))) {
			last_error = OPUS_INVALID_PACKET;
			return PackedVector2Array();
		}
		float pcm[FRAME];
		int n;
		if (len == 0) {
			n = opus_decode_float(dec, nullptr, 0, pcm, FRAME, 0); // concealment for one 20 ms frame
		} else if (fec) {
			// the lost frame is 20 ms (our frame size): FEC needs the exact length of what is missing
			n = opus_decode_float(dec, p_packet.ptr(), (opus_int32)len, pcm, FRAME, 1);
		} else {
			n = opus_decode_float(dec, p_packet.ptr(), (opus_int32)len, pcm, FRAME, 0);
		}
		if (n < 0) {
			last_error = n;
			return PackedVector2Array();
		}
		return to_frames(pcm, n);
	}

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("setup", "mix_rate"), &WdpVoiceDecoder::setup);
		ClassDB::bind_method(D_METHOD("decode", "packet"), &WdpVoiceDecoder::decode);
		ClassDB::bind_method(D_METHOD("decode_fec", "next_packet"), &WdpVoiceDecoder::decode_fec);
		ClassDB::bind_method(D_METHOD("reset"), &WdpVoiceDecoder::reset);
		ClassDB::bind_method(D_METHOD("get_last_error"), &WdpVoiceDecoder::get_last_error);
		ClassDB::bind_static_method("WdpVoiceDecoder", D_METHOD("packet_has_fec", "packet"), &WdpVoiceDecoder::packet_has_fec);
	}

public:
	~WdpVoiceDecoder() { free_all(); }

	// The output's mix rate (AudioServer.get_mix_rate()). OK, ERR_INVALID_PARAMETER or ERR_CANT_CREATE.
	Error setup(int p_mix_rate) {
		free_all();
		if (p_mix_rate < MIN_RATE || p_mix_rate > MAX_RATE) {
			return ERR_INVALID_PARAMETER;
		}
		int err = 0;
		dec = opus_decoder_create(OPUS_RATE, 1, &err);
		if (dec == nullptr || err != OPUS_OK) {
			dec = nullptr;
			return ERR_CANT_CREATE;
		}
		if (p_mix_rate != OPUS_RATE) {
			rs = make_resampler(OPUS_RATE, p_mix_rate);
			if (rs == nullptr) {
				free_all();
				return ERR_CANT_CREATE;
			}
		}
		mix_rate = p_mix_rate;
		return OK;
	}

	// One packet -> its frames at the mix rate; an empty packet is a lost 20 ms frame (concealment). A packet libopus
	// refuses gives an empty array, get_last_error() its Opus error code (play it as lost).
	PackedVector2Array decode(const PackedByteArray &p_packet) { return run(p_packet, 0); }

	// A lost 20 ms frame rebuilt from the in-band FEC of the packet after it (that packet is then decoded normally
	// with decode()). Without FEC data in it, libopus conceals.
	PackedVector2Array decode_fec(const PackedByteArray &p_next_packet) {
		if (p_next_packet.is_empty()) {
			return run(p_next_packet, 0);
		}
		return run(p_next_packet, 1);
	}

	void reset() {
		if (dec != nullptr) {
			opus_decoder_ctl(dec, OPUS_RESET_STATE);
		}
		if (rs != nullptr) {
			speex_resampler_reset_mem(rs);
			speex_resampler_skip_zeros(rs);
		}
	}

	int get_last_error() const { return last_error; }

	// Whether a packet carries in-band FEC for the frame before it (false for anything not a valid packet).
	static bool packet_has_fec(const PackedByteArray &p_packet) {
		const int64_t len = p_packet.size();
		if (len <= 0 || len > MAX_PACKET) {
			return false;
		}
		return wdp_packet_has_fec(p_packet.ptr(), (int)len);
	}
};

namespace {

void initialize_wdp_voice(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WdpVoiceEncoder);
	GDREGISTER_CLASS(WdpVoiceDecoder);
}

void uninitialize_wdp_voice(ModuleInitializationLevel p_level) {
	(void)p_level;
}

} // namespace

extern "C" {
GDExtensionBool GDE_EXPORT wdp_voice_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_wdp_voice);
	init_obj.register_terminator(uninitialize_wdp_voice);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
