# Building your own image

*Stub. The reinstall dialog links here from **How to build your own image**,
and until this page is published that button points at a placeholder URL
(`buildImageHelpURL` in `server/internal/api/me.go`). Swap the constant when
this is live.*

*The same box is on the new-container form now (image.md §10), so the page has
two doors to answer for rather than one: a machine's owner may name a reference
at create, and a holder brings one by reinstalling.*

## What this page has to answer

Someone holding a container has been shown a box that wants a full registry
reference, and the question underneath it is "what do I put in there". The
page needs to get them from nothing to a reference their host can boot.

- **What hqnode boots.** An OCI image whose entrypoint is an init that can be
  PID 1. The system images this project publishes run systemd; an image with
  no init still starts, and the panel says what it is rather than pretending
  it is a system container.
- **The two things that go wrong.** `linux/amd64` (or the host's actual
  architecture — an index with no matching platform is refused, not silently
  substituted), and the stop signal: systemd wants `SIGRTMIN+3`, and an image
  that does not declare it turns every stop into a 30-second wait followed by
  a kill.
- **A worked example.** A `Dockerfile` from one of the published images, built
  and pushed to a registry the host can reach, then pasted into the dialog.
- **Where it goes, and what it costs.** Their image is downloaded in full and
  expanded into their container's own disk. Nothing is shared with anyone,
  nothing is kept on the host between reinstalls, the download happens again
  every time, and every byte of it is charged to that container's traffic.
  This is the part the dialog can only say in one line and this page should
  say properly.
- **Private registries.** What the host can and cannot authenticate to, and
  who to ask.

See [image.md](https://github.com/yinyue123/hqnode/blob/main/image.md) §1 and
§3.2 for the behaviour this describes.
