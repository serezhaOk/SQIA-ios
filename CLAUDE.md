# Working on SQIA

## Always end an update with a pull command

Every time work is pushed — every commit, every follow-up, every fix — end
the reply with a fenced shell block the author can copy straight into a
terminal to get that push onto their machine. Not a description of it, the
command itself, with the real branch name filled in:

```sh
git fetch origin <branch> && git switch <branch> && git pull --ff-only
```

`git switch` creates the local branch tracking `origin/<branch>` the first
time and simply moves to it afterwards; `--ff-only` refuses rather than
merging over local work.

Add `&& open SQIA.xcodeproj` when the push changes resources or the project
structure, since Xcode has to re-read the bundle for those.
