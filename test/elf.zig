pub fn addElfTests(b: *Build, opts: Options) *Step {
    const elf_step = b.step("test-elf", "Run ELF tests");

    if (builtin.target.ofmt == .elf) {
        elf_step.dependOn(testAbsSymbols(b, opts));
        elf_step.dependOn(testAllowMultipleDefinitions(b, opts));
        elf_step.dependOn(testAsNeeded(b, opts));
        elf_step.dependOn(testCanonicalPlt(b, opts));
        elf_step.dependOn(testCommon(b, opts));
        elf_step.dependOn(testCopyrel(b, opts));
        elf_step.dependOn(testCopyrelAlias(b, opts));
        elf_step.dependOn(testDsoIfunc(b, opts));
        elf_step.dependOn(testDsoPlt(b, opts));
        elf_step.dependOn(testIfuncAlias(b, opts));
        elf_step.dependOn(testIfuncDynamic(b, opts));
        elf_step.dependOn(testIfuncFuncPtr(b, opts));
        elf_step.dependOn(testIfuncNoPlt(b, opts));
        elf_step.dependOn(testIfuncStatic(b, opts));
        elf_step.dependOn(testIfuncStaticPie(b, opts));
        elf_step.dependOn(testHelloDynamic(b, opts));
        elf_step.dependOn(testHelloPie(b, opts));
        elf_step.dependOn(testHelloStatic(b, opts));
        elf_step.dependOn(testTlsDesc(b, opts));
        elf_step.dependOn(testTlsDescImport(b, opts));
        elf_step.dependOn(testTlsDescStatic(b, opts));
        elf_step.dependOn(testTlsDso(b, opts));
        elf_step.dependOn(testTlsGd(b, opts));
        elf_step.dependOn(testTlsIe(b, opts));
        elf_step.dependOn(testTlsLd(b, opts));
        elf_step.dependOn(testTlsLdDso(b, opts));
        elf_step.dependOn(testTlsStatic(b, opts));
    }

    return elf_step;
}

fn testAbsSymbols(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-abs-symbols", "");

    const obj = cc(b, opts);
    obj.addAsmSource(
        \\.globl foo
        \\foo = 0x800008
        \\
    );
    obj.addArg("-c");
    const obj_out = obj.saveOutputAs("a.o");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#define _GNU_SOURCE 1
        \\#include <signal.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <ucontext.h>
        \\#include <assert.h>
        \\void handler(int signum, siginfo_t *info, void *ptr) {
        \\  assert((size_t)info->si_addr == 0x800008);
        \\  exit(0);
        \\}
        \\extern volatile int foo;
        \\int main() {
        \\  struct sigaction act;
        \\  act.sa_flags = SA_SIGINFO | SA_RESETHAND;
        \\  act.sa_sigaction = handler;
        \\  sigemptyset(&act.sa_mask);
        \\  sigaction(SIGSEGV, &act, 0);
        \\  foo = 5;
        \\}
    );
    exe.addArg("-fno-PIC");
    exe.addFileSource(obj_out.file);

    const run = exe.run();
    test_step.dependOn(run.step());

    return test_step;
}

fn testAllowMultipleDefinitions(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-allow-multiple-definitions", "");

    const a_o = cc(b, opts);
    a_o.addCSource("int main() { return 0; }");
    a_o.addArg("-c");
    const a_o_out = a_o.saveOutputAs("a.o");

    const b_o = cc(b, opts);
    b_o.addCSource("int main() { return 1; }");
    b_o.addArg("-c");
    const b_o_out = b_o.saveOutputAs("b.o");

    {
        const exe = cc(b, opts);
        exe.addFileSource(a_o_out.file);
        exe.addFileSource(b_o_out.file);
        exe.addArg("-Wl,--allow-multiple-definition");

        const run = exe.run();
        test_step.dependOn(run.step());
    }
    {
        const exe = cc(b, opts);
        exe.addFileSource(a_o_out.file);
        exe.addFileSource(b_o_out.file);
        exe.addArg("-Wl,-z,muldefs");

        const run = exe.run();
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testAsNeeded(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-as-needed", "");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\int baz();
        \\int main() {
        \\  printf("%d\n", baz());
        \\  return 0;
        \\}
    );
    main_o.addArg("-c");
    const main_o_out = main_o.saveOutputAs("main.o");

    const libfoo = cc(b, opts);
    libfoo.addCSource("int foo() { return 42; }");
    libfoo.addArgs(&.{ "-shared", "-fPIC", "-Wl,-soname,libfoo.so" });
    const libfoo_out = libfoo.saveOutputAs("libfoo.so");

    const libbar = cc(b, opts);
    libbar.addCSource("int bar() { return 42; }");
    libbar.addArgs(&.{ "-shared", "-fPIC", "-Wl,-soname,libbar.so" });
    const libbar_out = libbar.saveOutputAs("libbar.so");

    const libbaz = cc(b, opts);
    libbaz.addCSource(
        \\int foo();
        \\int baz() { return foo(); }
    );
    libbaz.addArgs(&.{ "-shared", "-fPIC", "-Wl,-soname,libbaz.so", "-lfoo" });
    libbaz.addPrefixedDirectorySource("-L", libfoo_out.dir);
    const libbaz_out = libbaz.saveOutputAs("libbaz.so");

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addArg("-Wl,--no-as-needed");
        exe.addFileSource(libfoo_out.file);
        exe.addFileSource(libbar_out.file);
        exe.addFileSource(libbaz_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libfoo_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libbar_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libbaz_out.dir);

        const run = exe.run();
        run.expectStdOutEqual("42\n");
        test_step.dependOn(run.step());

        const check = exe.check();
        check.checkStart("NEEDED libfoo.so");
        check.checkNext("NEEDED libbar.so");
        check.checkNext("NEEDED libbaz.so");
        test_step.dependOn(&check.step);
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addArg("-Wl,--as-needed");
        exe.addFileSource(libfoo_out.file);
        exe.addFileSource(libbar_out.file);
        exe.addFileSource(libbaz_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libfoo_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libbar_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", libbaz_out.dir);

        const run = exe.run();
        run.expectStdOutEqual("42\n");
        test_step.dependOn(run.step());

        const check = exe.check();
        check.checkStart("NEEDED libfoo.so");
        check.checkNotPresent("NEEDED libbar.so");
        check.checkStart("NEEDED libbaz.so");
        test_step.dependOn(&check.step);
    }

    return test_step;
}

fn testCanonicalPlt(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-canonical-plt", "");

    const dso = cc(b, opts);
    dso.addCSource(
        \\void *foo() {
        \\  return foo;
        \\}
        \\void *bar() {
        \\  return bar;
        \\}
    );
    dso.addArgs(&.{ "-fPIC", "-shared" });
    const dso_out = dso.saveOutputAs("a.so");

    const b_o = cc(b, opts);
    b_o.addCSource(
        \\void *bar();
        \\void *baz() {
        \\  return bar;
        \\}
    );
    b_o.addArgs(&.{ "-fPIC", "-c" });
    const b_o_out = b_o.saveOutputAs("b.o");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <assert.h>
        \\void *foo();
        \\void *bar();
        \\void *baz();
        \\int main() {
        \\  assert(foo == foo());
        \\  assert(bar == bar());
        \\  assert(bar == baz());
        \\}
    );
    main_o.addArgs(&.{ "-fno-PIC", "-c" });
    const main_o_out = main_o.saveOutputAs("main.o");

    const exe = cc(b, opts);
    exe.addFileSource(main_o_out.file);
    exe.addFileSource(b_o_out.file);
    exe.addFileSource(dso_out.file);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);
    exe.addArg("-no-pie");

    const run = exe.run();
    test_step.dependOn(run.step());

    return test_step;
}

fn testCommon(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-common", "");

    const exe = cc(b, opts);
    exe.addCSource(
        \\int foo;
        \\int bar;
        \\int baz = 42;
    );
    exe.addCSource(
        \\#include<stdio.h>
        \\int foo;
        \\int bar = 5;
        \\int baz;
        \\int main() {
        \\  printf("%d %d %d\n", foo, bar, baz);
        \\}
    );
    exe.addArg("-fcommon");

    const run = exe.run();
    run.expectStdOutEqual("0 5 42\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testCopyrel(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-copyrel", "");

    const dso = cc(b, opts);
    dso.addArgs(&.{ "-fPIC", "-shared" });
    dso.addCSource(
        \\int foo = 3;
        \\int bar = 5;
    );
    const dso_out = dso.saveOutputAs("liba.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include<stdio.h>
        \\extern int foo, bar;
        \\int main() {
        \\  printf("%d %d\n", foo, bar);
        \\  return 0;
        \\}
    );
    exe.addArg("-la");
    exe.addPrefixedDirectorySource("-L", dso_out.dir);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("3 5\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testCopyrelAlias(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-copyrel-alias", "");

    const dso = cc(b, opts);
    dso.addArgs(&.{ "-fPIC", "-shared" });
    dso.addCSource(
        \\int bruh = 31;
        \\int foo = 42;
        \\extern int bar __attribute__((alias("foo")));
        \\extern int baz __attribute__((alias("foo")));
    );
    const dso_out = dso.saveOutputAs("c.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include<stdio.h>
        \\extern int foo;
        \\extern int *get_bar();
        \\int main() {
        \\  printf("%d %d %d\n", foo, *get_bar(), &foo == get_bar());
        \\  return 0;
        \\}
    );
    exe.addCSource(
        \\extern int bar;
        \\int *get_bar() { return &bar; }
    );
    exe.addArgs(&.{ "-fno-PIC", "-no-pie" });
    exe.addFileSource(dso_out.file);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("42 42 1\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testDsoIfunc(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-dso-ifunc", "");

    const dso = cc(b, opts);
    dso.addArgs(&.{ "-fPIC", "-shared" });
    dso.addCSource(
        \\#include<stdio.h>
        \\__attribute__((ifunc("resolve_foobar")))
        \\void foobar(void);
        \\static void real_foobar(void) {
        \\  printf("Hello world\n");
        \\}
        \\typedef void Func();
        \\static Func *resolve_foobar(void) {
        \\  return real_foobar;
        \\}
    );
    const dso_out = dso.saveOutputAs("liba.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\void foobar(void);
        \\int main() {
        \\  foobar();
        \\}
    );
    exe.addArg("-la");
    exe.addPrefixedDirectorySource("-L", dso_out.dir);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("Hello world\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testDsoPlt(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-dso-plt", "");

    const dso = cc(b, opts);
    dso.addArgs(&.{ "-fPIC", "-shared" });
    dso.addCSource(
        \\#include<stdio.h>
        \\void world() {
        \\  printf("world\n");
        \\}
        \\void real_hello() {
        \\  printf("Hello ");
        \\  world();
        \\}
        \\void hello() {
        \\  real_hello();
        \\}
    );
    const dso_out = dso.saveOutputAs("liba.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include<stdio.h>
        \\void world() {
        \\  printf("WORLD\n");
        \\}
        \\void hello();
        \\int main() {
        \\  hello();
        \\}
    );
    exe.addArg("-la");
    exe.addPrefixedDirectorySource("-L", dso_out.dir);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("Hello WORLD\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testIfuncAlias(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-alias", "");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <assert.h>
        \\void foo() {}
        \\int bar() __attribute__((ifunc("resolve_bar")));
        \\void *resolve_bar() { return foo; }
        \\void *bar2 = bar;
        \\int main() {
        \\  assert(bar == bar2);
        \\}
    );
    exe.addArg("-fPIC");

    const run = exe.run();
    test_step.dependOn(run.step());

    return test_step;
}

fn testIfuncDynamic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-dynamic", "");

    const main_c =
        \\#include <stdio.h>
        \\__attribute__((ifunc("resolve_foobar")))
        \\static void foobar(void);
        \\static void real_foobar(void) {
        \\  printf("Hello world\n");
        \\}
        \\typedef void Func();
        \\static Func *resolve_foobar(void) {
        \\  return real_foobar;
        \\}
        \\int main() {
        \\  foobar();
        \\}
    ;

    {
        const exe = cc(b, opts);
        exe.addCSource(main_c);
        exe.addArg("-Wl,-z,lazy");

        const run = exe.run();
        run.expectStdOutEqual("Hello world\n");
        test_step.dependOn(run.step());
    }
    {
        const exe = cc(b, opts);
        exe.addCSource(main_c);
        exe.addArg("-Wl,-z,now");

        const run = exe.run();
        run.expectStdOutEqual("Hello world\n");
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testIfuncFuncPtr(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-func-ptr", "");

    const exe = cc(b, opts);
    exe.addCSource(
        \\typedef int Fn();
        \\int foo() __attribute__((ifunc("resolve_foo")));
        \\int real_foo() { return 3; }
        \\Fn *resolve_foo(void) {
        \\  return real_foo;
        \\}
    );
    exe.addCSource(
        \\typedef int Fn();
        \\int foo();
        \\Fn *get_foo() { return foo; }
    );
    exe.addCSource(
        \\#include <stdio.h>
        \\typedef int Fn();
        \\Fn *get_foo();
        \\int main() {
        \\  Fn *f = get_foo();
        \\  printf("%d\n", f());
        \\}
    );
    exe.addArg("-fPIC");

    const run = exe.run();
    run.expectStdOutEqual("3\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testIfuncNoPlt(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-noplt", "");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\__attribute__((ifunc("resolve_foo")))
        \\void foo(void);
        \\void hello(void) {
        \\  printf("Hello world\n");
        \\}
        \\typedef void Fn();
        \\Fn *resolve_foo(void) {
        \\  return hello;
        \\}
        \\int main() {
        \\  foo();
        \\}
    );
    exe.addArgs(&.{ "-fPIC", "-fno-plt" });

    const run = exe.run();
    run.expectStdOutEqual("Hello world\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testIfuncStatic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-static", "");

    if (!opts.has_static) {
        skipTestStep(test_step);
        return test_step;
    }

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\void foo() __attribute__((ifunc("resolve_foo")));
        \\void hello() {
        \\  printf("Hello world\n");
        \\}
        \\void *resolve_foo() {
        \\  return hello;
        \\}
        \\int main() {
        \\  foo();
        \\  return 0;
        \\}
    );
    exe.addArgs(&.{"-static"});

    const run = exe.run();
    run.expectStdOutEqual("Hello world\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testIfuncStaticPie(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-ifunc-static-pie", "");

    if (!opts.has_static_pie) {
        skipTestStep(test_step);
        return test_step;
    }

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\void foo() __attribute__((ifunc("resolve_foo")));
        \\void hello() {
        \\  printf("Hello world\n");
        \\}
        \\void *resolve_foo() {
        \\  return hello;
        \\}
        \\int main() {
        \\  foo();
        \\  return 0;
        \\}
    );
    exe.addArgs(&.{ "-fPIC", "-static-pie" });

    const run = exe.run();
    run.expectStdOutEqual("Hello world\n");
    test_step.dependOn(run.step());

    const check = exe.check();
    check.checkStart("header");
    check.checkNext("type DYN");
    check.checkStart("shdr {*}");
    check.checkNext("name .dynamic");
    check.checkStart("shdr {*}");
    check.checkNotPresent("name .interp");
    test_step.dependOn(&check.step);

    return test_step;
}

fn testHelloStatic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-hello-static", "");

    if (!opts.has_static) {
        skipTestStep(test_step);
        return test_step;
    }

    const exe = cc(b, opts);
    exe.addHelloWorldMain();
    exe.addArg("-static");

    const run = exe.run();
    run.expectHelloWorld();
    test_step.dependOn(run.step());

    const check = exe.check();
    check.checkStart("header");
    check.checkNext("type EXEC");
    check.checkStart("shdr {*}");
    check.checkNotPresent("name .dynamic");
    test_step.dependOn(&check.step);

    return test_step;
}

fn testHelloDynamic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-hello-dynamic", "");

    const exe = cc(b, opts);
    exe.addHelloWorldMain();
    exe.addArg("-no-pie");

    const run = exe.run();
    run.expectHelloWorld();
    test_step.dependOn(run.step());

    const check = exe.check();
    check.checkStart("header");
    check.checkNext("type EXEC");
    check.checkStart("shdr {*}");
    check.checkNext("name .dynamic");
    test_step.dependOn(&check.step);

    return test_step;
}

fn testHelloPie(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-hello-pie", "");

    const exe = cc(b, opts);
    exe.addHelloWorldMain();
    exe.addArgs(&.{ "-fPIC", "-pie" });

    const run = exe.run();
    run.expectHelloWorld();
    test_step.dependOn(run.step());

    const check = exe.check();
    check.checkStart("header");
    check.checkNext("type DYN");
    check.checkStart("shdr {*}");
    check.checkNext("name .dynamic");
    test_step.dependOn(&check.step);

    return test_step;
}

fn testTlsDesc(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-desc", "");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\_Thread_local int foo;
        \\int get_foo();
        \\int get_bar();
        \\int main() {
        \\  foo = 42;
        \\  printf("%d %d\n", get_foo(), get_bar());
        \\  return 0;
        \\}
    );
    main_o.addArgs(&.{ "-c", "-fPIC", "-mtls-dialect=gnu2" });
    const main_o_out = main_o.saveOutputAs("main.o");

    const a_o = cc(b, opts);
    a_o.addCSource(
        \\extern _Thread_local int foo;
        \\int get_foo() {
        \\  return foo;
        \\}
        \\static _Thread_local int bar = 5;
        \\int get_bar() {
        \\  return bar;
        \\}
    );
    a_o.addArgs(&.{ "-c", "-fPIC", "-mtls-dialect=gnu2" });
    const a_o_out = a_o.saveOutputAs("a.o");

    const exp_stdout = "42 5\n";

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);
        exe.addArg("-Wl,-no-relax");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const dso = cc(b, opts);
        dso.addFileSource(a_o_out.file);
        dso.addArg("-shared");
        const dso_out = dso.saveOutputAs("a.so");

        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(dso_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const dso = cc(b, opts);
        dso.addFileSource(a_o_out.file);
        dso.addArgs(&.{ "-shared", "-Wl,-no-relax" });
        const dso_out = dso.saveOutputAs("a.so");

        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(dso_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);
        exe.addArg("-Wl,-no-relax");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testTlsDescImport(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-desc-import", "");

    const dso = cc(b, opts);
    dso.addCSource(
        \\_Thread_local int foo = 5;
        \\_Thread_local int bar;
    );
    dso.addArgs(&.{ "-fPIC", "-shared", "-mtls-dialect=gnu2" });
    const dso_out = dso.saveOutputAs("a.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\extern _Thread_local int foo;
        \\extern _Thread_local int bar;
        \\int main() {
        \\  bar = 7;
        \\  printf("%d %d\n", foo, bar);
        \\}
    );
    exe.addArgs(&.{ "-fPIC", "-mtls-dialect=gnu2" });
    exe.addFileSource(dso_out.file);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("5 7\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testTlsDescStatic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-desc-static", "");

    if (!opts.has_static) {
        skipTestStep(test_step);
        return test_step;
    }

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\extern _Thread_local int foo;
        \\int main() {
        \\  foo = 42;
        \\  printf("%d\n", foo);
        \\}
    );
    main_o.addArgs(&.{ "-c", "-fPIC", "-mtls-dialect=gnu2" });
    const main_o_out = main_o.saveOutputAs("main.o");

    const a_o = cc(b, opts);
    a_o.addCSource(
        \\_Thread_local int foo;
    );
    a_o.addArgs(&.{ "-c", "-fPIC", "-mtls-dialect=gnu2" });
    const a_o_out = a_o.saveOutputAs("a.o");

    const exp_stdout = "42\n";

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);
        exe.addArg("-static");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);
        exe.addArgs(&.{ "-static", "-Wl,-no-relax" });

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testTlsDso(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-dso", "");

    const dso = cc(b, opts);
    dso.addCSource(
        \\extern _Thread_local int foo;
        \\_Thread_local int bar;
        \\int get_foo1() { return foo; }
        \\int get_bar1() { return bar; }
    );
    dso.addArgs(&.{ "-fPIC", "-shared" });
    const dso_out = dso.saveOutputAs("a.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\_Thread_local int foo;
        \\extern _Thread_local int bar;
        \\int get_foo1();
        \\int get_bar1();
        \\int get_foo2() { return foo; }
        \\int get_bar2() { return bar; }
        \\int main() {
        \\  foo = 5;
        \\  bar = 3;
        \\  printf("%d %d %d %d %d %d\n",
        \\         foo, bar,
        \\         get_foo1(), get_bar1(),
        \\         get_foo2(), get_bar2());
        \\  return 0;
        \\}
    );
    exe.addFileSource(dso_out.file);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("5 3 5 3 5 3\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testTlsGd(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-gd", "");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\__attribute__((tls_model("global-dynamic"))) static _Thread_local int x1 = 1;
        \\__attribute__((tls_model("global-dynamic"))) static _Thread_local int x2;
        \\__attribute__((tls_model("global-dynamic"))) extern _Thread_local int x3;
        \\__attribute__((tls_model("global-dynamic"))) extern _Thread_local int x4;
        \\int get_x5();
        \\int get_x6();
        \\int main() {
        \\  x2 = 2;
        \\  printf("%d %d %d %d %d %d\n", x1, x2, x3, x4, get_x5(), get_x6());
        \\  return 0;
        \\}
    );
    main_o.addArgs(&.{ "-c", "-fPIC" });
    const main_o_out = main_o.saveOutputAs("main.o");

    const a_o = cc(b, opts);
    a_o.addCSource(
        \\__attribute__((tls_model("global-dynamic"))) _Thread_local int x3 = 3;
        \\__attribute__((tls_model("global-dynamic"))) static _Thread_local int x5 = 5;
        \\int get_x5() { return x5; }
    );
    a_o.addArgs(&.{ "-c", "-fPIC" });
    const a_o_out = a_o.saveOutputAs("a.o");

    const b_o = cc(b, opts);
    b_o.addCSource(
        \\__attribute__((tls_model("global-dynamic"))) _Thread_local int x4 = 4;
        \\__attribute__((tls_model("global-dynamic"))) static _Thread_local int x6 = 6;
        \\int get_x6() { return x6; }
    );
    b_o.addArgs(&.{ "-c", "-fPIC" });
    const b_o_out = b_o.saveOutputAs("b.o");

    const exp_stdout = "1 2 3 4 5 6\n";

    const dso1 = cc(b, opts);
    dso1.addArg("-shared");
    dso1.addFileSource(a_o_out.file);
    const dso1_out = dso1.saveOutputAs("a.so");

    const dso2 = cc(b, opts);
    dso2.addArgs(&.{ "-shared", "-Wl,-no-relax" });
    dso2.addFileSource(b_o_out.file);
    const dso2_out = dso2.saveOutputAs("b.so");

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(dso1_out.file);
        exe.addFileSource(dso2_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso1_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso2_out.dir);

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addArg("-Wl,-no-relax");
        exe.addFileSource(dso1_out.file);
        exe.addFileSource(dso2_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso1_out.dir);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso2_out.dir);

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    if (opts.has_static) {
        {
            const exe = cc(b, opts);
            exe.addFileSource(main_o_out.file);
            exe.addFileSource(a_o_out.file);
            exe.addFileSource(b_o_out.file);
            exe.addArg("-static");

            const run = exe.run();
            run.expectStdOutEqual(exp_stdout);
            test_step.dependOn(run.step());
        }

        {
            const exe = cc(b, opts);
            exe.addFileSource(main_o_out.file);
            exe.addFileSource(a_o_out.file);
            exe.addFileSource(b_o_out.file);
            exe.addArgs(&.{ "-static", "-Wl,-no-relax" });

            const run = exe.run();
            run.expectStdOutEqual(exp_stdout);
            test_step.dependOn(run.step());
        }
    }

    return test_step;
}

fn testTlsIe(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-ie", "");

    const dso = cc(b, opts);
    dso.addCSource(
        \\#include <stdio.h>
        \\__attribute__((tls_model("initial-exec"))) static _Thread_local int foo;
        \\__attribute__((tls_model("initial-exec"))) static _Thread_local int bar;
        \\void set() {
        \\  foo = 3;
        \\  bar = 5;
        \\}
        \\void print() {
        \\  printf("%d %d ", foo, bar);
        \\}
    );
    dso.addArgs(&.{ "-shared", "-fPIC" });
    const dso_out = dso.saveOutputAs("a.so");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\_Thread_local int baz;
        \\void set();
        \\void print();
        \\int main() {
        \\  baz = 7;
        \\  print();
        \\  set();
        \\  print();
        \\  printf("%d\n", baz);
        \\}
    );
    main_o.addArg("-c");
    const main_o_out = main_o.saveOutputAs("main.o");

    const exp_stdout = "0 0 3 5 7\n";

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(dso_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(dso_out.file);
        exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);
        exe.addArg("-Wl,-no-relax");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testTlsLd(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-ld", "");

    const main_o = cc(b, opts);
    main_o.addCSource(
        \\#include <stdio.h>
        \\extern _Thread_local int foo;
        \\static _Thread_local int bar;
        \\int *get_foo_addr() { return &foo; }
        \\int *get_bar_addr() { return &bar; }
        \\int main() {
        \\  bar = 5;
        \\  printf("%d %d %d %d\n", *get_foo_addr(), *get_bar_addr(), foo, bar);
        \\  return 0;
        \\}
    );
    main_o.addArgs(&.{ "-c", "-fPIC", "-ftls-model=local-dynamic" });
    const main_o_out = main_o.saveOutputAs("main.o");

    const a_o = cc(b, opts);
    a_o.addCSource("_Thread_local int foo = 3;");
    a_o.addArgs(&.{ "-c", "-fPIC", "-ftls-model=local-dynamic" });
    const a_o_out = a_o.saveOutputAs("a.o");

    const exp_stdout = "3 5 3 5\n";

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);
        exe.addArg("-Wl,-relax");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    {
        const exe = cc(b, opts);
        exe.addFileSource(main_o_out.file);
        exe.addFileSource(a_o_out.file);
        exe.addArg("-Wl,-no-relax");

        const run = exe.run();
        run.expectStdOutEqual(exp_stdout);
        test_step.dependOn(run.step());
    }

    return test_step;
}

fn testTlsLdDso(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-ld-dso", "");

    const dso = cc(b, opts);
    dso.addCSource(
        \\static _Thread_local int def, def1;
        \\int f0() { return ++def; }
        \\int f1() { return ++def1 + def; }
    );
    dso.addArgs(&.{ "-shared", "-fPIC", "-ftls-model=local-dynamic" });
    const dso_out = dso.saveOutputAs("a.so");

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\extern int f0();
        \\extern int f1();
        \\int main() {
        \\  printf("%d %d\n", f0(), f1());
        \\  return 0;
        \\}
    );
    exe.addFileSource(dso_out.file);
    exe.addPrefixedDirectorySource("-Wl,-rpath,", dso_out.dir);

    const run = exe.run();
    run.expectStdOutEqual("1 1\n");
    test_step.dependOn(run.step());

    return test_step;
}

fn testTlsStatic(b: *Build, opts: Options) *Step {
    const test_step = b.step("test-elf-tls-static", "");

    if (!opts.has_static) {
        skipTestStep(test_step);
        return test_step;
    }

    const exe = cc(b, opts);
    exe.addCSource(
        \\#include <stdio.h>
        \\_Thread_local int a = 10;
        \\_Thread_local int b;
        \\_Thread_local char c = 'a';
        \\int main(int argc, char* argv[]) {
        \\  printf("%d %d %c\n", a, b, c);
        \\  a += 1;
        \\  b += 1;
        \\  c += 1;
        \\  printf("%d %d %c\n", a, b, c);
        \\  return 0;
        \\}
    );
    exe.addArg("-static");

    const run = exe.run();
    run.expectStdOutEqual(
        \\10 0 a
        \\11 1 b
        \\
    );
    test_step.dependOn(run.step());

    return test_step;
}

fn cc(b: *Build, opts: Options) SysCmd {
    const cmd = Run.create(b, "cc");
    cmd.addArgs(&.{ "cc", "-fno-lto" });
    cmd.addArg("-o");
    const out = cmd.addOutputFileArg("a.out");
    cmd.addPrefixedDirectorySourceArg("-B", opts.zld.dir);
    return .{ .cmd = cmd, .out = out };
}

fn ar(b: *Build, name: []const u8) SysCmd {
    const cmd = Run.create(b, "ar");
    cmd.addArgs(&.{ "ar", "rcs" });
    const out = cmd.addOutputFileArg(name);
    return .{ .cmd = cmd, .out = out };
}

fn ld(b: *Build, opts: Options) SysCmd {
    const cmd = Run.create(b, "ld");
    cmd.addFileSourceArg(opts.zld.file);
    cmd.addArg("-o");
    const out = cmd.addOutputFileArg("a.out");
    return .{ .cmd = cmd, .out = out };
}

const std = @import("std");
const builtin = @import("builtin");
const common = @import("test.zig");
const skipTestStep = common.skipTestStep;

const Build = std.Build;
const Compile = Step.Compile;
const FileSourceWithDir = common.FileSourceWithDir;
const Options = common.Options;
const Run = Step.Run;
const Step = Build.Step;
const SysCmd = common.SysCmd;
