# NERS 590 term project

This repository keeps the simulation code and paper together. The paper is a
Git submodule connected directly to its Overleaf project.

- `code/`: Julia project and simulation code.
- `paper/`: LaTeX source, tracked in the separate Overleaf repository.
- `term_paper_description.pdf`: assignment requirements.

## Clone the whole project

```bash
git clone --recurse-submodules <project-repository-url>
```

After a regular clone, initialize the paper with:

```bash
git submodule update --init --recursive
```

A submodule records a specific paper commit. These commands restore that version;
they do not automatically follow the latest Overleaf edits.

## Edit and publish the paper

Run from the top-level `term_project` directory:

```bash
git -C paper switch main
git -C paper pull --ff-only origin main
# Edit the LaTeX source, then review the changes.
git -C paper add .
git -C paper commit -m "Update paper"
git -C paper push origin main
# Record the new paper version in the parent repository.
git add paper
git commit -m "Update paper submodule"
```

If the parent has a remote, push the parent commit separately with `git push`.
Push the paper first so the parent never points at an unpublished paper commit.
Overleaf authentication uses a Git token stored through your credential manager;
do not put a token in `.gitmodules` or a remote URL.

## Bring Overleaf changes into this project

With a clean paper working tree:

```bash
git -C paper switch main
git -C paper pull --ff-only origin main
git add paper
git commit -m "Sync paper from Overleaf"
```

After pulling updates to the parent repository, restore its recorded paper version
with `git submodule update --init --recursive`. This may leave the paper in detached
HEAD state; switch back to `main` before making new paper commits.

The paper's `.gitignore` excludes generated LaTeX files, compiled document PDFs,
and local backups while allowing source figures to be tracked.
