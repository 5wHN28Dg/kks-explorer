// JPEG XL for the app (photos): encode RGBA pixels at a Butteraugli distance, decode to RGBA. Used by Jxl.kt.
#include <jni.h>
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/thread_parallel_runner.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <cstring>
#include <vector>

namespace {
jbyteArray toJava(JNIEnv* env, const uint8_t* p, size_t n) {
  jbyteArray out = env->NewByteArray((jsize)n);
  if (out) env->SetByteArrayRegion(out, 0, (jsize)n, reinterpret_cast<const jbyte*>(p));
  return out;
}
}  // namespace

// rgba: width*height*4 bytes (Android Bitmap ARGB_8888 memory order R,G,B,A; alpha ignored: photos are opaque).
// -> the JXL codestream, or null on failure.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_kks_explorer_Jxl_encodeRgba(JNIEnv* env, jclass, jbyteArray rgba, jint width, jint height, jfloat distance, jint effort) {
  const size_t px = (size_t)width * (size_t)height;
  if (width <= 0 || height <= 0 || (size_t)env->GetArrayLength(rgba) < px * 4) return nullptr;
  std::vector<uint8_t> rgb(px * 3);
  {
    jbyte* src = env->GetByteArrayElements(rgba, nullptr);
    const uint8_t* s = reinterpret_cast<const uint8_t*>(src);
    for (size_t i = 0; i < px; i++) { rgb[3 * i] = s[4 * i]; rgb[3 * i + 1] = s[4 * i + 1]; rgb[3 * i + 2] = s[4 * i + 2]; }
    env->ReleaseByteArrayElements(rgba, src, JNI_ABORT);
  }
  auto enc = JxlEncoderMake(nullptr);
  auto runner = JxlThreadParallelRunnerMake(nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());
  if (JxlEncoderSetParallelRunner(enc.get(), JxlThreadParallelRunner, runner.get()) != JXL_ENC_SUCCESS) return nullptr;
  JxlBasicInfo info;
  JxlEncoderInitBasicInfo(&info);
  info.xsize = (uint32_t)width;
  info.ysize = (uint32_t)height;
  info.bits_per_sample = 8;
  info.num_color_channels = 3;
  info.alpha_bits = 0;
  info.uses_original_profile = JXL_FALSE;   // lossy: XYB
  if (JxlEncoderSetBasicInfo(enc.get(), &info) != JXL_ENC_SUCCESS) return nullptr;
  JxlColorEncoding color;
  JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
  if (JxlEncoderSetColorEncoding(enc.get(), &color) != JXL_ENC_SUCCESS) return nullptr;
  JxlEncoderFrameSettings* fs = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
  if (JxlEncoderSetFrameDistance(fs, distance) != JXL_ENC_SUCCESS) return nullptr;
  JxlEncoderFrameSettingsSetOption(fs, JXL_ENC_FRAME_SETTING_EFFORT, effort);
  JxlPixelFormat fmt = {3, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
  if (JxlEncoderAddImageFrame(fs, &fmt, rgb.data(), rgb.size()) != JXL_ENC_SUCCESS) return nullptr;
  JxlEncoderCloseInput(enc.get());
  std::vector<uint8_t> out(64 * 1024);
  uint8_t* next = out.data();
  size_t avail = out.size();
  JxlEncoderStatus st;
  while ((st = JxlEncoderProcessOutput(enc.get(), &next, &avail)) == JXL_ENC_NEED_MORE_OUTPUT) {
    size_t used = next - out.data();
    out.resize(out.size() * 2);
    next = out.data() + used;
    avail = out.size() - used;
  }
  if (st != JXL_ENC_SUCCESS) return nullptr;
  return toJava(env, out.data(), next - out.data());
}

// -> RGBA pixels (width*height*4), size in dims[0], dims[1]; null if the data isn't a JXL image this can decode.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_kks_explorer_Jxl_decodeRgba(JNIEnv* env, jclass, jbyteArray data, jintArray dims) {
  const jsize n = env->GetArrayLength(data);
  std::vector<uint8_t> in((size_t)n);
  env->GetByteArrayRegion(data, 0, n, reinterpret_cast<jbyte*>(in.data()));
  auto dec = JxlDecoderMake(nullptr);
  auto runner = JxlThreadParallelRunnerMake(nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());
  if (JxlDecoderSetParallelRunner(dec.get(), JxlThreadParallelRunner, runner.get()) != JXL_DEC_SUCCESS) return nullptr;
  if (JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS) return nullptr;
  JxlDecoderSetInput(dec.get(), in.data(), in.size());
  JxlDecoderCloseInput(dec.get());
  JxlBasicInfo info;
  JxlPixelFormat fmt = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
  std::vector<uint8_t> px;
  for (;;) {
    JxlDecoderStatus st = JxlDecoderProcessInput(dec.get());
    if (st == JXL_DEC_BASIC_INFO) {
      if (JxlDecoderGetBasicInfo(dec.get(), &info) != JXL_DEC_SUCCESS) return nullptr;
      if ((uint64_t)info.xsize * info.ysize > 100000000ull) return nullptr;   // > 100 MP: not a photo of ours
    } else if (st == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
      size_t size = 0;
      if (JxlDecoderImageOutBufferSize(dec.get(), &fmt, &size) != JXL_DEC_SUCCESS) return nullptr;
      px.resize(size);
      if (JxlDecoderSetImageOutBuffer(dec.get(), &fmt, px.data(), px.size()) != JXL_DEC_SUCCESS) return nullptr;
    } else if (st == JXL_DEC_FULL_IMAGE) {
      continue;   // one frame; SUCCESS follows
    } else if (st == JXL_DEC_SUCCESS) {
      break;
    } else {
      return nullptr;   // error, or truncated input
    }
  }
  if (px.empty()) return nullptr;
  jint wh[2] = {(jint)info.xsize, (jint)info.ysize};
  env->SetIntArrayRegion(dims, 0, 2, wh);
  return toJava(env, px.data(), px.size());
}
