# Roadmap

Goal: an OS whose defaults are built around a personal development workflow
with AI tools in the loop — not a general-purpose distro.

Each item below should land as its own commit against the vanilla baseline.

## 0. Baseline
- [x] Import vanilla `releng` profile (archiso v92)
- [ ] Pick a name; set `iso_name`, `iso_label`, `iso_publisher`, `iso_application`
- [ ] Confirm a stock build boots in QEMU before changing anything

## 1. Developer base
- [ ] Core toolchain: `base-devel`, `git`, `github-cli`, language runtimes in daily use
- [ ] Shell, editor, and terminal of choice with dotfiles in `airootfs/etc/skel`
- [ ] Container tooling (`podman` or `docker`)

## 2. AI tooling
- [ ] AI coding agents and CLIs preinstalled (e.g. Claude Code)
- [ ] Local inference option (`ollama` / `llama.cpp`) with GPU drivers for the target hardware
- [ ] Secrets handling for API keys (no keys baked into the image)

## 3. Installer & persistence
- [ ] Decide: live-only, or an installer (`archinstall` config) that reproduces this setup on disk
- [ ] Custom package repo for anything not in the official repos / AUR builds

## 4. Polish
- [ ] Branding: boot menu, motd, hostname
- [ ] CI build of the ISO
