# emerald

`emerald` is a drop-in replacement for your system linker `ld` written in Zig. Currently, the main development effort is focused on the MachO
driver. MachO driver is on par with the LLVM lld linker, faster than the legacy Apple ld linker, but slower than the rewritten Apple ld linker.
Some benchmark results between the linkers when linking stage3-zig compiler which includes linking LLVM statically:

```sh
$ hyperfine ./emerald.sh ./ld.sh ./ld_legacy.sh ./lld.sh
Benchmark 1: ./emerald.sh
  Time (mean ± σ):      1.088 s ±  0.018 s    [User: 3.174 s, System: 1.004 s]
  Range (min … max):    1.039 s …  1.104 s    10 runs

Benchmark 2: ./ld.sh
  Time (mean ± σ):     491.8 ms ±  19.5 ms    [User: 1891.5 ms, System: 304.7 ms]
  Range (min … max):   458.1 ms … 509.9 ms    10 runs

Benchmark 3: ./ld_legacy.sh
  Time (mean ± σ):      2.132 s ±  0.013 s    [User: 3.242 s, System: 0.256 s]
  Range (min … max):    2.104 s …  2.150 s    10 runs

Benchmark 4: ./lld.sh
  Time (mean ± σ):      1.160 s ±  0.021 s    [User: 1.329 s, System: 0.247 s]
  Range (min … max):    1.133 s …  1.208 s    10 runs

Summary
  ./ld.sh ran
    2.21 ± 0.10 times faster than ./emerald.sh
    2.36 ± 0.10 times faster than ./lld.sh
    4.33 ± 0.17 times faster than ./ld_legacy.sh
```

In the results
* `emerald.sh` calls `emerald` with all the required inputs and flags
* `ld.sh` calls the rewritten Apple linker
* `ld_legacy.sh` calls `ld -ld_classic` the legacy Apple linker
* `lld.sh` calls LLVM lld linker

The tl;dr is `emerald` is currently directly competing with LLVM lld but behind the Apple ld linker.

## Quick start guide

### Building

You will need Zig 0.13.0 in your path. You can download it from [here](https://ziglang.org/download/).

```
$ zig build -Doptimize=ReleaseFast
```

This will create the `ld.emerald` (Elf), `ld64.emerald` (MachO), `emerald-link.exe` (Coff) and `wasm-emerald` (Wasm) binaries in `zig-out/bin/`.
You can then pass it to your system C/C++ compiler with `-B` or `-fuse-ld` flag (note that the latter is supported mainly/only by clang):

```
$ cat <<EOF > hello.c
#include <stdio.h>

int main() {
    fprintf(stderr, "Hello, World!\n");
    return 0;
}
EOF

# Using clang
$ clang hello.c -fuse-ld=ld64.emerald

# Using gcc
$ gcc hello.c -B/path/to/ld64.emerald
```

### Testing

If you'd like to run unit and end-to-end tests, run the tests like you'd normally do for any other Zig project.

```
$ zig build test
```

## Supported backends

- [x] Mach-O (x86_64)
- [x] Mach-O (aarch64)
- [x] ELF (x86_64)
- [x] ELF (aarch64)
- [ ] ELF (riscv64)
- [ ] COFF (x86_64)
- [ ] COFF (aarch64)
- [x] Wasm (static)

## Contributing

You are welcome to contribute to this repo.
