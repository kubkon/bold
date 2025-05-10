pub const File = union(enum) {
    internal: *InternalObject,
    object: *Object,
    dylib: *Dylib,

    pub fn getIndex(file: File) Index {
        return switch (file) {
            inline else => |x| x.index,
        };
    }

    pub fn fmtPath(file: File) std.fmt.Formatter(formatPath) {
        return .{ .data = file };
    }

    fn formatPath(
        file: File,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_fmt_string;
        _ = options;
        switch (file) {
            .internal => try writer.writeAll(""),
            .object => |x| try writer.print("{}", .{x.fmtPath()}),
            .dylib => |x| try writer.writeAll(x.path),
        }
    }

    pub fn resolveSymbols(file: File, macho_file: *MachO) !void {
        switch (file) {
            inline else => |x| try x.resolveSymbols(macho_file),
        }
    }

    pub fn checkDuplicates(file: File, macho_file: *MachO) !void {
        const tracy = trace(@src());
        defer tracy.end();

        const gpa = macho_file.allocator;

        for (file.getSymbols(), file.getNlists(), 0..) |sym, nlist, i| {
            if (sym.visibility != .global) continue;
            if (sym.flags.weak) continue;
            if (nlist.undf()) continue;
            const ref = file.getSymbolRef(@enumFromInt(i), macho_file).unwrap() orelse continue;
            const ref_file = ref.getFile(macho_file);
            if (ref_file.getIndex() == file.getIndex()) continue;

            macho_file.dupes_mutex.lock();
            defer macho_file.dupes_mutex.unlock();

            const gop = try macho_file.dupes.getOrPut(gpa, file.getGlobals()[i]);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{};
            }
            try gop.value_ptr.append(gpa, file.getIndex());
        }
    }

    pub fn scanRelocs(file: File, macho_file: *MachO) !void {
        switch (file) {
            .dylib => unreachable,
            .object => |x| try x.scanRelocs(macho_file),
            .internal => |x| x.scanRelocs(macho_file),
        }
    }

    /// Encodes symbol rank so that the following ordering applies:
    /// * strong in object
    /// * weak in object
    /// * tentative in object
    /// * strong in archive/dylib
    /// * weak in archive/dylib
    /// * tentative in archive
    /// * unclaimed
    pub fn getSymbolRank(file: File, args: struct {
        archive: bool = false,
        weak: bool = false,
        tentative: bool = false,
    }) u32 {
        // Offset by 1 since we start indexing at 0, and any operation on 0 will not get us far.
        const index: u32 = @intFromEnum(file.getIndex()) + 1;
        if (file != .dylib and !args.archive) {
            const base: u32 = blk: {
                if (args.tentative) break :blk 3;
                break :blk if (args.weak) 2 else 1;
            };
            return (base << 16) + index;
        }
        const base: u32 = blk: {
            if (args.tentative) break :blk 3;
            break :blk if (args.weak) 2 else 1;
        };
        return base + (index << 24);
    }

    pub fn getAtom(file: File, atom_index: Atom.Index) *Atom {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.getAtom(atom_index),
        };
    }

    pub fn getAtoms(file: File) []const Atom.Index {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.getAtoms(),
        };
    }

    pub fn addAtomExtra(file: File, allocator: Allocator, extra: Atom.Extra) !u32 {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.addAtomExtra(allocator, extra),
        };
    }

    pub fn getAtomExtra(file: File, index: u32) Atom.Extra {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.getAtomExtra(index),
        };
    }

    pub fn setAtomExtra(file: File, index: u32, extra: Atom.Extra) void {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.setAtomExtra(index, extra),
        };
    }

    pub fn getSymbols(file: File) []Symbol {
        return switch (file) {
            inline else => |x| x.symbols.items,
        };
    }

    pub fn getSymbolRef(file: File, sym_index: Symbol.Index, macho_file: *MachO) Symbol.Ref {
        return switch (file) {
            inline else => |x| x.getSymbolRef(sym_index, macho_file),
        };
    }

    pub fn getNlists(file: File) []macho.nlist_64 {
        return switch (file) {
            .dylib => unreachable,
            .internal => |x| x.symtab.items,
            .object => |x| x.symtab.items(.nlist),
        };
    }

    pub fn getGlobals(file: File) []MachO.SymbolResolver.Index {
        return switch (file) {
            inline else => |x| x.globals.items,
        };
    }

    pub fn markImportsAndExports(file: File, macho_file: *MachO) void {
        const nsyms = switch (file) {
            .dylib => unreachable,
            inline else => |x| x.symbols.items.len,
        };
        for (0..nsyms) |i| {
            const ref = file.getSymbolRef(@enumFromInt(i), macho_file).unwrap() orelse continue;
            const sym = ref.getSymbol(macho_file);
            if (sym.visibility != .global) continue;
            if (sym.getFile(macho_file).? == .dylib and !sym.flags.abs) {
                sym.flags.import = true;
                continue;
            }
            if (file.getIndex() == ref.getFile(macho_file).getIndex()) {
                sym.flags.@"export" = true;
            }
        }
    }

    pub fn createSymbolIndirection(file: File, macho_file: *MachO) !void {
        const nsyms = switch (file) {
            inline else => |x| x.symbols.items.len,
        };
        for (0..nsyms) |i| {
            const ref = file.getSymbolRef(@enumFromInt(i), macho_file).unwrap() orelse continue;
            if (ref.getFile(macho_file).getIndex() != file.getIndex()) continue;
            const sym = ref.getSymbol(macho_file);
            if (sym.getSectionFlags().got) {
                log.debug("'{s}' needs GOT", .{sym.getName(macho_file)});
                try macho_file.got.addSymbol(ref, macho_file);
            }
            if (sym.getSectionFlags().stubs) {
                log.debug("'{s}' needs STUBS", .{sym.getName(macho_file)});
                try macho_file.stubs.addSymbol(ref, macho_file);
            }
            if (sym.getSectionFlags().tlv_ptr) {
                log.debug("'{s}' needs TLV pointer", .{sym.getName(macho_file)});
                try macho_file.tlv_ptr.addSymbol(ref, macho_file);
            }
            if (sym.getSectionFlags().objc_stubs) {
                log.debug("'{s}' needs OBJC STUBS", .{sym.getName(macho_file)});
                try macho_file.objc_stubs.addSymbol(ref, macho_file);
            }
        }
    }

    pub fn initOutputSections(file: File, macho_file: *MachO) !void {
        const tracy = trace(@src());
        defer tracy.end();
        for (file.getAtoms()) |atom_index| {
            const atom = file.getAtom(atom_index);
            if (!atom.alive.load(.seq_cst)) continue;
            atom.out_n_sect = try Atom.initOutputSection(atom.getInputSection(macho_file), macho_file);
        }
    }

    pub fn dedupLiterals(file: File, lp: MachO.LiteralPool, macho_file: *MachO) void {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.dedupLiterals(lp, macho_file),
        };
    }

    pub fn writeAtoms(file: File, macho_file: *MachO) !void {
        return switch (file) {
            .dylib => unreachable,
            inline else => |x| x.writeAtoms(macho_file),
        };
    }

    pub fn calcSymtabSize(file: File, macho_file: *MachO) void {
        return switch (file) {
            inline else => |x| x.calcSymtabSize(macho_file),
        };
    }

    pub fn writeSymtab(file: File, macho_file: *MachO) void {
        return switch (file) {
            inline else => |x| x.writeSymtab(macho_file),
        };
    }

    pub const Index = enum(u32) {
        _,

        pub fn toOptional(index: Index) OptionalIndex {
            const res: OptionalIndex = @enumFromInt(@intFromEnum(index));
            assert(res != .none);
            return res;
        }

        pub fn eql(index: Index, other: Index) bool {
            return @intFromEnum(index) == @intFromEnum(other);
        }

        pub fn lessThan(index: Index, other: Index) bool {
            return @intFromEnum(index) < @intFromEnum(other);
        }

        pub fn format(
            index: Index,
            comptime unused_fmt_string: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = unused_fmt_string;
            _ = options;
            try writer.print("{d}", .{@intFromEnum(index)});
        }
    };

    pub const OptionalIndex = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(opt: OptionalIndex) ?Index {
            if (opt == .none) return null;
            return @enumFromInt(@intFromEnum(opt));
        }

        pub fn eql(index: OptionalIndex, other: OptionalIndex) bool {
            return @intFromEnum(index) == @intFromEnum(other);
        }

        pub fn format(
            opt: OptionalIndex,
            comptime unused_fmt_string: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = unused_fmt_string;
            _ = options;
            if (opt == .none) {
                try writer.writeAll(".none");
            } else {
                try writer.print("{d}", .{@intFromEnum(opt)});
            }
        }
    };

    pub const Entry = union(enum) {
        none: void,
        internal: InternalObject,
        object: Object,
        dylib: Dylib,
    };

    pub const Handle = std.fs.File;
    pub const HandleIndex = u32;
};

const assert = std.debug.assert;
const bind = @import("dyld_info/bind.zig");
const log = std.log.scoped(.link);
const macho = std.macho;
const std = @import("std");
const trace = @import("tracy.zig").trace;

const Allocator = std.mem.Allocator;
const Atom = @import("Atom.zig");
const InternalObject = @import("InternalObject.zig");
const MachO = @import("MachO.zig");
const Object = @import("Object.zig");
const Dylib = @import("Dylib.zig");
const Symbol = @import("Symbol.zig");
