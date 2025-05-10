# bold - the *bold* linker

> Bold used to be emerald, but due to time constraints and other commitments I am unable to develop and maintain the other drivers.
> Emerald now lives in another repo -> [kubkon/emerald-old](https://github.com/kubkon/emerald-old).

`bold` is a drop-in replacement for Apple system linker `ld`, written fully in Zig. It is on par with the LLVM lld linker, 
faster than the legacy Apple ld linker, but slower than the rewritten Apple ld linker. Some benchmark results between the linkers 
when linking stage3-zig compiler which includes linking LLVM statically:

```sh
$ hyperfine ./bold.sh ./ld.sh ./ld_legacy.sh ./lld.sh
Benchmark 1: ./bold.sh
  Time (mean ± σ):     978.5 ms ±   9.9 ms    [User: 3083.2 ms, System: 949.2 ms]
  Range (min … max):   967.6 ms … 998.7 ms    10 runs

Benchmark 2: ./ld.sh
  Time (mean ± σ):     439.0 ms ±   5.4 ms    [User: 1769.9 ms, System: 273.1 ms]
  Range (min … max):   432.2 ms … 447.9 ms    10 runs

Benchmark 3: ./ld_legacy.sh
  Time (mean ± σ):      1.986 s ±  0.021 s    [User: 3.100 s, System: 0.221 s]
  Range (min … max):    1.968 s …  2.030 s    10 runs

Benchmark 4: ./lld.sh
  Time (mean ± σ):      1.043 s ±  0.009 s    [User: 1.206 s, System: 0.210 s]
  Range (min … max):    1.031 s …  1.060 s    10 runs

Summary
  ./ld.sh ran
    2.23 ± 0.04 times faster than ./bold.sh
    2.38 ± 0.04 times faster than ./lld.sh
    4.52 ± 0.07 times faster than ./ld_legacy.sh
```

In the results
* `bold.sh` calls `bold` with all the required inputs and flags
* `ld.sh` calls the rewritten Apple linker
* `ld_legacy.sh` calls `ld -ld_classic` the legacy Apple linker
* `lld.sh` calls LLVM lld linker

tl;dr `bold` is currently directly competing with LLVM lld but behind the Apple ld linker.

## Quick start guide

### Building

You will need Zig 0.14.0 in your path. You can download it from [here](https://ziglang.org/download/).

```
$ zig build -Doptimize=ReleaseFast
```

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
$ clang hello.c -fuse-ld=bold

# Using gcc
$ gcc hello.c -B/path/to/bold
```

### Testing

If you'd like to run unit and end-to-end tests, run the tests like you'd normally do for any other Zig project.

```
$ zig build test
```

## Contributing

You are welcome to contribute to this repo.
