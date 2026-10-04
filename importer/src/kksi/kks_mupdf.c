/*
 * The importer's MuPDF layer (decision 0026). It reproduces exactly what the Python importer did through PyMuPDF 1.28.2,
 * so that the glyph images, and with them the readings, stay identical:
 *   - kks_rotated_copy: PyMuPDF's Page.show_pdf_page() onto a new page (extractor/orient.py rotated_copy), saved and
 *     reopened as PyMuPDF's Document.save() would write it;
 *   - kks_render_gray: Page.get_pixmap(dpi=…, clip=…, colorspace=csGRAY) (a display list, then a draw device over the
 *     rounded clip), with fz_set_graphics_min_line_width as TOOLS.set_graphics_min_line_width;
 *   - kks_drawings: Page.get_drawings() as far as the reader uses it, from PyMuPDF's line-art device (src/extra.i at
 *     tag 1.28.2: jm_lineart_*, trace_*, jm_checkrect, jm_checkquad, jm_append_merge), with C structs instead of Python
 *     dicts. PyMuPDF is AGPL-3.0, like this project.
 * The matrix arithmetic mirrors PyMuPDF's mix of Python doubles and MuPDF float functions step by step.
 */
#include <mupdf/fitz.h>
#include <mupdf/pdf.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static fz_context *g_ctx;
static char g_error[512];

const char *kks_error(void) { return g_error; }

int kks_init(void)
{
	if (g_ctx) return 1;
	g_ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
	if (!g_ctx) return 0;
	fz_register_document_handlers(g_ctx);
	return 1;
}

/* ---------------------------------------------------------------- PyMuPDF arithmetic */

typedef struct { double a, b, c, d, e, f; } dmat;   /* a PyMuPDF Matrix: Python floats */
typedef struct { double x0, y0, x1, y1; } drect;    /* a PyMuPDF Rect */

static fz_matrix to_fz(dmat m) { return fz_make_matrix((float)m.a, (float)m.b, (float)m.c, (float)m.d, (float)m.e, (float)m.f); }
static dmat from_fz(fz_matrix m) { dmat r = {m.a, m.b, m.c, m.d, m.e, m.f}; return r; }
static fz_rect rect_to_fz(drect r) { return fz_make_rect((float)r.x0, (float)r.y0, (float)r.x1, (float)r.y1); }
static drect rect_from_fz(fz_rect r) { drect d = {r.x0, r.y0, r.x1, r.y1}; return d; }

static dmat concat(dmat m1, dmat m2) { return from_fz(fz_concat(to_fz(m1), to_fz(m2))); }   /* util_concat_matrix */
static drect rect_mul(drect r, dmat m) { return rect_from_fz(fz_transform_rect(rect_to_fz(r), to_fz(m))); }   /* util_transform_rect */

static dmat invert(dmat m0)   /* util_invert_matrix (Python): doubles in, float fields out */
{
	fz_matrix src = to_fz(m0);
	double a = src.a;
	double det = a * src.d - (double)src.b * src.c;
	fz_matrix dst = fz_identity;
	if (det < -2.220446049250313e-16 || det > 2.220446049250313e-16) {
		double rdet = 1 / det;
		dst.a = (float)(src.d * rdet);
		dst.b = (float)(-src.b * rdet);
		dst.c = (float)(-src.c * rdet);
		dst.d = (float)(a * rdet);
		a = -src.e * (double)dst.a - src.f * (double)dst.c;
		dst.f = (float)(-src.e * (double)dst.b - src.f * (double)dst.d);
		dst.e = (float)a;
	}
	return from_fz(dst);
}

static dmat rotate_deg(int deg)   /* Matrix(degree): cos/sin rounded to 8 digits */
{
	double theta = deg * 3.141592653589793 / 180.0;   /* math.radians */
	double c = round(cos(theta) * 1e8) / 1e8, s = round(sin(theta) * 1e8) / 1e8;
	dmat m = {c, s, -s, c, 0, 0};
	return m;
}

static double width(drect r) { return fabs(r.x1 - r.x0); }
static double height(drect r) { return fabs(r.y1 - r.y0); }

static dmat page_transformation_matrix(pdf_page *page)   /* Page.transformation_matrix for rotation 0 */
{
	fz_rect mediabox = fz_unit_rect;
	fz_matrix ctm = fz_identity;
	pdf_page_transform(g_ctx, page, &mediabox, &ctm);
	return from_fz(ctm);
}

/* ---------------------------------------------------------------- rotated_copy (orient.py) */

static fz_buffer *read_contents(pdf_obj *pageref)   /* JM_read_contents */
{
	pdf_obj *contents = pdf_dict_get(g_ctx, pageref, PDF_NAME(Contents));
	if (pdf_is_array(g_ctx, contents)) {
		fz_buffer *res = fz_new_buffer(g_ctx, 1024);
		for (int i = 0; i < pdf_array_len(g_ctx, contents); i++) {
			if (i > 0) fz_append_byte(g_ctx, res, 32);
			pdf_obj *obj = pdf_array_get(g_ctx, contents, i);
			if (pdf_is_stream(g_ctx, obj)) {
				fz_buffer *n = pdf_load_stream(g_ctx, obj);
				fz_append_buffer(g_ctx, res, n);
				fz_drop_buffer(g_ctx, n);
			}
		}
		return res;
	}
	if (contents) return pdf_load_stream(g_ctx, contents);
	return fz_new_buffer(g_ctx, 0);
}

static void update_stream(pdf_document *doc, pdf_obj *obj, fz_buffer *buf)
{
	/* PyMuPDF deflates the stream when that is smaller; the content parser decodes it back to the same bytes, so the
	   rendering can't differ: stored as it is here. */
	pdf_update_stream(g_ctx, doc, obj, buf, 0);
}

/* Returns a new document (the saved-and-reopened copy) or NULL; kks_error() says why. */
fz_document *kks_rotated_copy(const char *src, int extra)
{
	fz_document *result = NULL;
	pdf_document *s = NULL, *d = NULL;
	pdf_graft_map *gmap = NULL;
	fz_buffer *out = NULL;
	fz_var(result); fz_var(s); fz_var(d); fz_var(gmap); fz_var(out);
	fz_try(g_ctx) {
		s = pdf_open_document(g_ctx, src);
		pdf_page *sp = pdf_load_page(g_ctx, s, 0);
		pdf_dict_put_int(g_ctx, sp->obj, PDF_NAME(Rotate), 0);   /* s[0].set_rotation(0) */
		fz_drop_page(g_ctx, (fz_page *)sp);
		sp = pdf_load_page(g_ctx, s, 0);
		drect r = rect_from_fz(fz_bound_page(g_ctx, (fz_page *)sp));   /* s[0].rect */
		double W = (extra == 0 || extra == 180) ? width(r) : height(r);
		double H = (extra == 0 || extra == 180) ? height(r) : width(r);

		d = pdf_create_document(g_ctx);   /* pymupdf.open() + new_page(width=W, height=H) */
		fz_rect mb = fz_unit_rect;
		mb.x1 = (float)W; mb.y1 = (float)H;
		pdf_obj *resources = pdf_add_new_dict(g_ctx, d, 1);
		fz_buffer *contents = fz_new_buffer(g_ctx, 0);
		pdf_obj *page_obj = pdf_add_page(g_ctx, d, mb, 0, resources, contents);
		pdf_insert_page(g_ctx, d, -1, page_obj);
		pdf_drop_obj(g_ctx, page_obj);
		pdf_drop_obj(g_ctx, resources);
		fz_drop_buffer(g_ctx, contents);
		pdf_page *tp = pdf_load_page(g_ctx, d, 0);

		/* show_pdf_page(p.rect, s, 0, rotate=extra, keep_proportion=True) */
		drect prect = rect_from_fz(fz_bound_page(g_ctx, (fz_page *)tp));
		drect tar = rect_mul(prect, invert(page_transformation_matrix(tp)));
		drect sr = rect_mul(r, invert(page_transformation_matrix(sp)));
		/* calc_matrix(sr, tar, keep=True, rotate=extra) */
		double smx = (sr.x0 + sr.x1) / 2.0, smy = (sr.y0 + sr.y1) / 2.0;
		double tmx = (tar.x0 + tar.x1) / 2.0, tmy = (tar.y0 + tar.y1) / 2.0;
		dmat mv = {1, 0, 0, 1, -smx, -smy};
		dmat m = concat(mv, rotate_deg(extra));
		drect sr1 = rect_mul(sr, m);
		double fw = width(tar) / width(sr1), fh = height(tar) / height(sr1);
		if (fh < fw) fw = fh; else fh = fw;   /* min(fw, fh) */
		dmat sc = {fw, 0, 0, fh, 0, 0};
		m = concat(m, sc);
		dmat mt = {1, 0, 0, 1, tmx, tmy};
		m = concat(m, mt);

		/* page.wrap_contents(): the new page has no content, nothing to balance */
		gmap = pdf_new_graft_map(g_ctx, d);
		/* JM_xobject_from_page */
		fz_rect smedia = pdf_to_rect(g_ctx, pdf_dict_get_inheritable(g_ctx, sp->obj, PDF_NAME(MediaBox)));
		pdf_obj *o = pdf_dict_get_inheritable(g_ctx, sp->obj, PDF_NAME(Resources));
		pdf_obj *res1 = pdf_graft_mapped_object(g_ctx, gmap, o);
		fz_buffer *cont = read_contents(sp->obj);
		pdf_obj *xobj1 = pdf_new_xobject(g_ctx, d, smedia, fz_identity, NULL, cont);
		update_stream(d, xobj1, cont);
		pdf_dict_put(g_ctx, xobj1, PDF_NAME(Resources), res1);
		fz_drop_buffer(g_ctx, cont);
		pdf_drop_obj(g_ctx, res1);
		/* _show_pdf_page */
		pdf_obj *subres1 = pdf_new_dict(g_ctx, d, 5);
		pdf_dict_puts(g_ctx, subres1, "fullpage", xobj1);
		pdf_obj *subres = pdf_new_dict(g_ctx, d, 5);
		pdf_dict_put(g_ctx, subres, PDF_NAME(XObject), subres1);
		fz_buffer *res = fz_new_buffer(g_ctx, 20);
		fz_append_string(g_ctx, res, "/fullpage Do");
		pdf_obj *xobj2 = pdf_new_xobject(g_ctx, d, rect_to_fz(sr), to_fz(m), subres, res);
		pdf_obj *tres = pdf_dict_get_inheritable(g_ctx, tp->obj, PDF_NAME(Resources));
		if (!tres) tres = pdf_dict_put_dict(g_ctx, tp->obj, PDF_NAME(Resources), 5);
		pdf_obj *tx = pdf_dict_get(g_ctx, tres, PDF_NAME(XObject));
		if (!tx) tx = pdf_dict_put_dict(g_ctx, tres, PDF_NAME(XObject), 5);
		pdf_dict_puts(g_ctx, tx, "fzFrm0", xobj2);
		fz_buffer *nres = fz_new_buffer(g_ctx, 50);
		fz_append_string(g_ctx, nres, " q /");
		fz_append_string(g_ctx, nres, "fzFrm0");
		fz_append_string(g_ctx, nres, " Do Q ");
		/* JM_insert_contents(overlay=1) */
		pdf_obj *cobj = pdf_dict_get(g_ctx, tp->obj, PDF_NAME(Contents));
		pdf_obj *newconts = pdf_add_stream(g_ctx, d, nres, NULL, 0);
		if (pdf_is_array(g_ctx, cobj)) pdf_array_push(g_ctx, cobj, newconts);
		else {
			pdf_obj *carr = pdf_new_array(g_ctx, d, 5);
			if (cobj) pdf_array_push(g_ctx, carr, cobj);
			pdf_array_push(g_ctx, carr, newconts);
			pdf_dict_put(g_ctx, tp->obj, PDF_NAME(Contents), carr);
			pdf_drop_obj(g_ctx, carr);
		}
		pdf_drop_obj(g_ctx, newconts);
		fz_drop_buffer(g_ctx, nres);
		fz_drop_buffer(g_ctx, res);
		pdf_drop_obj(g_ctx, subres);
		pdf_drop_obj(g_ctx, subres1);
		pdf_drop_obj(g_ctx, xobj1);
		pdf_drop_obj(g_ctx, xobj2);
		fz_drop_page(g_ctx, (fz_page *)tp);
		fz_drop_page(g_ctx, (fz_page *)sp);

		/* d.save(dst) with PyMuPDF's defaults, then pymupdf.open(dst) */
		pdf_write_options opts = pdf_default_write_options;
		out = fz_new_buffer(g_ctx, 1 << 20);
		fz_output *fo = fz_new_output_with_buffer(g_ctx, out);
		pdf_write_document(g_ctx, d, fo, &opts);
		fz_close_output(g_ctx, fo);
		fz_drop_output(g_ctx, fo);
		fz_stream *st = fz_open_buffer(g_ctx, out);
		result = fz_open_document_with_stream(g_ctx, "pdf", st);
		fz_drop_stream(g_ctx, st);
	}
	fz_always(g_ctx) {
		pdf_drop_graft_map(g_ctx, gmap);
		pdf_drop_document(g_ctx, d);
		pdf_drop_document(g_ctx, s);
		fz_drop_buffer(g_ctx, out);
	}
	fz_catch(g_ctx) {
		snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
		result = NULL;
	}
	return result;
}

fz_document *kks_open(const char *path)
{
	fz_document *doc = NULL;
	fz_try(g_ctx) doc = fz_open_document(g_ctx, path);
	fz_catch(g_ctx) { snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx)); doc = NULL; }
	return doc;
}

static void dl_forget(fz_document *doc);
void kks_close(fz_document *doc) { dl_forget(doc); fz_drop_document(g_ctx, doc); }

int kks_page_size(fz_document *doc, float *w, float *h)
{
	int ok = 0;
	fz_try(g_ctx) {
		fz_page *p = fz_load_page(g_ctx, doc, 0);
		fz_rect r = fz_bound_page(g_ctx, p);
		*w = r.x1 - r.x0; *h = r.y1 - r.y0;
		fz_drop_page(g_ctx, p);
		ok = 1;
	}
	fz_catch(g_ctx) snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
	return ok;
}

/* ---------------------------------------------------------------- get_pixmap (JM_pixmap_from_display_list) */

/* Page 0 in gray at `zoom` (dpi/72); clip in page coordinates when has_clip. Returns malloc'd samples (w*h bytes)
   and sets *w, *h, *x, *y (the pixmap's origin), or NULL. */
/* The page's display list, kept between renders of the same document (PyMuPDF builds the same list on every
   get_pixmap call; reusing it changes no pixel, and the reader renders thousands of clips per sheet). */
static fz_document *dl_doc;
static float dl_mlw;
static fz_display_list *dl_cached;

static void dl_forget(fz_document *doc)
{
	if (dl_cached && (doc == NULL || doc == dl_doc)) {
		fz_drop_display_list(g_ctx, dl_cached);
		dl_cached = NULL;
		dl_doc = NULL;
	}
}

/* Page.get_pixmap(matrix=Matrix(zoom, zoom), clip, colorspace=csGRAY or csRGB, alpha=False): ncomp 1 or 3. */
unsigned char *kks_render(fz_document *doc, double zoom, int has_clip, double cx0, double cy0, double cx1, double cy1,
                          float min_line_width, int ncomp, int *w, int *h, int *x, int *y)
{
	unsigned char *samples = NULL;
	fz_display_list *dl = NULL;
	fz_pixmap *pix = NULL;
	fz_device *dev = NULL;
	fz_page *page = NULL;
	fz_var(samples); fz_var(dl); fz_var(pix); fz_var(dev); fz_var(page);
	float old_mlw = fz_graphics_min_line_width(g_ctx);
	fz_try(g_ctx) {
		fz_set_graphics_min_line_width(g_ctx, min_line_width);
		if (dl_cached && dl_doc == doc && dl_mlw == min_line_width) {
			dl = fz_keep_display_list(g_ctx, dl_cached);
		} else {
			dl_forget(NULL);
			page = fz_load_page(g_ctx, doc, 0);
			dl = fz_new_display_list_from_page(g_ctx, page);   /* get_displaylist(annots=True) */
			dl_cached = fz_keep_display_list(g_ctx, dl);
			dl_doc = doc;
			dl_mlw = min_line_width;
		}
		fz_matrix matrix = fz_make_matrix((float)zoom, 0, 0, (float)zoom, 0, 0);   /* Matrix(zoom, zoom) */
		fz_rect rect = fz_bound_display_list(g_ctx, dl);
		fz_rect rclip = has_clip ? fz_make_rect((float)cx0, (float)cy0, (float)cx1, (float)cy1) : fz_infinite_rect;
		rect = fz_intersect_rect(rect, rclip);
		rect = fz_transform_rect(rect, matrix);
		fz_irect irect = fz_round_rect(rect);
		pix = fz_new_pixmap_with_bbox(g_ctx, ncomp == 3 ? fz_device_rgb(g_ctx) : fz_device_gray(g_ctx), irect, NULL, 0);
		fz_clear_pixmap_with_value(g_ctx, pix, 0xFF);
		if (has_clip) {
			dev = fz_new_draw_device_with_bbox(g_ctx, matrix, pix, &irect);
			fz_run_display_list(g_ctx, dl, dev, fz_identity, rclip, NULL);
		} else {
			dev = fz_new_draw_device(g_ctx, matrix, pix);
			fz_run_display_list(g_ctx, dl, dev, fz_identity, fz_infinite_rect, NULL);
		}
		fz_close_device(g_ctx, dev);
		*w = pix->w; *h = pix->h; *x = pix->x; *y = pix->y;
		size_t rowlen = (size_t)pix->w * ncomp;
		samples = malloc(rowlen * pix->h + 1);
		for (int row = 0; row < pix->h; row++)
			memcpy(samples + (size_t)row * rowlen, pix->samples + (size_t)row * pix->stride, rowlen);
	}
	fz_always(g_ctx) {
		fz_set_graphics_min_line_width(g_ctx, old_mlw);
		fz_drop_device(g_ctx, dev);
		fz_drop_pixmap(g_ctx, pix);
		fz_drop_display_list(g_ctx, dl);
		fz_drop_page(g_ctx, page);
	}
	fz_catch(g_ctx) {
		snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
		free(samples);
		samples = NULL;
	}
	return samples;
}

unsigned char *kks_render_gray(fz_document *doc, double zoom, int has_clip, double cx0, double cy0, double cx1, double cy1,
                               float min_line_width, int *w, int *h, int *x, int *y)
{
	return kks_render(doc, zoom, has_clip, cx0, cy0, cx1, cy1, min_line_width, 1, w, h, x, y);
}

void kks_free(void *p) { free(p); }

/* ---------------------------------------------------------------- get_drawings (PyMuPDF line-art device) */

typedef struct { char cmd; float p[8]; int orientation; } kks_item;   /* 'l': 2 points, 'c': 4, 'r' ('re'): rect, 'q' ('qu'): 4 */

typedef struct {
	char type[3];            /* "f", "s" or "fs" */
	int has_fill;
	size_t seqno;
	float rect[4];
	int n_items;
	kks_item *items;
	/* style, as PyMuPDF's path dict (a merged "fs" keeps the fill's keys and adds the stroke's missing ones) */
	int close_path;          /* -1 = key absent, 0, 1 */
	int even_odd;            /* fills */
	int has_fill_color; float fill[3]; float fill_opacity;
	int has_stroke;          /* the stroke keys below are present */
	int has_color; float color[3]; float stroke_opacity;
	float width;
	int cap[3];
	int join;
	int dash_len;
} kks_path;

typedef struct {
	fz_device super;
	kks_path *out; int n_out, cap_out;
	kks_path cur; int have_cur; int cap_items;
	fz_matrix ctm;
	fz_point lastpoint, firstpoint;
	int havemove;
	fz_rect pathrect;
	int linecount;
	int path_type;           /* 1 fill, 2 stroke */
	size_t seqno;
	size_t logidx;           /* index in PyMuPDF's get_bboxlog(): one per path, text, shade or image call */
	int want_images;
	struct kks_image *images; int n_images, cap_images;
} kks_lineart;

typedef struct kks_image {
	size_t logidx;
	float ctm[6];
	int w, h, n;             /* n = 3 (RGB) or 4 (RGBA) */
	unsigned char *pixels;   /* w*h*n, rows without padding */
} kks_image;

static void cur_add(kks_lineart *dev, kks_item it)
{
	if (dev->cur.n_items == dev->cap_items) {
		dev->cap_items = dev->cap_items ? dev->cap_items * 2 : 8;
		dev->cur.items = realloc(dev->cur.items, sizeof(kks_item) * dev->cap_items);
	}
	dev->cur.items[dev->cur.n_items++] = it;
}

void kks_free_paths(kks_path *p, int n)
{
	for (int i = 0; i < n; i++) free(p[i].items);
	free(p);
}

static int checkquad(kks_lineart *dev)
{
	int len = dev->cur.n_items;
	float f[8]; fz_point lp = {0, 0};
	for (int i = 0; i < 4; i++) {
		kks_item *line = &dev->cur.items[len - 4 + i];
		f[i * 2] = line->p[0]; f[i * 2 + 1] = line->p[1];
		lp.x = line->p[2]; lp.y = line->p[3];
	}
	if (lp.x != f[0] || lp.y != f[1]) return 0;
	dev->linecount = 0;
	fz_quad q = fz_make_quad(f[0], f[1], f[6], f[7], f[2], f[3], f[4], f[5]);
	kks_item it = {'q', {q.ul.x, q.ul.y, q.ur.x, q.ur.y, q.ll.x, q.ll.y, q.lr.x, q.lr.y}, 0};
	dev->cur.items[len - 4] = it;
	dev->cur.n_items = len - 3;
	return 1;
}

static int checkrect(kks_lineart *dev)
{
	dev->linecount = 0;
	int len = dev->cur.n_items;
	kks_item *line0 = &dev->cur.items[len - 3], *line2 = &dev->cur.items[len - 1];
	fz_point ll = {line0->p[0], line0->p[1]}, lr = {line0->p[2], line0->p[3]};
	fz_point ur = {line2->p[0], line2->p[1]}, ul = {line2->p[2], line2->p[3]};
	if (ll.y != lr.y || ll.x != ul.x || ur.y != ul.y || ur.x != lr.x) return 0;
	fz_rect r; int orientation;
	if (ul.y < lr.y) { r = fz_make_rect(ul.x, ul.y, lr.x, lr.y); orientation = 1; }
	else { r = fz_make_rect(ll.x, ll.y, ur.x, ur.y); orientation = -1; }
	kks_item it = {'r', {r.x0, r.y0, r.x1, r.y1}, orientation};
	dev->cur.items[len - 3] = it;
	dev->cur.n_items = len - 2;
	return 1;
}

static void trace_moveto(fz_context *ctx, void *dev_, float x, float y)
{
	kks_lineart *dev = dev_;
	dev->lastpoint = fz_transform_point(fz_make_point(x, y), dev->ctm);
	if (fz_is_infinite_rect(dev->pathrect))
		dev->pathrect = fz_make_rect(dev->lastpoint.x, dev->lastpoint.y, dev->lastpoint.x, dev->lastpoint.y);
	dev->firstpoint = dev->lastpoint;
	dev->havemove = 1;
	dev->linecount = 0;
}

static void trace_lineto(fz_context *ctx, void *dev_, float x, float y)
{
	kks_lineart *dev = dev_;
	fz_point p1 = fz_transform_point(fz_make_point(x, y), dev->ctm);
	dev->pathrect = fz_include_point_in_rect(dev->pathrect, p1);
	kks_item it = {'l', {dev->lastpoint.x, dev->lastpoint.y, p1.x, p1.y}, 0};
	cur_add(dev, it);
	dev->lastpoint = p1;
	dev->linecount += 1;
	if (dev->linecount == 4 && dev->path_type != 1) checkquad(dev);
}

static void trace_curveto(fz_context *ctx, void *dev_, float x1, float y1, float x2, float y2, float x3, float y3)
{
	kks_lineart *dev = dev_;
	dev->linecount = 0;
	fz_point p1 = fz_transform_point(fz_make_point(x1, y1), dev->ctm);
	fz_point p2 = fz_transform_point(fz_make_point(x2, y2), dev->ctm);
	fz_point p3 = fz_transform_point(fz_make_point(x3, y3), dev->ctm);
	dev->pathrect = fz_include_point_in_rect(dev->pathrect, p1);
	dev->pathrect = fz_include_point_in_rect(dev->pathrect, p2);
	dev->pathrect = fz_include_point_in_rect(dev->pathrect, p3);
	kks_item it = {'c', {dev->lastpoint.x, dev->lastpoint.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y}, 0};
	cur_add(dev, it);
	dev->lastpoint = p3;
}

static void trace_close(fz_context *ctx, void *dev_)
{
	kks_lineart *dev = dev_;
	if (dev->linecount == 3 && checkrect(dev)) return;
	dev->linecount = 0;
	if (dev->havemove) {
		if (dev->firstpoint.x != dev->lastpoint.x || dev->firstpoint.y != dev->lastpoint.y) {
			kks_item it = {'l', {dev->lastpoint.x, dev->lastpoint.y, dev->firstpoint.x, dev->firstpoint.y}, 0};
			cur_add(dev, it);
			dev->lastpoint = dev->firstpoint;
		}
		dev->havemove = 0;
		dev->cur.close_path = 0;
	} else {
		dev->cur.close_path = 1;
	}
}

static const fz_path_walker trace_walker = { trace_moveto, trace_lineto, trace_curveto, trace_close };

static int lineart_path(kks_lineart *dev, const fz_path *path)
{
	dev->pathrect = fz_infinite_rect;
	dev->linecount = 0;
	dev->lastpoint = fz_make_point(0, 0);
	dev->firstpoint = fz_make_point(0, 0);
	dev->cur.n_items = 0;
	dev->cur.close_path = -1;
	dev->cur.has_fill_color = dev->cur.has_stroke = dev->cur.has_color = 0;
	fz_walk_path(g_ctx, path, &trace_walker, dev);
	return dev->cur.n_items > 0;
}

static int same_items(kks_path *a, kks_path *b)
{
	if (a->n_items != b->n_items) return 0;
	for (int i = 0; i < a->n_items; i++) {
		kks_item *x = &a->items[i], *y = &b->items[i];
		if (x->cmd != y->cmd || x->orientation != y->orientation) return 0;
		int n = x->cmd == 'l' ? 4 : 8;
		if (x->cmd == 'r') n = 4;
		for (int k = 0; k < n; k++) if (x->p[k] != y->p[k]) return 0;
	}
	return 1;
}

static void append_merge(kks_lineart *dev)
{
	kks_path p = dev->cur;
	p.items = malloc(sizeof(kks_item) * (p.n_items ? p.n_items : 1));
	memcpy(p.items, dev->cur.items, sizeof(kks_item) * p.n_items);
	if (dev->n_out > 0 && strcmp(p.type, "s") == 0) {
		kks_path *prev = &dev->out[dev->n_out - 1];
		if (strcmp(prev->type, "f") == 0 && same_items(prev, &p)) {   /* a stroke of the fill just before: merge */
			strcpy(prev->type, "fs");
			/* PyDict_Merge(prev, stroke, override=0): the stroke's keys the fill lacks */
			if (prev->close_path < 0) prev->close_path = p.close_path;
			prev->has_stroke = 1;
			prev->has_color = p.has_color;
			memcpy(prev->color, p.color, sizeof p.color);
			prev->stroke_opacity = p.stroke_opacity;
			prev->width = p.width;
			memcpy(prev->cap, p.cap, sizeof p.cap);
			prev->join = p.join;
			prev->dash_len = p.dash_len;
			free(p.items);
			return;
		}
	}
	if (dev->n_out == dev->cap_out) {
		dev->cap_out = dev->cap_out ? dev->cap_out * 2 : 1024;
		dev->out = realloc(dev->out, sizeof(kks_path) * dev->cap_out);
	}
	dev->out[dev->n_out++] = p;
}

static int lineart_color(fz_colorspace *cs, const float *color, float rgb[3])   /* jm_lineart_color */
{
	if (!cs) return 0;
	fz_convert_color(g_ctx, cs, color, fz_device_rgb(g_ctx), rgb, NULL, fz_default_color_params);
	return 1;
}

static void lineart_fill_path(fz_context *ctx, fz_device *dev_, const fz_path *path, int even_odd, fz_matrix ctm,
                              fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	kks_lineart *dev = (kks_lineart *)dev_;
	dev->logidx += 1;
	dev->ctm = ctm;
	dev->path_type = 1;
	if (!lineart_path(dev, path)) return;
	strcpy(dev->cur.type, "f");
	dev->cur.has_fill = 1;
	dev->cur.even_odd = even_odd;
	dev->cur.fill_opacity = alpha;
	dev->cur.has_fill_color = lineart_color(cs, color, dev->cur.fill);
	dev->cur.seqno = dev->seqno;
	dev->cur.rect[0] = dev->pathrect.x0; dev->cur.rect[1] = dev->pathrect.y0;
	dev->cur.rect[2] = dev->pathrect.x1; dev->cur.rect[3] = dev->pathrect.y1;
	append_merge(dev);
	dev->seqno += 1;
}

static void lineart_stroke_path(fz_context *ctx, fz_device *dev_, const fz_path *path, const fz_stroke_state *stroke,
                                fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	kks_lineart *dev = (kks_lineart *)dev_;
	float pathfactor = sqrtf(fabsf(ctm.a * ctm.d - ctm.b * ctm.c));
	dev->logidx += 1;
	dev->ctm = ctm;
	dev->path_type = 2;
	if (!lineart_path(dev, path)) return;
	strcpy(dev->cur.type, "s");
	dev->cur.has_fill = 0;
	dev->cur.has_stroke = 1;
	dev->cur.stroke_opacity = alpha;
	dev->cur.has_color = lineart_color(cs, color, dev->cur.color);
	dev->cur.width = pathfactor * stroke->linewidth;
	dev->cur.cap[0] = stroke->start_cap; dev->cur.cap[1] = stroke->dash_cap; dev->cur.cap[2] = stroke->end_cap;
	dev->cur.join = (int)(float)stroke->linejoin;
	dev->cur.dash_len = stroke->dash_len;
	if (dev->cur.close_path < 0) dev->cur.close_path = 0;
	dev->cur.seqno = dev->seqno;
	dev->cur.rect[0] = dev->pathrect.x0; dev->cur.rect[1] = dev->pathrect.y0;
	dev->cur.rect[2] = dev->pathrect.x1; dev->cur.rect[3] = dev->pathrect.y1;
	append_merge(dev);
	dev->seqno += 1;
}

#define INC(d) do { ((kks_lineart *)(d))->seqno += 1; ((kks_lineart *)(d))->logidx += 1; } while (0)
static void inc_text(fz_context *c, fz_device *d, const fz_text *t, fz_matrix m, fz_colorspace *cs, const float *col,
                     float a, fz_color_params cp) { INC(d); }
static void inc_stroke_text(fz_context *c, fz_device *d, const fz_text *t, const fz_stroke_state *s, fz_matrix m,
                            fz_colorspace *cs, const float *col, float a, fz_color_params cp) { INC(d); }
static void inc_ignore_text(fz_context *c, fz_device *d, const fz_text *t, fz_matrix m) { INC(d); }
static void inc_shade(fz_context *c, fz_device *d, fz_shade *s, fz_matrix m, float a, fz_color_params cp) { INC(d); }
static void inc_image_mask(fz_context *c, fz_device *d, fz_image *i, fz_matrix m, fz_colorspace *cs, const float *col,
                           float a, fz_color_params cp)
{
	if (((kks_lineart *)d)->want_images)
		fz_throw(c, FZ_ERROR_GENERIC, "image masks (stencils) are not supported in the path store");
	INC(d);
}

/* The image as MuPDF draws it: decoded (colour-key transparency as alpha), its soft mask as alpha, converted to
   sRGB with MuPDF's colour management like every vector colour. */
static void inc_image(fz_context *c, fz_device *d_, fz_image *image, fz_matrix m, float a, fz_color_params cp)
{
	kks_lineart *d = (kks_lineart *)d_;
	if (d->want_images) {
		fz_pixmap *pix = NULL, *rgb = NULL, *mask = NULL;
		fz_var(pix); fz_var(rgb); fz_var(mask);
		fz_try(c) {
			pix = fz_get_pixmap_from_image(c, image, NULL, NULL, NULL, NULL);
			rgb = fz_convert_pixmap(c, pix, fz_device_rgb(c), NULL, NULL, fz_default_color_params, 1);
			if (image->mask) {
				mask = fz_get_pixmap_from_image(c, image->mask, NULL, NULL, NULL, NULL);
				if (mask->w != rgb->w || mask->h != rgb->h) {
					fz_pixmap *sc = fz_scale_pixmap(c, mask, 0, 0, rgb->w, rgb->h, NULL);
					fz_drop_pixmap(c, mask);
					mask = sc;
				}
			}
			int n = (rgb->alpha || mask) ? 4 : 3;
			kks_image im = {d->logidx, {m.a, m.b, m.c, m.d, m.e, m.f}, rgb->w, rgb->h, n, NULL};
			im.pixels = malloc((size_t)im.w * im.h * n + 1);
			for (int y = 0; y < im.h; y++)
				for (int x = 0; x < im.w; x++) {
					const unsigned char *sp = rgb->samples + (size_t)y * rgb->stride + (size_t)x * rgb->n;
					unsigned char *dp = im.pixels + ((size_t)y * im.w + x) * n;
					dp[0] = sp[0]; dp[1] = sp[1]; dp[2] = sp[2];
					if (n == 4) {
						int alpha = rgb->alpha ? sp[3] : 255;
						if (mask) alpha = mask->samples[(size_t)y * mask->stride + (size_t)x * mask->n];   /* PIL putalpha: replaces */
						dp[3] = (unsigned char)alpha;
					}
				}
			if (rgb->alpha) {   /* MuPDF pixmaps are premultiplied: back to straight alpha (before the soft mask) */
				for (int y = 0; y < im.h; y++)
					for (int x = 0; x < im.w; x++) {
						const unsigned char *sp = rgb->samples + (size_t)y * rgb->stride + (size_t)x * rgb->n;
						unsigned char *dp = im.pixels + ((size_t)y * im.w + x) * n;
						int al = sp[3];
						for (int k = 0; k < 3; k++) dp[k] = al ? (unsigned char)((sp[k] * 255 + al / 2) / al) : 0;
					}
			}
			if (d->n_images == d->cap_images) {
				d->cap_images = d->cap_images ? d->cap_images * 2 : 8;
				d->images = realloc(d->images, sizeof(kks_image) * d->cap_images);
			}
			d->images[d->n_images++] = im;
		}
		fz_always(c) {
			fz_drop_pixmap(c, mask);
			fz_drop_pixmap(c, rgb);
			fz_drop_pixmap(c, pix);
		}
		fz_catch(c) fz_rethrow(c);
	}
	INC(d);
}

/* All paths of page 0 (strokes, fills, fill+stroke merged), in drawing order. Returns the count; *out is malloc'd
   (free with kks_free_paths). -1 on error. unrotate: run with the page's /Rotate set to 0 and restored after, like
   PyMuPDF's Page.get_cdrawings (coordinates in the unrotated page). */
int kks_drawings_images(fz_document *doc, kks_path **out, int unrotate, kks_image **images, int *n_images);
int kks_drawings(fz_document *doc, kks_path **out, int unrotate)
{
	return kks_drawings_images(doc, out, unrotate, NULL, NULL);
}

int kks_drawings_images(fz_document *doc, kks_path **out, int unrotate, kks_image **images, int *n_images)
{
	fz_context *ctx = g_ctx;   /* fz_new_derived_device expects `ctx` */
	int n = -1;
	kks_lineart *dev = NULL;
	fz_page *page = NULL;
	int old_rot = 0, restore = 0;
	fz_var(dev); fz_var(page); fz_var(n); fz_var(restore);
	fz_try(g_ctx) {
		page = fz_load_page(g_ctx, doc, 0);
		pdf_page *pp = pdf_page_from_fz_page(g_ctx, page);
		if (unrotate && pp) {
			old_rot = pdf_to_int(g_ctx, pdf_dict_get_inheritable(g_ctx, pp->obj, PDF_NAME(Rotate)));
			if (old_rot % 360 != 0) { pdf_dict_put_int(g_ctx, pp->obj, PDF_NAME(Rotate), 0); restore = 1; }
		}
		dev = fz_new_derived_device(g_ctx, kks_lineart);
		dev->want_images = images != NULL;
		dev->super.fill_path = lineart_fill_path;
		dev->super.stroke_path = lineart_stroke_path;
		dev->super.fill_text = inc_text;
		dev->super.stroke_text = inc_stroke_text;
		dev->super.ignore_text = inc_ignore_text;
		dev->super.fill_shade = inc_shade;
		dev->super.fill_image = inc_image;
		dev->super.fill_image_mask = inc_image_mask;
		fz_run_page(g_ctx, page, (fz_device *)dev, fz_identity, NULL);
		fz_close_device(g_ctx, (fz_device *)dev);
		*out = dev->out;
		n = dev->n_out;
		dev->out = NULL;
		if (images) {
			*images = dev->images;
			*n_images = dev->n_images;
			dev->images = NULL;
			dev->n_images = 0;
		}
	}
	fz_always(g_ctx) {
		if (restore) {
			pdf_page *pp = pdf_page_from_fz_page(g_ctx, page);
			pdf_dict_put_int(g_ctx, pp->obj, PDF_NAME(Rotate), old_rot);
		}
		if (dev) {
			free(dev->cur.items);
			for (int i = 0; i < dev->n_images; i++) free(dev->images[i].pixels);   /* only left on error */
			free(dev->images);
			if (dev->out) kks_free_paths(dev->out, dev->n_out);
		}
		fz_drop_device(g_ctx, (fz_device *)dev);
		fz_drop_page(g_ctx, page);
	}
	fz_catch(g_ctx) {
		snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
		n = -1;
	}
	return n;
}

void kks_free_images(kks_image *p, int n)
{
	for (int i = 0; i < n; i++) free(p[i].pixels);
	free(p);
}

/* ---------------------------------------------------------------- display geometry (ref/pathstore.from_pdf_page) */

/* the first page's own /Rotate, normalised to 0/90/180/270 (anything else counts as 0, as PyMuPDF does). -1 on error */
int kks_page_rotation(fz_document *doc)
{
	int rot = 0;
	fz_page *page = NULL;
	fz_var(page); fz_var(rot);
	fz_try(g_ctx) {
		page = fz_load_page(g_ctx, doc, 0);
		pdf_page *pp = pdf_page_from_fz_page(g_ctx, page);
		if (pp) rot = pdf_to_int(g_ctx, pdf_dict_get_inheritable(g_ctx, pp->obj, PDF_NAME(Rotate)));
		while (rot < 0) rot += 360;
		while (rot >= 360) rot -= 360;
		if (rot % 90 != 0) rot = 0;
	}
	fz_always(g_ctx) { fz_drop_page(g_ctx, page); }
	fz_catch(g_ctx) {
		snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
		rot = -1;
	}
	return rot;
}

/* m = page.rotation_matrix * Matrix(extra) * shift and r = page.rect * Matrix(extra), with PyMuPDF's arithmetic
   (JM_rotate_page_matrix, util_concat_matrix, util_transform_rect: MuPDF floats). m: 6 doubles, r: 4 doubles. */
int kks_display_geom(fz_document *doc, int extra, double *m_out, double *r_out)
{
	int ok = 0;
	fz_page *page = NULL;
	fz_var(page);
	fz_try(g_ctx) {
		page = fz_load_page(g_ctx, doc, 0);
		pdf_page *pp = pdf_page_from_fz_page(g_ctx, page);
		dmat rm = {1, 0, 0, 1, 0, 0};
		if (pp) {
			int rot = pdf_to_int(g_ctx, pdf_dict_get_inheritable(g_ctx, pp->obj, PDF_NAME(Rotate)));
			while (rot < 0) rot += 360;
			while (rot >= 360) rot -= 360;
			if (rot % 90 != 0) rot = 0;
			if (rot != 0) {
				/* JM_cropbox_size */
				fz_rect mediabox = pdf_to_rect(g_ctx, pdf_dict_get_inheritable(g_ctx, pp->obj, PDF_NAME(MediaBox)));
				if (fz_is_infinite_rect(mediabox) || fz_is_empty_rect(mediabox)) mediabox = fz_make_rect(0, 0, 612, 792);
				mediabox = fz_make_rect(fz_min(mediabox.x0, mediabox.x1), fz_min(mediabox.y0, mediabox.y1),
				                        fz_max(mediabox.x0, mediabox.x1), fz_max(mediabox.y0, mediabox.y1));   /* JM_mediabox */
				if (mediabox.x1 - mediabox.x0 < 1 || mediabox.y1 - mediabox.y0 < 1) mediabox = fz_unit_rect;
				fz_rect cropbox = pdf_to_rect(g_ctx, pdf_dict_get_inheritable(g_ctx, pp->obj, PDF_NAME(CropBox)));
				if (fz_is_infinite_rect(cropbox) || fz_is_empty_rect(cropbox)) cropbox = mediabox;
				float y0 = mediabox.y1 - cropbox.y1, y1 = mediabox.y1 - cropbox.y0;
				cropbox.y0 = y0; cropbox.y1 = y1;
				float w = fabsf(cropbox.x1 - cropbox.x0), h = fabsf(cropbox.y1 - cropbox.y0);
				fz_matrix f;
				if (rot == 90) f = fz_make_matrix(0, 1, -1, 0, h, 0);
				else if (rot == 180) f = fz_make_matrix(-1, 0, 0, -1, w, h);
				else f = fz_make_matrix(0, -1, 1, 0, 0, w);
				rm = from_fz(f);
			}
		}
		dmat em = rotate_deg(extra);
		dmat m = concat(rm, em);
		drect r = rect_mul(rect_from_fz(fz_bound_page(g_ctx, page)), em);
		dmat shift = {1, 0, 0, 1, -r.x0, -r.y0};
		m = concat(m, shift);
		m_out[0] = m.a; m_out[1] = m.b; m_out[2] = m.c; m_out[3] = m.d; m_out[4] = m.e; m_out[5] = m.f;
		r_out[0] = r.x0; r_out[1] = r.y0; r_out[2] = r.x1; r_out[3] = r.y1;
		ok = 1;
	}
	fz_always(g_ctx) fz_drop_page(g_ctx, page);
	fz_catch(g_ctx) snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
	return ok;
}

/* ---------------------------------------------------------------- annotation notes (import_sheet.py) */

/* The /Contents of page 0's annotations in /Annots order, skipping links, popups and widgets (Page.annots()), each
   UTF-8 and NUL-terminated, concatenated. Returns a malloc'd buffer (*len bytes) or NULL on error. */
char *kks_annot_notes(fz_document *doc, size_t *len)
{
	char *out = NULL;
	fz_page *page = NULL;
	fz_var(out); fz_var(page);
	*len = 0;
	fz_try(g_ctx) {
		size_t cap = 256;
		out = malloc(cap);
		page = fz_load_page(g_ctx, doc, 0);
		pdf_page *pp = pdf_page_from_fz_page(g_ctx, page);
		pdf_obj *annots = pp ? pdf_dict_get(g_ctx, pp->obj, PDF_NAME(Annots)) : NULL;
		for (int i = 0; i < pdf_array_len(g_ctx, annots); i++) {
			pdf_obj *a = pdf_array_get(g_ctx, annots, i);
			int type = pdf_annot_type_from_string(g_ctx, pdf_to_name(g_ctx, pdf_dict_get(g_ctx, a, PDF_NAME(Subtype))));
			if (type == PDF_ANNOT_LINK || type == PDF_ANNOT_POPUP || type == PDF_ANNOT_WIDGET) continue;
			const char *s = pdf_dict_get_text_string(g_ctx, a, PDF_NAME(Contents));
			size_t n = strlen(s) + 1;
			while (*len + n > cap) { cap *= 2; out = realloc(out, cap); }
			memcpy(out + *len, s, n);
			*len += n;
		}
	}
	fz_always(g_ctx) fz_drop_page(g_ctx, page);
	fz_catch(g_ctx) {
		snprintf(g_error, sizeof g_error, "%s", fz_caught_message(g_ctx));
		free(out);
		out = NULL;
	}
	return out;
}
