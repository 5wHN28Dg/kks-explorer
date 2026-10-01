/* The drawing viewer's widget (decision 0031): a GtkWidget whose snapshot is drawn by Nim (cached tiles appended as
   textures, so GSK composites them on the GPU, decision 0016). Focusable, with an accessible label set from Nim. */
#include <gtk/gtk.h>

typedef void (*kks_snap_fn)(void *user, GtkSnapshot *s, int w, int h);

struct _KksView {
	GtkWidget parent;
	kks_snap_fn snap;
	void *user;
};
G_DECLARE_FINAL_TYPE(KksView, kks_view, KKS, VIEW, GtkWidget)
G_DEFINE_TYPE(KksView, kks_view, GTK_TYPE_WIDGET)

static void kks_view_snapshot(GtkWidget *w, GtkSnapshot *s)
{
	KksView *v = KKS_VIEW(w);
	if (v->snap) v->snap(v->user, s, gtk_widget_get_width(w), gtk_widget_get_height(w));
}

static void kks_view_measure(GtkWidget *w, GtkOrientation o, int for_size, int *min, int *nat, int *minb, int *natb)
{
	*min = 100; *nat = 600;
}

static void kks_view_class_init(KksViewClass *c)
{
	GTK_WIDGET_CLASS(c)->snapshot = kks_view_snapshot;
	GTK_WIDGET_CLASS(c)->measure = kks_view_measure;
	gtk_widget_class_set_accessible_role(GTK_WIDGET_CLASS(c), GTK_ACCESSIBLE_ROLE_IMG);
}

static void kks_view_init(KksView *v)
{
	gtk_widget_set_focusable(GTK_WIDGET(v), TRUE);
	gtk_widget_set_hexpand(GTK_WIDGET(v), TRUE);
	gtk_widget_set_vexpand(GTK_WIDGET(v), TRUE);
	gtk_widget_set_overflow(GTK_WIDGET(v), GTK_OVERFLOW_HIDDEN);
}

GtkWidget *kks_view_new(kks_snap_fn snap, void *user)
{
	KksView *v = g_object_new(kks_view_get_type(), NULL);
	v->snap = snap;
	v->user = user;
	return GTK_WIDGET(v);
}
