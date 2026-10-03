/* The webcam for scanning an invite QR (decision 0039): the camera portal (AccessCamera, then OpenPipeWireRemote's
 * fd into GStreamer's pipewiresrc); v4l2src when no portal answers; KKS_CAMERA_FILE plays a video file through the
 * same pipeline (tests). Frames come out of an appsink as 8-bit grey. Runs on the GTK main loop: the portal's answer
 * arrives as a D-Bus signal there, and the caller polls kks_cam_frame from a timer. */
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PORTAL "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"

typedef struct kks_cam {
    int state;               /* 0 starting (waiting for the person or the portal), 1 running, -1 failed */
    int closed;              /* closed while the portal was still asking: freed when the answer comes */
    char err[256];
    GstElement *pipe, *sink;
    GDBusConnection *bus;
    guint sub;
    unsigned char *frame;
    int w, h;
} kks_cam;

static void fail(kks_cam *c, const char *m) { c->state = -1; snprintf(c->err, sizeof c->err, "%s", m); }

static void start_pipeline(kks_cam *c, const char *src) {
    char desc[1200];
    snprintf(desc, sizeof desc, "%s ! videoconvert ! video/x-raw,format=GRAY8 ! appsink name=sink max-buffers=1 drop=true sync=false", src);
    GError *e = NULL;
    c->pipe = gst_parse_launch(desc, &e);
    if (!c->pipe || e) {
        fail(c, e ? e->message : "the camera pipeline could not be built");
        if (e) g_error_free(e);
        if (c->pipe) { gst_object_unref(c->pipe); c->pipe = NULL; }
        return;
    }
    c->sink = gst_bin_get_by_name(GST_BIN(c->pipe), "sink");
    if (gst_element_set_state(c->pipe, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        fail(c, "The camera could not be started (is another program using it?)");
        return;
    }
    c->state = 1;
}

static void free_cam(kks_cam *c) {
    if (c->sink) gst_object_unref(c->sink);
    if (c->pipe) { gst_element_set_state(c->pipe, GST_STATE_NULL); gst_object_unref(c->pipe); }
    if (c->bus) g_object_unref(c->bus);
    free(c->frame);
    free(c);
}

static void on_response(GDBusConnection *bus, const char *sender, const char *path, const char *iface,
                        const char *sig, GVariant *params, gpointer data) {
    kks_cam *c = data;
    guint32 resp = 2;
    GVariant *res = NULL;
    g_variant_get(params, "(u@a{sv})", &resp, &res);
    if (res) g_variant_unref(res);
    g_dbus_connection_signal_unsubscribe(bus, c->sub);
    c->sub = 0;
    if (c->closed) { free_cam(c); return; }
    if (resp != 0) { fail(c, "Camera access was not allowed. Paste the invite text instead, or allow the camera in Settings → Privacy."); return; }
    GUnixFDList *fds = NULL;
    GError *e = NULL;
    GVariant *r = g_dbus_connection_call_with_unix_fd_list_sync(bus, PORTAL, PORTAL_PATH, "org.freedesktop.portal.Camera",
        "OpenPipeWireRemote", g_variant_new("(@a{sv})", g_variant_new_array(G_VARIANT_TYPE("{sv}"), NULL, 0)),
        G_VARIANT_TYPE("(h)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &fds, NULL, &e);
    if (!r) { fail(c, e->message); g_error_free(e); return; }
    gint32 idx = -1;
    g_variant_get(r, "(h)", &idx);
    g_variant_unref(r);
    int fd = g_unix_fd_list_get(fds, idx, &e);
    g_object_unref(fds);
    if (fd < 0) { fail(c, e ? e->message : "no PipeWire connection"); if (e) g_error_free(e); return; }
    char src[64];
    snprintf(src, sizeof src, "pipewiresrc fd=%d", fd);   /* pipewiresrc owns the fd from here */
    start_pipeline(c, src);
}

kks_cam *kks_cam_open(void) {
    gst_init(NULL, NULL);
    kks_cam *c = calloc(1, sizeof *c);
    const char *file = getenv("KKS_CAMERA_FILE");
    if (file && *file) {
        gchar *q = g_strescape(file, NULL);
        char src[1100];
        snprintf(src, sizeof src, "filesrc location=\"%s\" ! decodebin", q);
        g_free(q);
        start_pipeline(c, src);
        return c;
    }
    GError *e = NULL;
    c->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &e);
    if (!c->bus) { g_clear_error(&e); start_pipeline(c, "v4l2src"); return c; }
    GVariant *p = g_dbus_connection_call_sync(c->bus, PORTAL, PORTAL_PATH, "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", "org.freedesktop.portal.Camera", "IsCameraPresent"), G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &e);
    if (!p) { g_clear_error(&e); start_pipeline(c, "v4l2src"); return c; }   /* no camera portal: the device directly */
    GVariant *v = NULL;
    g_variant_get(p, "(v)", &v);
    gboolean present = v && g_variant_is_of_type(v, G_VARIANT_TYPE_BOOLEAN) && g_variant_get_boolean(v);
    if (v) g_variant_unref(v);
    g_variant_unref(p);
    if (!present) { fail(c, "No camera found on this computer. Paste the invite text instead."); return c; }
    /* the Request object the portal will answer on: …/request/<our unique name without ':' and with '.' → '_'>/<token> */
    char token[32];
    snprintf(token, sizeof token, "kks%u", g_random_int());
    gchar *sender = g_strdup(g_dbus_connection_get_unique_name(c->bus) + 1);
    for (char *s = sender; *s; s++) if (*s == '.') *s = '_';
    gchar *req = g_strdup_printf(PORTAL_PATH "/request/%s/%s", sender, token);
    c->sub = g_dbus_connection_signal_subscribe(c->bus, PORTAL, "org.freedesktop.portal.Request", "Response", req, NULL,
                                                G_DBUS_SIGNAL_FLAGS_NONE, on_response, c, NULL);
    g_free(sender);
    g_free(req);
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&b, "{sv}", "handle_token", g_variant_new_string(token));
    GVariant *r = g_dbus_connection_call_sync(c->bus, PORTAL, PORTAL_PATH, "org.freedesktop.portal.Camera", "AccessCamera",
        g_variant_new("(a{sv})", &b), G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &e);
    if (!r) {
        g_dbus_connection_signal_unsubscribe(c->bus, c->sub);
        c->sub = 0;
        g_clear_error(&e);
        start_pipeline(c, "v4l2src");
        return c;
    }
    g_variant_unref(r);
    return c;   /* state 0 until the portal answers */
}

int kks_cam_state(kks_cam *c) {
    if (c->state == 1 && c->pipe) {   /* errors from the pipeline (unplugged, busy) */
        GstBus *bus = gst_element_get_bus(c->pipe);
        GstMessage *m = gst_bus_pop_filtered(bus, GST_MESSAGE_ERROR);
        if (m) {
            GError *e = NULL;
            gst_message_parse_error(m, &e, NULL);
            fail(c, e ? e->message : "the camera stopped");
            if (e) g_error_free(e);
            gst_message_unref(m);
        }
        gst_object_unref(bus);
    }
    return c->state;
}

const char *kks_cam_error(kks_cam *c) { return c->err; }

/* the newest frame as tight 8-bit grey rows (valid until the next call), or NULL if none arrived since */
const unsigned char *kks_cam_frame(kks_cam *c, int *w, int *h) {
    if (c->state != 1 || !c->sink) return NULL;
    GstSample *s = gst_app_sink_try_pull_sample(GST_APP_SINK(c->sink), 0);
    if (!s) return NULL;
    GstCaps *caps = gst_sample_get_caps(s);
    GstStructure *st = caps ? gst_caps_get_structure(caps, 0) : NULL;
    int fw = 0, fh = 0;
    if (st) { gst_structure_get_int(st, "width", &fw); gst_structure_get_int(st, "height", &fh); }
    GstBuffer *buf = gst_sample_get_buffer(s);
    GstMapInfo map;
    const unsigned char *out = NULL;
    if (fw > 0 && fh > 0 && buf && gst_buffer_map(buf, &map, GST_MAP_READ)) {
        size_t stride = map.size / (size_t)fh;   /* GStreamer pads grey rows to 4 bytes */
        if (stride >= (size_t)fw) {
            if (c->w != fw || c->h != fh) { free(c->frame); c->frame = malloc((size_t)fw * fh); c->w = fw; c->h = fh; }
            for (int y = 0; y < fh; y++) memcpy(c->frame + (size_t)y * fw, map.data + (size_t)y * stride, fw);
            *w = fw; *h = fh;
            out = c->frame;
        }
        gst_buffer_unmap(buf, &map);
    }
    gst_sample_unref(s);
    return out;
}

void kks_cam_close(kks_cam *c) {
    if (!c) return;
    if (c->sub) {   /* the portal is still asking: stop the camera if it starts, free on the answer */
        c->closed = 1;
        return;
    }
    free_cam(c);
}
