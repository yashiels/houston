#!/usr/bin/env bash
# setup-git-fixtures.sh — Create temporary git repos for testing.
# Source this file in bats setup() and call create_git_fixtures.
# Call cleanup_git_fixtures in teardown().

create_git_fixtures() {
  local fixtures_dir="$1"

  # fake-github-repo
  mkdir -p "$fixtures_dir/fake-github-repo"
  git init "$fixtures_dir/fake-github-repo" >/dev/null 2>&1
  git -C "$fixtures_dir/fake-github-repo" remote add origin git@github.com:stitch-Money/some-service.git 2>/dev/null || true

  # fake-gitlab-repo
  mkdir -p "$fixtures_dir/fake-gitlab-repo"
  git init "$fixtures_dir/fake-gitlab-repo" >/dev/null 2>&1
  git -C "$fixtures_dir/fake-gitlab-repo" remote add origin git@gitlab.com:exipay/pos/exi-terminal-app.git 2>/dev/null || true

  # fake-personal-repo — set identity to yashiels so apex profile doesn't win via global identity
  mkdir -p "$fixtures_dir/fake-personal-repo"
  git init "$fixtures_dir/fake-personal-repo" >/dev/null 2>&1
  git -C "$fixtures_dir/fake-personal-repo" remote add origin git@github.com:skynergroup/some-project.git 2>/dev/null || true
  git -C "$fixtures_dir/fake-personal-repo" config user.email "yashiel@skyner.co.za" 2>/dev/null || true
  git -C "$fixtures_dir/fake-personal-repo" config user.name "Yashiel Sookdeo" 2>/dev/null || true
}

cleanup_git_fixtures() {
  local fixtures_dir="$1"
  rm -rf "$fixtures_dir/fake-github-repo"
  rm -rf "$fixtures_dir/fake-gitlab-repo"
  rm -rf "$fixtures_dir/fake-personal-repo"
}
