# Land an SSH login on the wizard instead of a bare shell.
#
# This is a profile.d file rather than a shell in /etc/passwd because the
# hqnode SSH gateway does not read /etc/passwd for a shell: it execs
# `bash -l` (agent/internal/sshgw/session.go), and a login shell reads
# /etc/profile, which Alpine's sources this directory from.
#
# The two guards matter more than the exec does:
#
#   interactive   `su -l <user> -c …` is how the gateway runs SFTP and how it
#                 runs `ssh host command`. Both are login shells and neither
#                 is interactive, so both must fall through to the thing they
#                 were asked to do. `hqnode exec` uses `sh -c` and never
#                 reads a profile at all.
#   NQ_NO_WIZARD  the way back out. The wizard's own "open a shell" sets it,
#                 and so can anybody who wants the container rather than the
#                 page.
case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || true ;;
esac
if [ -z "${NQ_NO_WIZARD:-}" ] && [ -x /usr/local/bin/nq-wizard ] && [ -t 0 ] && [ -t 1 ]; then
	NQ_NO_WIZARD=1
	export NQ_NO_WIZARD
	exec /usr/local/bin/nq-wizard
fi
