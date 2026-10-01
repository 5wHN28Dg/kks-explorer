// QR codes through zxing-cpp (decision 0019): the classic writer (the distro's 2.3 build has no experimental C writer)
// and the reader. Plain C entry points for Nim.
#include <ZXing/MultiFormatWriter.h>
#include <ZXing/BitMatrix.h>
#include <ZXing/ReadBarcode.h>
#include <ZXing/ImageView.h>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C" {

// Modules of a QR code for `text` (UTF-8, byte mode, error correction M): *size × *size bytes, 1 = dark.
// Returns malloc'd memory, NULL on error.
unsigned char *kks_qr_encode(const char *text, int *size)
{
	try {
		ZXing::MultiFormatWriter writer(ZXing::BarcodeFormat::QRCode);
		writer.setEncoding(ZXing::CharacterSet::UTF8).setEccLevel(4).setMargin(0);   // ecc 0..8 scale: 4 ≈ M
		ZXing::BitMatrix m = writer.encode(std::string(text), 0, 0);
		int n = m.width();
		unsigned char *out = (unsigned char *)malloc((size_t)n * n);
		for (int y = 0; y < n; y++)
			for (int x = 0; x < n; x++) out[y * n + x] = m.get(x, y) ? 1 : 0;
		*size = n;
		return out;
	} catch (...) {
		return nullptr;
	}
}

// The text of the first QR code in a grey image, malloc'd; NULL when none was found.
char *kks_qr_decode(const unsigned char *gray, int w, int h)
{
	try {
		ZXing::ImageView img(gray, w, h, ZXing::ImageFormat::Lum);
		ZXing::ReaderOptions opts;
		opts.setFormats(ZXing::BarcodeFormat::QRCode).setTryHarder(true).setTryRotate(true).setTryInvert(true);
		auto r = ZXing::ReadBarcode(img, opts);
		if (!r.isValid()) return nullptr;
		std::string t = r.text();
		char *out = (char *)malloc(t.size() + 1);
		memcpy(out, t.c_str(), t.size() + 1);
		return out;
	} catch (...) {
		return nullptr;
	}
}

}
