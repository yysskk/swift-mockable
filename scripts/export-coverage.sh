#!/usr/bin/env bash
#
# Runs the test suite with code coverage enabled and exports the result as an
# lcov report — the format Codecov consumes.
#
# Usage:
#   scripts/export-coverage.sh [output-file]
#
# The report defaults to `coverage.lcov` in the repository root. A human
# readable summary is printed to stdout as well.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

# The export runs from the repository root, so resolve a relative output path
# against the caller's directory before moving there.
output="${1:-${repo_root}/coverage.lcov}"
[[ "${output}" == /* ]] || output="$(pwd)/${output}"
readonly output

# Coverage measures the shipped sources only. Test code and the dependency
# sources checked out under .build are not part of the metric.
readonly excluded_paths='(^|/)(\.build|Tests)/'

cd "${repo_root}"

# llvm-cov lives inside the active toolchain on macOS and on PATH in the
# official Swift container images.
if command -v xcrun >/dev/null 2>&1; then
    llvm_cov=(xcrun llvm-cov)
elif command -v llvm-cov >/dev/null 2>&1; then
    llvm_cov=(llvm-cov)
else
    echo "error: llvm-cov not found; install the Swift toolchain's LLVM tools." >&2
    exit 1
fi

swift test --enable-code-coverage

bin_path="$(swift build --show-bin-path)"
readonly bin_path
readonly profdata="${bin_path}/codecov/default.profdata"

if [[ ! -f "${profdata}" ]]; then
    echo "error: no coverage profile at ${profdata}." >&2
    exit 1
fi

# The native build system emits one test product for the whole package, and
# the Swift Build backend (the default from Swift 6.4) one per test target.
# Each is a bundle directory on Darwin and a bare executable on Linux, except
# that the Swift Build backend on Linux emits a shared library loaded by a
# `-test-runner` executable. Coverage is merged across all of them.
test_binaries=()
for bundle in "${bin_path}"/*.xctest; do
    if [[ -d "${bundle}" ]]; then
        test_binaries+=("${bundle}/Contents/MacOS/$(basename "${bundle}" .xctest)")
    elif [[ -f "${bundle}" ]]; then
        test_binaries+=("${bundle}")
    fi
done
for runner in "${bin_path}"/*-test-runner; do
    library="${runner%-test-runner}.so"
    if [[ -f "${library}" ]]; then
        test_binaries+=("${library}")
    fi
done
readonly test_binaries

if [[ ${#test_binaries[@]} -eq 0 ]]; then
    echo "error: no test binary found in ${bin_path}." >&2
    exit 1
fi

# llvm-cov takes the first binary positionally and the rest through -object.
llvm_cov_objects=("${test_binaries[0]}")
for binary in "${test_binaries[@]:1}"; do
    llvm_cov_objects+=(-object "${binary}")
done
readonly llvm_cov_objects

# llvm-cov records absolute source paths. Codecov matches coverage against the
# repository tree, so rewrite them relative to the repository root.
"${llvm_cov[@]}" export -format=lcov "${llvm_cov_objects[@]}" \
    -instr-profile "${profdata}" \
    -ignore-filename-regex="${excluded_paths}" \
    | awk -v prefix="SF:${repo_root}/" '
        index($0, prefix) == 1 { $0 = "SF:" substr($0, length(prefix) + 1) }
        { print }
    ' > "${output}"

"${llvm_cov[@]}" report "${llvm_cov_objects[@]}" \
    -instr-profile "${profdata}" \
    -ignore-filename-regex="${excluded_paths}"

echo "Wrote lcov report to ${output}"
