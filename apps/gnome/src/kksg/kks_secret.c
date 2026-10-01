/* The device's storage key in the user's keyring through libsecret (decision 0020, 0031). The key is stored as
   base64 text under the schema org.kks.Explorer with kind=storage-key and the data folder, so two data folders
   (tests, a second profile) keep separate keys. */
#include <libsecret/secret.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static const SecretSchema schema = {
	"org.kks.Explorer", SECRET_SCHEMA_NONE,
	{ {"kind", SECRET_SCHEMA_ATTRIBUTE_STRING}, {"folder", SECRET_SCHEMA_ATTRIBUTE_STRING}, {NULL, 0} }
};

static char err_buf[512];
const char *kks_secret_error(void) { return err_buf; }

/* Returns a malloc'd copy of the stored text, NULL if none (err_buf empty) or on error (err_buf set). */
char *kks_secret_lookup(const char *folder)
{
	GError *e = NULL;
	err_buf[0] = 0;
	gchar *pw = secret_password_lookup_sync(&schema, NULL, &e, "kind", "storage-key", "folder", folder, NULL);
	if (e) { snprintf(err_buf, sizeof err_buf, "%s", e->message); g_error_free(e); return NULL; }
	if (!pw) return NULL;
	char *out = strdup(pw);
	secret_password_free(pw);
	return out;
}

int kks_secret_store(const char *folder, const char *text)
{
	GError *e = NULL;
	err_buf[0] = 0;
	gboolean ok = secret_password_store_sync(&schema, SECRET_COLLECTION_DEFAULT, "KKS Explorer storage key", text,
	                                         NULL, &e, "kind", "storage-key", "folder", folder, NULL);
	if (e) { snprintf(err_buf, sizeof err_buf, "%s", e->message); g_error_free(e); return 0; }
	return ok;
}

int kks_secret_clear(const char *folder)
{
	GError *e = NULL;
	gboolean ok = secret_password_clear_sync(&schema, NULL, &e, "kind", "storage-key", "folder", folder, NULL);
	if (e) { g_error_free(e); return 0; }
	return ok;
}
