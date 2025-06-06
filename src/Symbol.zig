//! Represents a defined symbol.

/// Allocated address value of this symbol.
value: u64 = 0,

/// Offset into the linker's intern table.
name: MachO.String = .init,

/// File where this symbol is defined.
file: File.OptionalIndex = .none,

/// Reference to Atom containing this symbol if any.
/// Use `getAtom` to get the pointer to the atom.
atom_ref: Atom.Ref = .none,

/// Assigned output section index for this symbol.
out_n_sect: u8 = 0,

/// Index of the source nlist this symbol references.
/// Use `getNlist` to pull the nlist from the relevant file.
nlist_idx: u32 = 0,

/// Misc flags for the symbol packaged as packed struct for compression.
flags: Flags = .{},

sect_flags: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

visibility: Visibility = .local,

extra: u32 = 0,

pub fn isLocal(symbol: Symbol) bool {
    return !(symbol.flags.import or symbol.flags.@"export");
}

pub fn isSymbolStab(symbol: Symbol, macho_file: *MachO) bool {
    const file = symbol.getFile(macho_file) orelse return false;
    return switch (file) {
        .object => symbol.getNlist(macho_file).stab(),
        else => false,
    };
}

pub fn isTlvInit(symbol: Symbol, macho_file: *MachO) bool {
    const name = symbol.getName(macho_file);
    return std.mem.indexOf(u8, name, "$tlv$init") != null;
}

pub fn weakRef(symbol: Symbol, macho_file: *MachO) bool {
    const file = symbol.getFile(macho_file).?;
    const is_dylib_weak = switch (file) {
        .dylib => |x| x.weak,
        else => false,
    };
    return is_dylib_weak or symbol.flags.weak_ref;
}

pub fn getName(symbol: Symbol, macho_file: *MachO) [:0]const u8 {
    return switch (symbol.getFile(macho_file).?) {
        inline else => |x| x.getString(symbol.name),
    };
}

pub fn getAtom(symbol: Symbol, macho_file: *MachO) ?*Atom {
    const ref = symbol.atom_ref.unwrap() orelse return null;
    return ref.getAtom(macho_file);
}

pub fn getOutputSectionIndex(symbol: Symbol, macho_file: *MachO) u8 {
    if (symbol.getAtom(macho_file)) |atom| return atom.out_n_sect;
    return symbol.out_n_sect;
}

pub fn getFile(symbol: Symbol, macho_file: *MachO) ?File {
    const index = symbol.file.unwrap() orelse return null;
    return macho_file.getFile(index);
}

/// Asserts file is an object.
pub fn getNlist(symbol: Symbol, macho_file: *MachO) macho.nlist_64 {
    const file = symbol.getFile(macho_file).?;
    return switch (file) {
        .dylib => unreachable,
        .object => |x| x.symtab.items(.nlist)[symbol.nlist_idx],
        .internal => |x| x.symtab.items[symbol.nlist_idx],
    };
}

pub fn getSize(symbol: Symbol, macho_file: *MachO) u64 {
    const file = symbol.getFile(macho_file).?;
    assert(file == .object);
    return file.object.symtab.items(.size)[symbol.nlist_idx];
}

pub fn getDylibOrdinal(symbol: Symbol, macho_file: *MachO) ?u16 {
    assert(symbol.flags.import);
    const file = symbol.getFile(macho_file) orelse return null;
    return switch (file) {
        .dylib => |x| x.ordinal,
        else => null,
    };
}

pub fn getSymbolRank(symbol: Symbol, macho_file: *MachO) u32 {
    const file = symbol.getFile(macho_file).?;
    const in_archive = switch (file) {
        .object => |x| !x.alive,
        else => false,
    };
    return file.getSymbolRank(.{
        .archive = in_archive,
        .weak = symbol.flags.weak,
        .tentative = symbol.flags.tentative,
    });
}

pub fn getAddress(symbol: Symbol, opts: struct {
    stubs: bool = true,
}, macho_file: *MachO) u64 {
    if (opts.stubs) {
        if (symbol.getSectionFlags().stubs) {
            return symbol.getStubsAddress(macho_file);
        } else if (symbol.getSectionFlags().objc_stubs) {
            return symbol.getObjcStubsAddress(macho_file);
        }
    }
    if (symbol.getAtom(macho_file)) |atom| return atom.getAddress(macho_file) + symbol.value;
    return symbol.value;
}

pub fn getGotAddress(symbol: Symbol, macho_file: *MachO) u64 {
    if (!symbol.getSectionFlags().got) return 0;
    const extra = symbol.getExtra(macho_file);
    return macho_file.got.getAddress(extra.got, macho_file);
}

pub fn getStubsAddress(symbol: Symbol, macho_file: *MachO) u64 {
    if (!symbol.getSectionFlags().stubs) return 0;
    const extra = symbol.getExtra(macho_file);
    return macho_file.stubs.getAddress(extra.stubs, macho_file);
}

pub fn getObjcStubsAddress(symbol: Symbol, macho_file: *MachO) u64 {
    if (!symbol.getSectionFlags().objc_stubs) return 0;
    const extra = symbol.getExtra(macho_file);
    return macho_file.objc_stubs.getAddress(extra.objc_stubs, macho_file);
}

pub fn getObjcSelrefsAddress(symbol: Symbol, macho_file: *MachO) u64 {
    if (!symbol.getSectionFlags().objc_stubs) return 0;
    const extra = symbol.getExtra(macho_file);
    const file = symbol.getFile(macho_file).?;
    return switch (file) {
        .dylib => unreachable,
        inline else => |x| x.symbols.items[extra.objc_selrefs].getAddress(.{}, macho_file),
    };
}

pub fn getTlvPtrAddress(symbol: Symbol, macho_file: *MachO) u64 {
    if (!symbol.getSectionFlags().tlv_ptr) return 0;
    const extra = symbol.getExtra(macho_file);
    return macho_file.tlv_ptr.getAddress(extra.tlv_ptr, macho_file);
}

pub fn getOutputSymtabIndex(symbol: Symbol, macho_file: *MachO) ?u32 {
    if (!symbol.flags.output_symtab) return null;
    assert(!symbol.isSymbolStab(macho_file));
    const file = symbol.getFile(macho_file).?;
    const symtab_ctx = switch (file) {
        inline else => |x| x.output_symtab_ctx,
    };
    var idx = symbol.getExtra(macho_file).symtab;
    if (symbol.isLocal()) {
        idx += symtab_ctx.ilocal;
    } else if (symbol.flags.@"export") {
        idx += symtab_ctx.iexport;
    } else {
        assert(symbol.flags.import);
        idx += symtab_ctx.iimport;
    }
    return idx;
}

pub fn getSectionFlags(symbol: Symbol) SectionFlags {
    return @bitCast(symbol.sect_flags.load(.seq_cst));
}

pub fn setSectionFlags(symbol: *Symbol, flags: SectionFlags) void {
    _ = symbol.sect_flags.fetchOr(@bitCast(flags), .seq_cst);
}

const AddExtraOpts = struct {
    got: ?u32 = null,
    stubs: ?u32 = null,
    objc_stubs: ?u32 = null,
    tlv_ptr: ?u32 = null,
    symtab: ?u32 = null,
    objc_selrefs: ?u32 = null,
};

pub fn addExtra(symbol: *Symbol, opts: AddExtraOpts, macho_file: *MachO) void {
    var extra = symbol.getExtra(macho_file);
    inline for (@typeInfo(@TypeOf(opts)).@"struct".fields) |field| {
        if (@field(opts, field.name)) |x| {
            @field(extra, field.name) = x;
        }
    }
    symbol.setExtra(extra, macho_file);
}

pub inline fn getExtra(symbol: Symbol, macho_file: *MachO) Extra {
    return switch (symbol.getFile(macho_file).?) {
        inline else => |x| x.getSymbolExtra(symbol.extra),
    };
}

pub inline fn setExtra(symbol: Symbol, extra: Extra, macho_file: *MachO) void {
    return switch (symbol.getFile(macho_file).?) {
        inline else => |x| x.setSymbolExtra(symbol.extra, extra),
    };
}

pub fn setOutputSym(symbol: Symbol, macho_file: *MachO, out: *macho.nlist_64) void {
    if (symbol.isLocal()) {
        out.n_type = if (symbol.flags.abs) macho.N_ABS else macho.N_SECT;
        out.n_sect = if (symbol.flags.abs) 0 else @intCast(symbol.getOutputSectionIndex(macho_file) + 1);
        out.n_desc = 0;
        out.n_value = symbol.getAddress(.{ .stubs = false }, macho_file);

        switch (symbol.visibility) {
            .hidden => out.n_type |= macho.N_PEXT,
            else => {},
        }
    } else if (symbol.flags.@"export") {
        assert(symbol.visibility == .global);
        out.n_type = macho.N_EXT;
        out.n_type |= if (symbol.flags.abs) macho.N_ABS else macho.N_SECT;
        out.n_sect = if (symbol.flags.abs) 0 else @intCast(symbol.getOutputSectionIndex(macho_file) + 1);
        out.n_value = symbol.getAddress(.{ .stubs = false }, macho_file);
        out.n_desc = 0;

        if (symbol.flags.weak) {
            out.n_desc |= macho.N_WEAK_DEF;
        }
        if (symbol.flags.dyn_ref) {
            out.n_desc |= macho.REFERENCED_DYNAMICALLY;
        }
    } else {
        assert(symbol.visibility == .global);
        out.n_type = macho.N_EXT;
        out.n_sect = 0;
        out.n_value = 0;
        out.n_desc = 0;

        const ord: u16 = if (macho_file.options.namespace == .flat)
            @as(u8, @bitCast(macho.BIND_SPECIAL_DYLIB_FLAT_LOOKUP))
        else if (symbol.getDylibOrdinal(macho_file)) |ord|
            ord
        else
            macho.BIND_SPECIAL_DYLIB_SELF;
        out.n_desc = macho.N_SYMBOL_RESOLVER * ord;

        if (symbol.flags.weak) {
            out.n_desc |= macho.N_WEAK_DEF;
        }

        if (symbol.weakRef(macho_file)) {
            out.n_desc |= macho.N_WEAK_REF;
        }
    }
}

pub fn format(
    symbol: Symbol,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = symbol;
    _ = unused_fmt_string;
    _ = options;
    _ = writer;
    @compileError("do not format symbols directly");
}

const FormatContext = struct {
    symbol: Symbol,
    macho_file: *MachO,
};

pub fn fmt(symbol: Symbol, macho_file: *MachO) std.fmt.Formatter(format2) {
    return .{ .data = .{
        .symbol = symbol,
        .macho_file = macho_file,
    } };
}

fn format2(
    ctx: FormatContext,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = unused_fmt_string;
    const symbol = ctx.symbol;
    try writer.print("%{d} : {s} : @{x}", .{
        symbol.nlist_idx,
        symbol.getName(ctx.macho_file),
        symbol.getAddress(.{}, ctx.macho_file),
    });
    if (symbol.getFile(ctx.macho_file)) |file| {
        if (symbol.getOutputSectionIndex(ctx.macho_file) != 0) {
            try writer.print(" : sect({d})", .{symbol.getOutputSectionIndex(ctx.macho_file)});
        }
        if (symbol.getAtom(ctx.macho_file)) |atom| {
            try writer.print(" : atom({d})", .{atom.atom_index});
        }
        var buf: [3]u8 = .{'_'} ** 3;
        if (symbol.flags.@"export") buf[0] = 'E';
        if (symbol.flags.import) buf[1] = 'I';
        switch (symbol.visibility) {
            .local => buf[2] = 'L',
            .hidden => buf[2] = 'H',
            .global => buf[2] = 'G',
        }
        try writer.print(" : {s}", .{&buf});
        if (symbol.flags.weak) try writer.writeAll(" : weak");
        if (symbol.isSymbolStab(ctx.macho_file)) try writer.writeAll(" : stab");
        switch (file) {
            .internal => |x| try writer.print(" : internal({d})", .{x.index}),
            .object => |x| try writer.print(" : object({d})", .{x.index}),
            .dylib => |x| try writer.print(" : dylib({d})", .{x.index}),
        }
    } else try writer.writeAll(" : unresolved");
}

pub const Flags = packed struct {
    /// Whether the symbol is imported at runtime.
    import: bool = false,

    /// Whether the symbol is exported at runtime.
    @"export": bool = false,

    /// Whether this symbol is weak.
    weak: bool = false,

    /// Whether this symbol is weakly referenced.
    weak_ref: bool = false,

    /// Whether this symbol is dynamically referenced.
    dyn_ref: bool = false,

    /// Whether this symbol was marked as N_NO_DEAD_STRIP.
    no_dead_strip: bool = false,

    /// Whether this symbol can be interposed at runtime.
    interposable: bool = false,

    /// Whether this symbol is absolute.
    abs: bool = false,

    /// Whether this symbol is a tentative definition.
    tentative: bool = false,

    /// Whether this symbol is a thread-local variable.
    tlv: bool = false,

    /// Whether the symbol makes into the output symtab or not.
    output_symtab: bool = false,
};

pub const SectionFlags = packed struct(u8) {
    /// Whether the symbol contains __got indirection.
    got: bool = false,

    /// Whether the symbols contains __stubs indirection.
    stubs: bool = false,

    /// Whether the symbol has a TLV pointer.
    tlv_ptr: bool = false,

    /// Whether the symbol contains __objc_stubs indirection.
    objc_stubs: bool = false,

    _: u4 = 0,
};

pub const Visibility = enum {
    global,
    hidden,
    local,

    pub fn rank(vis: Visibility) u2 {
        return switch (vis) {
            .local => 2,
            .hidden => 1,
            .global => 0,
        };
    }
};

pub const Extra = struct {
    got: u32 = 0,
    stubs: u32 = 0,
    objc_stubs: u32 = 0,
    tlv_ptr: u32 = 0,
    symtab: u32 = 0,
    objc_selrefs: u32 = 0,

    pub const init: Extra = .{
        .got = 0,
        .stubs = 0,
        .objc_stubs = 0,
        .tlv_ptr = 0,
        .symtab = 0,
        .objc_selrefs = 0,
    };
};

pub const Index = enum(u32) {
    _,

    pub fn toOptional(index: Index) OptionalIndex {
        const result: OptionalIndex = @enumFromInt(@intFromEnum(index));
        assert(result != .none);
        return result;
    }

    pub fn toRef(index: Index, file: File.Index) Ref {
        const result: Ref = @enumFromInt(@intFromEnum(index) | @as(u64, @intFromEnum(file)) << 32);
        assert(result != .none);
        return result;
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

    pub fn eql(opt: OptionalIndex, other: OptionalIndex) bool {
        return @intFromEnum(opt) == @intFromEnum(other);
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

pub const Ref = enum(u64) {
    none = std.math.maxInt(u64),
    _,

    pub fn unwrap(ref: Ref) ?UnwrappedRef {
        if (ref == .none) return null;
        const raw = @intFromEnum(ref);
        const sym_index: Index = @enumFromInt(@as(u32, @truncate(raw)));
        const file_index: File.Index = @enumFromInt(@as(u32, @truncate(raw >> 32)));
        return .{ .symbol = sym_index, .file = file_index };
    }

    pub fn eql(ref: Ref, other: Ref) bool {
        return @intFromEnum(ref) == @intFromEnum(other);
    }

    pub fn lessThan(ref: Ref, other: Ref) bool {
        return @intFromEnum(ref) < @intFromEnum(other);
    }
};

pub const UnwrappedRef = struct {
    symbol: Index,
    file: File.Index,

    pub fn getSymbol(ref: UnwrappedRef, macho_file: *MachO) *Symbol {
        const file = macho_file.getFile(ref.file);
        return switch (file) {
            inline else => |x| &x.symbols.items[@intFromEnum(ref.symbol)],
        };
    }

    pub fn getFile(ref: UnwrappedRef, macho_file: *MachO) File {
        return macho_file.getFile(ref.file);
    }

    pub fn eql(ref: UnwrappedRef, other: UnwrappedRef) bool {
        return ref.symbol == other.symbol and ref.file == other.file;
    }

    pub fn lessThan(ref: UnwrappedRef, other: UnwrappedRef) bool {
        if (ref.file == other.file) {
            return @intFromEnum(ref.symbol) < @intFromEnum(other.symbol);
        }
        return @intFromEnum(ref.file) < @intFromEnum(other.file);
    }
};

const assert = std.debug.assert;
const macho = std.macho;
const std = @import("std");

const Atom = @import("Atom.zig");
const File = @import("file.zig").File;
const MachO = @import("MachO.zig");
const Object = @import("Object.zig");
const Symbol = @This();
