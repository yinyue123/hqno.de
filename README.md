# hqno.de — help for people who hold a container

User-facing documentation for hqnode. It is written for someone who has been
given a container and has never seen the panel before: how it becomes theirs,
how to get in, what the limits do when they are reached, and what expiry and
reinstall actually take away.

Published as a VitePress site at [doc.hqno.de](https://doc.hqno.de) — the panel
itself is `hqno.de`, and the panel links here by one constant, `DOCS_BASE` in
`web/lib/docs.ts`, so this address is changed in two places and no more. Every
page lives under [`docs/`](docs/), which is what the site is built from:

- [How this works](docs/how-it-works.md)
- [Quick start](docs/quick-start.md)
- [Using your container](docs/using-your-container.md)
- [Adding your own software to app-setup](docs/app-setup-sources.md)
- [Building your own image](docs/building-your-own-image.md)
- [Running a machine of your own](docs/running-a-machine.md)

Chinese lives beside them in [`docs/zh/`](docs/zh/), one file per translated
page, and the theme grows a language menu from the `locales` block in
`docs/.vitepress/config.ts`. English is the root locale, so its addresses stay
unprefixed and every link anyone has already sent still answers.

A locale does not have to be complete: the three pages a beginner needs are
translated, and the Chinese sidebar links straight at the English copies of the
rest, labelled `（英文）`. Two things to know when adding a language:

- link to an untranslated page with an absolute path (`/using-your-container`).
  A relative one resolves inside the locale directory, where there is no file,
  and the build fails on it — which is the check working.
- **do not draw a box around Chinese text.** A browser does not render CJK at
  exactly twice the width of a Latin character, so a frame that is square in a
  terminal comes out ragged on the page. The Chinese figures use a left border
  and an open right edge, and every column boundary sits *before* the first CJK
  character on the line. Wide grids become real markdown tables instead.

```sh
npm install
npm run docs:dev      # http://localhost:5173
npm run docs:build    # → docs/.vitepress/dist
```

Cloudflare Pages builds it:

| Setting | Value |
|---|---|
| Build output directory | `.vitepress/dist` |
| Build command | anything below |

`npx vitepress build`, `npx vitepress build docs` and `npm run docs:build` all
produce the same themed pages in `.vitepress/dist`. That is deliberate, and
neither half of it used to be true.

The argument names the VitePress root. Without it VitePress takes the
*repository* root, loads no configuration at all, and treats every markdown file
in the tree as a page — including `images/README.md`, whose link to the
`app-setup/` source directory is correct on GitHub and is not a page anywhere.
Three deploys died on that link. Failing was better than publishing the whole
repository unthemed, but neither is a site, and the build command lives in a
dashboard rather than in this repository — so this is the wrong place to keep
being right about it. `.vitepress/config.ts` at the root points a rootless build
back at `docs/`; it holds `srcDir` and `outDir` and nothing else, with a
one-line shim beside it for the theme. The configuration itself stays in
`docs/.vitepress/config.ts`, next to the pages.

Then the fourth deploy built and still failed, because the output was written
where the *command* implied rather than where Pages was told to look. So both
configurations now name one directory, `<repo>/.vitepress/dist`. One path can be
wrong, but it cannot be right for one command and wrong for another.

It also builds and publishes the system images a container is installed from —
one public package, `ghcr.io/yinyue123/hqnode`, one tag per system. See
[`images/`](images/README.md). They live here rather than with the product
because they are published: a panel pulls them by name, from anywhere, without
a credential.

Running the machines rather than holding a container is the other side of the
product, and it has a page here now:
[running a machine of your own](docs/running-a-machine.md). The deeper end of it
— agent internals, moving the listeners, storage — stays with the code, in
[operating the panel](https://github.com/yinyue123/hqnode/blob/main/docs/operating-the-panel.md).

## How this repo is used

It is a submodule of [hqnode](https://github.com/yinyue123/hqnode), checked out
at `help/`. It is separate because it is published — it is what the site serves
— and because it changes on its own schedule: a wording fix here should not
need a commit in the product repo, and a refactor there should not drag the
help along with it.

Working on it from inside hqnode:

```sh
git submodule update --init help    # first time, or after cloning hqnode
cd help
git checkout main                   # a submodule starts detached
# edit, commit, push as a normal repo
cd ..
git add help && git commit -m "Update help"   # record the new commit in hqnode
```

The parent repo records *which commit* of this one it goes with, so it does not
move until someone says so.

## House rules

- Say what happens, not what the button is called.
- Every claim is checkable against the code. If the panel cannot do something
  yet, say so plainly rather than describing the intent.
- No screenshots. They are the first thing to rot.
