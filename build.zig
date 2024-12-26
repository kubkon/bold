const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const log = std.log;
const tests = @import("test/test.zig");

const Allocator = std.mem.Allocator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const enable_logging = b.option(bool, "log", "Whether to enable logging") orelse (mode == .Debug);
    const enable_tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack_depth = b.option(usize, "tracy-callstack-depth", "Set Tracy callstack depth") orelse 20;
    const strip = b.option(bool, "strip", "Omit debug information") orelse blk: {
        if (enable_tracy != null) break :blk false;
        break :blk null;
    };
    const use_llvm = b.option(bool, "use-llvm", "Whether to use LLVM") orelse true;
    const sanitize_thread = b.option(bool, "sanitize-thread", "Enable thread-sanitization") orelse false;
    const single_threaded = b.option(bool, "single-threaded", "Force single-threaded") orelse false;

    const yaml = b.dependency("zig-yaml", .{
        .target = target,
        .optimize = mode,
    });
    const dis_x86_64 = b.dependency("zig-dis-x86_64", .{
        .target = target,
        .optimize = mode,
    });

    const exe = b.addExecutable(.{
        .name = "bold",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
        .use_llvm = use_llvm,
        .sanitize_thread = sanitize_thread,
        .single_threaded = single_threaded,
    });
    exe.root_module.addImport("yaml", yaml.module("yaml"));
    exe.root_module.addImport("dis_x86_64", dis_x86_64.module("dis_x86_64"));
    exe.root_module.strip = strip;
    exe.linkLibC();

    const exe_opts = b.addOptions();
    exe.root_module.addOptions("build_options", exe_opts);
    exe_opts.addOption(bool, "enable_logging", enable_logging);
    exe_opts.addOption(bool, "enable_tracy", enable_tracy != null);
    exe_opts.addOption(usize, "tracy_callstack_depth", tracy_callstack_depth);

    if (enable_tracy) |tracy_path| {
        const client_cpp = fs.path.join(
            b.allocator,
            &[_][]const u8{ tracy_path, "TracyClient.cpp" },
        ) catch unreachable;

        // On mingw, we need to opt into windows 7+ to get some features required by tracy.
        const tracy_c_flags: []const []const u8 = if (target.result.os.tag == .windows and target.result.abi == .gnu)
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
        else
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.addIncludePath(.{ .cwd_relative = tracy_path });
        exe.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });

        if (target.result.os.tag == .windows) {
            exe.linkSystemLibrary("dbghelp");
            exe.linkSystemLibrary("ws2_32");
        }
    }
    b.installArtifact(exe);

    const system_compiler = b.option(tests.SystemCompiler, "system-compiler", "System compiler we are utilizing for tests: gcc, clang");
    const has_static = b.option(bool, "has-static", "Whether the system compiler supports '-static' flag") orelse false;
    const has_zig = b.option(bool, "has-zig", "Whether the Zig compiler is in path") orelse false;
    const is_musl = b.option(bool, "musl", "Whether the tests are linked against musl libc") orelse false;
    const has_objc_msgsend_stubs = b.option(bool, "has-objc-msgsend-stubs", "Whether the system compiler supports '-fobjc-msgsend-selector-stubs' flag") orelse false;
    const is_nix = b.option(bool, "nix", "Whether the host is Nix-based") orelse false;

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/MachO.zig"),
        .target = target,
        .optimize = mode,
        .use_llvm = use_llvm,
        .sanitize_thread = sanitize_thread,
        .single_threaded = single_threaded,
    });
    const unit_tests_opts = b.addOptions();
    unit_tests.root_module.addOptions("build_options", unit_tests_opts);
    unit_tests_opts.addOption(bool, "enable_logging", enable_logging);
    unit_tests_opts.addOption(bool, "enable_tracy", enable_tracy != null);
    unit_tests.root_module.addImport("yaml", yaml.module("yaml"));
    unit_tests.root_module.addImport("dis_x86_64", dis_x86_64.module("dis_x86_64"));
    unit_tests.linkLibC();

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    test_step.dependOn(tests.addTests(b, exe, .{
        .system_compiler = system_compiler,
        .has_static = has_static,
        .has_zig = has_zig,
        .is_musl = is_musl,
        .has_objc_msgsend_stubs = has_objc_msgsend_stubs,
        .is_nix = is_nix,
    }));
}
