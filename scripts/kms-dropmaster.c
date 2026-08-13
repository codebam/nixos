/*
 * LD_PRELOAD shim for ffmpeg's kmsgrab.
 *
 * ffmpeg opens the DRM primary node with a bare open(O_RDWR) (hwcontext_drm.c).
 * The kernel hands DRM master to whoever opens that node while no master exists --
 * which is exactly the situation on a TTY with the compositor gone. The capture then
 * holds master and the compositor cannot start: "Device or resource busy" (EBUSY).
 *
 * kmsgrab does not need master; it imports framebuffers via CAP_SYS_ADMIN. So drop
 * master immediately after the open and stay out of the compositor's way. When a
 * compositor is already master the ioctl just fails harmlessly -- we were never it.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* DRM_IOCTL_DROP_MASTER is _IO('d', 0x1f); not worth linking libdrm for one ioctl. */
#define DROP_MASTER 0x641f

static void maybe_drop(int fd, const char *path)
{
	int ret;

	if (fd < 0 || !path || strncmp(path, "/dev/dri/card", 13))
		return;

	ret = ioctl(fd, DROP_MASTER, 0);
	if (getenv("KMS_DROPMASTER_DEBUG")) {
		char msg[128];
		int n = snprintf(msg, sizeof msg,
		                 "kms-dropmaster: %s fd=%d drop_master=%d errno=%d\n",
		                 path, fd, ret, ret < 0 ? errno : 0);
		if (n > 0) {
			/* debug output only; nothing sensible to do if the write fails */
			ssize_t ignored = write(2, msg, (size_t)n);
			(void)ignored;
		}
	}
}

static int va_mode(int flags, va_list ap)
{
	return (flags & (O_CREAT | O_TMPFILE)) ? va_arg(ap, int) : 0;
}

int open(const char *path, int flags, ...)
{
	static int (*real)(const char *, int, ...);
	va_list ap;
	int mode, fd;

	if (!real)
		real = dlsym(RTLD_NEXT, "open");
	va_start(ap, flags);
	mode = va_mode(flags, ap);
	va_end(ap);

	fd = real(path, flags, mode);
	maybe_drop(fd, path);
	return fd;
}

int open64(const char *path, int flags, ...)
{
	static int (*real)(const char *, int, ...);
	va_list ap;
	int mode, fd;

	if (!real)
		real = dlsym(RTLD_NEXT, "open64");
	va_start(ap, flags);
	mode = va_mode(flags, ap);
	va_end(ap);

	fd = real(path, flags, mode);
	maybe_drop(fd, path);
	return fd;
}

/*
 * Both spellings of each entry point matter: with _FILE_OFFSET_BITS=64 a caller's
 * open()/openat() binds to open64()/openat64(), so wrapping only the short names
 * silently misses everything -- which is exactly how the first version of this shim
 * failed, loading fine while intercepting nothing.
 */
static int openat_common(int (*real)(int, const char *, int, ...), int dirfd,
                         const char *path, int flags, va_list ap)
{
	int mode = va_mode(flags, ap);
	int fd = real(dirfd, path, flags, mode);

	maybe_drop(fd, path);
	return fd;
}

int openat(int dirfd, const char *path, int flags, ...)
{
	static int (*real)(int, const char *, int, ...);
	va_list ap;
	int fd;

	if (!real)
		real = dlsym(RTLD_NEXT, "openat");
	va_start(ap, flags);
	fd = openat_common(real, dirfd, path, flags, ap);
	va_end(ap);
	return fd;
}

int openat64(int dirfd, const char *path, int flags, ...)
{
	static int (*real)(int, const char *, int, ...);
	va_list ap;
	int fd;

	if (!real)
		real = dlsym(RTLD_NEXT, "openat64");
	va_start(ap, flags);
	fd = openat_common(real, dirfd, path, flags, ap);
	va_end(ap);
	return fd;
}
