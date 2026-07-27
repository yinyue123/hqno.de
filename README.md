# hqno.de — help for people who hold a container

User-facing documentation for hqnode. It is written for someone who has been
given a container and has never seen the panel before: how it becomes theirs,
how to get in, what the limits do when they are reached, and what expiry and
reinstall actually take away.

- [Using your container](using-your-container.md)

Running the machines rather than holding a container is the other side of the
product, and its documentation lives with the code:
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
