const usage =
    \\Usage: {s} [files...]
    \\
    \\General Options:
    \\--allow-multiple-definition   Allow multiple definitions
    \\--as-needed                   Only set DT_NEEDED for shared libraries if used
    \\--no-as-needed                Always set DT_NEEDED for shared libraries (default)
    \\--Bstatic                     Do not link against shared libraries
    \\--Bdynamic                    Link against shared libraries (default)
    \\--dynamic                     Alias for --Bdynamic
    \\--dynamic-linker=[value], -I [value]      
    \\                              Set the dynamic linker to use
    \\--end-group                   Ignored for compatibility with GNU
    \\--eh-frame-hdr                Create .eh_frame_hdr section (default)
    \\--export-dynamic, -E          Export all dynamic symbols
    \\--no-export-dynamic           Don't export all dynamic symbols
    \\--no-eh-frame-hdr             Don't create .eh_frame_hdr section
    \\--entry=[value], -e [value]   Set name of the entry point symbol
    \\--gc-sections                 Remove unused sections
    \\--no-gc-sections              Don't remove unused sections (default)
    \\--print-gc-sections           List removed unused sections to stderr
    \\-l[value]                     Specify library to link against
    \\-L[value]                     Specify library search dir
    \\-m [value]                    Set target emulation
    \\--pie                         Create a position independent executable
    \\  --pic-executable
    \\--no-pie                      Create a position dependent executable (default)
    \\  --no-pic-executable
    \\--pop-state                   Restore the states saved by --push-state
    \\--push-state                  Save the current state of --as-needed, -static and --whole-archive
    \\--relax                       Optimize instructions (default)
    \\--no-relax                    Don't optimize instructions
    \\--rpath=[value], -R [value]   Specify runtime path
    \\--shared                      Create dynamic library
    \\--static                      Alias for --Bstatic
    \\--start-group                 Ignored for compatibility with GNU
    \\--strip-all, -s               Strip all symbols. Implies --strip-debug
    \\--strip-debug, -S             Strip .debug_ sections
    \\--warn-common                 Warn about duplicate common symbols
    \\--image-base=[value]          Set the base address
    \\-o [value]                    Specify output path for the final artifact
    \\-z                            Set linker extension flags
    \\  stack-size=[value]          Override default stack size
    \\  execstack                   Require executable stack
    \\  noexecstack                 Force stack non-executable
    \\  execstack-if-needed         Make the stack executable if the input file explicitly requests it
    \\  now                         Disable lazy function resolution
    \\  nocopyreloc                 Do not create copy relocations
    \\  text                        Do not allow relocations against read-only segments (default)
    \\  notext                      Allow relocations against read-only segments. Sets the DT_TEXTREL flag
    \\                              in the .dynamic section
    \\-h, --help                    Print this help and exit
    \\--verbose                     Print full linker invocation to stderr
    \\--debug-log [value]           Turn on debugging logs for [value] (requires zld compiled with -Dlog)
    \\
    \\ld.zld: supported targets: elf64-x86-64
    \\ld.zld: supported emulations: elf_x86_64
;

const cmd = "ld.zld";

emit: Zld.Emit,
output_mode: Zld.OutputMode,
positionals: []const Positional,
search_dirs: []const []const u8,
rpath_list: []const []const u8,
strip_debug: bool = false,
strip_all: bool = false,
entry: ?[]const u8 = null,
gc_sections: bool = false,
print_gc_sections: bool = false,
allow_multiple_definition: bool = false,
cpu_arch: ?std.Target.Cpu.Arch = null,
dynamic_linker: ?[]const u8 = null,
eh_frame_hdr: bool = true,
static: bool = false,
relax: bool = true,
export_dynamic: bool = false,
image_base: u64 = 0x200000,
page_size: ?u16 = null,
pie: bool = false,
pic: bool = false,
warn_common: bool = false,
/// -z flags
/// Overrides default stack size.
z_stack_size: ?u64 = null,
/// Marks the writeable segments as executable.
z_execstack: bool = false,
/// Marks the writeable segments as executable only if requested by an input object file
/// via sh_flags of the input .note.GNU-stack section.
z_execstack_if_needed: bool = false,
/// Disables lazy function resolution.
z_now: bool = false,
/// Do not create copy relocations.
z_nocopyreloc: bool = false,
/// Do not allow relocations against read-only segments.
z_text: bool = true,

pub fn parse(arena: Allocator, args: []const []const u8, ctx: anytype) !Options {
    if (args.len == 0) ctx.fatal(usage, .{cmd});

    var positionals = std.ArrayList(Positional).init(arena);
    var search_dirs = std.StringArrayHashMap(void).init(arena);
    var rpath_list = std.StringArrayHashMap(void).init(arena);
    var verbose = false;
    var opts: Options = .{
        .emit = .{
            .directory = std.fs.cwd(),
            .sub_path = "a.out",
        },
        .output_mode = .exe,
        .positionals = undefined,
        .search_dirs = undefined,
        .rpath_list = undefined,
    };

    var it = Zld.Options.ArgsIterator{ .args = args };
    var p = ArgParser(@TypeOf(ctx)){ .it = &it, .ctx = ctx };
    while (p.hasMore()) {
        if (p.flag2("help") or p.flag1("h")) {
            ctx.fatal(usage, .{cmd});
        } else if (p.arg2("debug-log")) |scope| {
            try ctx.log_scopes.append(scope);
        } else if (p.arg1("l")) |lib| {
            try positionals.append(.{ .tag = .library, .path = try std.fmt.allocPrint(arena, "-l{s}", .{lib}) });
        } else if (p.arg1("L")) |dir| {
            try search_dirs.put(dir, {});
        } else if (p.arg1("o")) |path| {
            opts.emit.sub_path = path;
        } else if (p.arg1("image-base")) |value| {
            opts.image_base = std.fmt.parseInt(u64, value, 0) catch
                ctx.fatal("Could not parse value '{s}' into integer", .{value});
        } else if (p.flagAny("gc-sections")) {
            opts.gc_sections = true;
        } else if (p.flagAny("no-gc-sections")) {
            opts.gc_sections = false;
        } else if (p.flagAny("print-gc-sections")) {
            opts.print_gc_sections = true;
        } else if (p.flagAny("shared")) {
            opts.output_mode = .lib;
        } else if (p.argAny("rpath")) |path| {
            try rpath_list.put(path, {});
        } else if (p.arg1("R")) |path| {
            try rpath_list.put(path, {});
        } else if (p.flagAny("export-dynamic") or p.flag1("E")) {
            opts.export_dynamic = true;
        } else if (p.flagAny("no-export-dynamic")) {
            opts.export_dynamic = false;
        } else if (p.flagAny("pie") or p.flagAny("pic-executable")) {
            opts.pic = true;
            opts.pie = true;
        } else if (p.flagAny("no-pie") or p.flagAny("no-pic-executable")) {
            opts.pic = false;
            opts.pie = false;
        } else if (p.argAny("entry")) |name| {
            opts.entry = name;
        } else if (p.arg1("e")) |name| {
            opts.entry = name;
        } else if (p.arg1("m")) |target| {
            if (mem.eql(u8, target, "elf_x86_64")) {
                opts.cpu_arch = .x86_64;
                opts.page_size = 0x1000;
            } else {
                ctx.fatal("unknown target emulation '{s}'", .{target});
            }
        } else if (p.flagAny("allow-multiple-definition")) {
            opts.allow_multiple_definition = true;
        } else if (p.flagAny("warn-common")) {
            opts.warn_common = true;
        } else if (p.flagAny("static")) {
            opts.static = true;
            try positionals.append(.{ .tag = .static });
        } else if (p.flagAny("dynamic")) {
            opts.static = false;
            try positionals.append(.{ .tag = .dynamic });
        } else if (p.argAny("B")) |b_arg| {
            if (mem.eql(u8, b_arg, "static")) {
                opts.static = true;
                try positionals.append(.{ .tag = .static });
            } else if (mem.eql(u8, b_arg, "dynamic")) {
                opts.static = false;
                try positionals.append(.{ .tag = .dynamic });
            } else {
                ctx.fatal("unknown argument '--B{s}'", .{b_arg});
            }
        } else if (p.flagAny("start-group") or p.flagAny("end-group")) {
            // Ignored
        } else if (p.flagAny("strip-debug") or p.flag1("S")) {
            opts.strip_debug = true;
        } else if (p.flagAny("strip-all") or p.flag1("s")) {
            opts.strip_all = true;
        } else if (p.flagAny("as-needed")) {
            try positionals.append(.{ .tag = .as_needed });
        } else if (p.flagAny("no-as-needed")) {
            try positionals.append(.{ .tag = .no_as_needed });
        } else if (p.flagAny("push-state")) {
            try positionals.append(.{ .tag = .push_state });
        } else if (p.flagAny("pop-state")) {
            try positionals.append(.{ .tag = .pop_state });
        } else if (p.argAny("dynamic-linker")) |path| {
            opts.dynamic_linker = path;
        } else if (p.arg1("I")) |path| {
            opts.dynamic_linker = path;
        } else if (p.flagAny("eh-frame-hdr")) {
            opts.eh_frame_hdr = true;
        } else if (p.flagAny("no-eh-frame-hdr")) {
            opts.eh_frame_hdr = false;
        } else if (p.flagAny("relax")) {
            opts.relax = true;
        } else if (p.flagAny("no-relax")) {
            opts.relax = false;
        } else if (p.flagAny("verbose")) {
            verbose = true;
        } else if (p.argZ("stack-size")) |value| {
            opts.z_stack_size = std.fmt.parseInt(u64, value, 0) catch
                ctx.fatal("Could not parse value '{s}' into integer", .{value});
        } else if (p.flagZ("execstack")) {
            opts.z_execstack = true;
        } else if (p.flagZ("noexecstack")) {
            opts.z_execstack = false;
        } else if (p.flagZ("execstack-if-needed")) {
            opts.z_execstack_if_needed = true;
        } else if (p.flagZ("now")) {
            opts.z_now = true;
        } else if (p.flagZ("nocopyreloc")) {
            opts.z_nocopyreloc = true;
        } else if (p.flagZ("text")) {
            opts.z_text = true;
        } else if (p.flagZ("notext")) {
            opts.z_text = false;
        } else {
            try positionals.append(.{ .tag = .path, .path = p.arg });
        }
    }

    if (verbose) {
        std.debug.print("{s} ", .{cmd});
        for (args[0 .. args.len - 1]) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print("{s}\n", .{args[args.len - 1]});
    }

    if (positionals.items.len == 0) ctx.fatal("Expected at least one positional argument", .{});
    if (opts.pic) opts.image_base = 0;
    if (opts.page_size) |page_size| {
        if (opts.image_base % page_size != 0) {
            ctx.fatal("specified --image-base=0x{x} is not a multiple of page size of 0x{x}", .{
                opts.image_base,
                page_size,
            });
        }
    }

    opts.positionals = positionals.items;
    opts.search_dirs = search_dirs.keys();
    opts.rpath_list = rpath_list.keys();

    return opts;
}

fn ArgParser(comptime Ctx: type) type {
    return struct {
        arg: []const u8 = undefined,
        it: *Zld.Options.ArgsIterator,
        ctx: Ctx,

        fn hasMore(p: *Self) bool {
            p.arg = p.it.next() orelse return false;
            return true;
        }

        fn flagAny(p: *Self, comptime pat: []const u8) bool {
            return p.flag2(pat) or p.flag1(pat);
        }

        fn flag2(p: *Self, comptime pat: []const u8) bool {
            return p.flagPrefix(pat, "--");
        }

        fn flag1(p: *Self, comptime pat: []const u8) bool {
            return p.flagPrefix(pat, "-");
        }

        fn flagZ(p: *Self, comptime pat: []const u8) bool {
            const prefix = "-z";
            const i = p.it.i;
            const actual_flag = blk: {
                if (mem.eql(u8, p.arg, prefix)) {
                    break :blk p.it.nextOrFatal(p.ctx);
                }
                if (mem.startsWith(u8, p.arg, prefix)) {
                    break :blk p.arg[prefix.len..];
                }
                return false;
            };
            if (mem.eql(u8, actual_flag, pat)) return true;
            p.it.i = i;
            return false;
        }

        fn flagPrefix(p: *Self, comptime pat: []const u8, comptime prefix: []const u8) bool {
            if (mem.startsWith(u8, p.arg, prefix)) {
                const actual_arg = p.arg[prefix.len..];
                if (mem.eql(u8, actual_arg, pat)) {
                    return true;
                }
            }
            return false;
        }

        fn argAny(p: *Self, comptime pat: []const u8) ?[]const u8 {
            if (p.arg2(pat)) |value| return value;
            return p.arg1(pat);
        }

        fn arg2(p: *Self, comptime pat: []const u8) ?[]const u8 {
            return p.argPrefix(pat, "--");
        }

        fn arg1(p: *Self, comptime pat: []const u8) ?[]const u8 {
            return p.argPrefix(pat, "-");
        }

        fn argZ(p: *Self, comptime pat: []const u8) ?[]const u8 {
            const prefix = "-z";
            const i = p.it.i;
            const actual_arg = blk: {
                if (mem.eql(u8, p.arg, prefix)) {
                    break :blk p.it.nextOrFatal(p.ctx);
                }
                if (mem.startsWith(u8, p.arg, prefix)) {
                    break :blk p.arg[prefix.len..];
                }
                return null;
            };
            if (mem.startsWith(u8, actual_arg, pat)) {
                if (mem.indexOf(u8, actual_arg, "=")) |index| {
                    if (index == pat.len) {
                        const value = actual_arg[index + 1 ..];
                        return value;
                    }
                }
            }
            p.it.i = i;
            return null;
        }

        fn argPrefix(p: *Self, comptime pat: []const u8, comptime prefix: []const u8) ?[]const u8 {
            if (mem.startsWith(u8, p.arg, prefix)) {
                const actual_arg = p.arg[prefix.len..];
                if (mem.eql(u8, actual_arg, pat)) {
                    return p.it.nextOrFatal(p.ctx);
                }
                if (pat.len == 1 and mem.eql(u8, actual_arg[0..pat.len], pat)) {
                    return actual_arg[pat.len..];
                }
                if (mem.startsWith(u8, actual_arg, pat)) {
                    if (mem.indexOf(u8, actual_arg, "=")) |index| {
                        if (index == pat.len) {
                            const value = actual_arg[index + 1 ..];
                            return value;
                        }
                    }
                }
            }
            return null;
        }

        const Self = @This();
    };
}

pub const Positional = struct {
    tag: Tag,
    path: []const u8 = "",

    pub const Tag = enum {
        path,
        library,
        static,
        dynamic,
        as_needed,
        no_as_needed,
        push_state,
        pop_state,
    };
};

const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const mem = std.mem;
const process = std.process;

const Allocator = mem.Allocator;
const Options = @This();
const Zld = @import("../Zld.zig");
