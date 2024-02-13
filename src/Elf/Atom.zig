/// Address allocated for this Atom.
value: u64 = 0,

/// Name of this Atom.
name: u32 = 0,

/// Index into linker's input file table.
file: File.Index = 0,

/// Size of this atom
size: u64 = 0,

/// Alignment of this atom as a power of two.
alignment: u8 = 0,

/// Index of the input section.
shndx: u32 = 0,

/// Index of the output section.
out_shndx: u32 = 0,

/// Index of the input section containing this atom's relocs.
relocs_shndx: u32 = 0,

/// Start index of relocations belonging to this atom.
rel_index: u32 = 0,

/// Number of relocations belonging to this atom.
rel_num: u32 = 0,

/// Index of this atom in the linker's atoms table.
atom_index: Index = 0,

flags: Flags = .{},

/// Start index of FDEs referencing this atom.
fde_start: u32 = 0,

/// End index of FDEs referencing this atom.
fde_end: u32 = 0,

pub fn getName(self: Atom, elf_file: *Elf) [:0]const u8 {
    return elf_file.string_intern.getAssumeExists(self.name);
}

pub fn getAddress(self: Atom, elf_file: *Elf) u64 {
    const shdr = elf_file.sections.items(.shdr)[self.out_shndx];
    return shdr.sh_addr + self.value;
}

/// Returns atom's code and optionally uncompresses data if required (for compressed sections).
/// Caller owns the memory.
pub fn getCodeUncompressAlloc(self: Atom, elf_file: *Elf) ![]u8 {
    const tracy = trace(@src());
    defer tracy.end();

    const gpa = elf_file.base.allocator;
    const shdr = self.getInputShdr(elf_file);
    const object = self.getObject(elf_file);
    const file = elf_file.getFileHandle(object.file_handle);
    const data = try object.preadShdrContentsAlloc(gpa, file, self.shndx);
    defer if (shdr.sh_flags & elf.SHF_COMPRESSED != 0) gpa.free(data);

    if (shdr.sh_flags & elf.SHF_COMPRESSED != 0) {
        const chdr = @as(*align(1) const elf.Elf64_Chdr, @ptrCast(data.ptr)).*;
        switch (chdr.ch_type) {
            .ZLIB => {
                var stream = std.io.fixedBufferStream(data[@sizeOf(elf.Elf64_Chdr)..]);
                var zlib_stream = try std.compress.zlib.decompressStream(gpa, stream.reader());
                defer zlib_stream.deinit();
                const decomp = try gpa.alloc(u8, chdr.ch_size);
                const nread = try zlib_stream.reader().readAll(decomp);
                if (nread != decomp.len) {
                    return error.InputOutput;
                }
                return decomp;
            },
            else => @panic("TODO unhandled compression scheme"),
        }
    }

    return data;
}

pub fn getObject(self: Atom, elf_file: *Elf) *Object {
    return elf_file.getFile(self.file).?.object;
}

pub fn getInputShdr(self: Atom, elf_file: *Elf) elf.Elf64_Shdr {
    const object = self.getObject(elf_file);
    return object.shdrs.items[self.shndx];
}

pub fn getPriority(self: Atom, elf_file: *Elf) u64 {
    const object = self.getObject(elf_file);
    return (@as(u64, @intCast(object.index)) << 32) | @as(u64, @intCast(self.shndx));
}

pub fn getRelocs(self: Atom, elf_file: *Elf) []const elf.Elf64_Rela {
    const object = self.getObject(elf_file);
    return object.relocs.items[self.rel_index..][0..self.rel_num];
}

pub fn writeRelocs(self: Atom, elf_file: *Elf, out_relocs: *std.ArrayList(elf.Elf64_Rela)) !void {
    const tracy = trace(@src());
    defer tracy.end();

    relocs_log.debug("0x{x}: {s}", .{ self.getAddress(elf_file), self.getName(elf_file) });

    const object = self.getObject(elf_file);
    for (self.getRelocs(elf_file)) |rel| {
        const target = object.getSymbol(rel.r_sym(), elf_file);
        const r_type = rel.r_type();
        const r_offset = self.value + rel.r_offset;
        var r_addend = rel.r_addend;
        var r_sym: u32 = 0;
        switch (target.getType(elf_file)) {
            elf.STT_SECTION => {
                r_addend += @intCast(target.getAddress(.{}, elf_file));
                r_sym = elf_file.sections.items(.sym_index)[target.shndx];
            },
            else => {
                r_sym = target.getOutputSymtabIndex(elf_file) orelse 0;
            },
        }

        relocs_log.debug("  {s}: [{x} => {d}({s})] + {x}", .{
            fmtRelocType(r_type),
            r_offset,
            r_sym,
            target.getName(elf_file),
            r_addend,
        });

        out_relocs.appendAssumeCapacity(.{
            .r_offset = r_offset,
            .r_addend = r_addend,
            .r_info = (@as(u64, @intCast(r_sym)) << 32) | r_type,
        });
    }
}

pub fn getFdes(self: Atom, elf_file: *Elf) []Fde {
    if (self.fde_start == self.fde_end) return &[0]Fde{};
    const object = self.getObject(elf_file);
    return object.fdes.items[self.fde_start..self.fde_end];
}

pub fn markFdesDead(self: Atom, elf_file: *Elf) void {
    for (self.getFdes(elf_file)) |*fde| {
        fde.alive = false;
    }
}

pub fn scanRelocs(self: Atom, elf_file: *Elf) !void {
    const tracy = trace(@src());
    defer tracy.end();

    const object = self.getObject(elf_file);
    const relocs = self.getRelocs(elf_file);
    const code = try self.getCodeUncompressAlloc(elf_file);
    defer elf_file.base.allocator.free(code);

    var has_errors = false;
    var i: usize = 0;
    while (i < relocs.len) : (i += 1) {
        const rel = relocs[i];

        if (rel.r_type() == elf.R_X86_64_NONE) continue;
        if (try self.reportUndefSymbol(rel, elf_file)) continue;

        const symbol = object.getSymbol(rel.r_sym(), elf_file);
        const is_shared = elf_file.options.shared;

        if (symbol.isIFunc(elf_file)) {
            symbol.flags.got = true;
            symbol.flags.plt = true;
        }

        // While traversing relocations, mark symbols that require special handling such as
        // pointer indirection via GOT, or a stub trampoline via PLT.
        switch (rel.r_type()) {
            elf.R_X86_64_64 => {
                self.scanReloc(symbol, rel, getDynAbsRelocAction(symbol, elf_file), elf_file) catch {
                    has_errors = true;
                };
            },

            elf.R_X86_64_32,
            elf.R_X86_64_32S,
            => {
                self.scanReloc(symbol, rel, getAbsRelocAction(symbol, elf_file), elf_file) catch {
                    has_errors = true;
                };
            },

            elf.R_X86_64_GOT32,
            elf.R_X86_64_GOT64,
            elf.R_X86_64_GOTPC32,
            elf.R_X86_64_GOTPC64,
            elf.R_X86_64_GOTPCREL,
            elf.R_X86_64_GOTPCREL64,
            elf.R_X86_64_GOTPCRELX,
            elf.R_X86_64_REX_GOTPCRELX,
            => {
                symbol.flags.got = true;
            },

            elf.R_X86_64_PLT32,
            elf.R_X86_64_PLTOFF64,
            => {
                if (symbol.flags.import) {
                    symbol.flags.plt = true;
                }
            },

            elf.R_X86_64_PC32 => {
                self.scanReloc(symbol, rel, getPcRelocAction(symbol, elf_file), elf_file) catch {
                    has_errors = true;
                };
            },

            elf.R_X86_64_TLSGD => {
                // TODO verify followed by appropriate relocation such as PLT32 __tls_get_addr

                if (elf_file.options.static or
                    (elf_file.options.relax and !symbol.flags.import and !is_shared))
                {
                    // Relax if building with -static flag as __tls_get_addr() will not be present in libc.a
                    // We skip the next relocation.
                    i += 1;
                } else if (elf_file.options.relax and !symbol.flags.import and is_shared and
                    elf_file.options.z_nodlopen)
                {
                    symbol.flags.gottp = true;
                    i += 1;
                } else {
                    symbol.flags.tlsgd = true;
                }
            },

            elf.R_X86_64_TLSLD => {
                // TODO verify followed by appropriate relocation such as PLT32 __tls_get_addr

                if (elf_file.options.static or (elf_file.options.relax and !is_shared)) {
                    // Relax if building with -static flag as __tls_get_addr() will not be present in libc.a
                    // We skip the next relocation.
                    i += 1;
                } else {
                    elf_file.got.flags.needs_tlsld = true;
                }
            },

            elf.R_X86_64_GOTTPOFF => {
                const should_relax = blk: {
                    if (!elf_file.options.relax or is_shared or symbol.flags.import) break :blk false;
                    relaxGotTpOff(code[rel.r_offset - 3 ..]) catch break :blk false;
                    break :blk true;
                };
                if (!should_relax) {
                    symbol.flags.gottp = true;
                }
            },

            elf.R_X86_64_GOTPC32_TLSDESC => {
                const should_relax = elf_file.options.static or
                    (elf_file.options.relax and !is_shared and !symbol.flags.import);
                if (!should_relax) {
                    symbol.flags.tlsdesc = true;
                }
            },

            elf.R_X86_64_TPOFF32,
            elf.R_X86_64_TPOFF64,
            => {
                if (is_shared) self.picError(symbol, rel, elf_file) catch {
                    has_errors = true;
                };
            },

            elf.R_X86_64_GOTOFF64,
            elf.R_X86_64_DTPOFF32,
            elf.R_X86_64_DTPOFF64,
            elf.R_X86_64_SIZE32,
            elf.R_X86_64_SIZE64,
            elf.R_X86_64_TLSDESC_CALL,
            => {},

            else => {
                elf_file.base.fatal("{s}: unknown relocation type: {}", .{
                    self.getName(elf_file),
                    fmtRelocType(rel.r_type()),
                });
                has_errors = true;
            },
        }
    }

    if (has_errors) return error.RelocError;
}

fn scanReloc(self: Atom, symbol: *Symbol, rel: elf.Elf64_Rela, action: RelocAction, elf_file: *Elf) !void {
    const tracy = trace(@src());
    defer tracy.end();

    const is_writeable = self.getInputShdr(elf_file).sh_flags & elf.SHF_WRITE != 0;
    const object = self.getObject(elf_file);

    switch (action) {
        .none => {},

        .@"error" => if (symbol.isAbs(elf_file))
            try self.noPicError(symbol, rel, elf_file)
        else
            try self.picError(symbol, rel, elf_file),

        .copyrel => {
            if (elf_file.options.z_nocopyreloc) {
                if (symbol.isAbs(elf_file))
                    try self.noPicError(symbol, rel, elf_file)
                else
                    try self.picError(symbol, rel, elf_file);
            }
            symbol.flags.copy_rel = true;
        },

        .dyn_copyrel => {
            if (is_writeable or elf_file.options.z_nocopyreloc) {
                try self.textReloc(symbol, elf_file);
                object.num_dynrelocs += 1;
            } else {
                symbol.flags.copy_rel = true;
            }
        },

        .plt => {
            symbol.flags.plt = true;
        },

        .cplt => {
            symbol.flags.plt = true;
            symbol.flags.is_canonical = true;
        },

        .dyn_cplt => {
            if (is_writeable) {
                object.num_dynrelocs += 1;
            } else {
                symbol.flags.plt = true;
                symbol.flags.is_canonical = true;
            }
        },

        .dynrel, .baserel, .ifunc => {
            try self.textReloc(symbol, elf_file);
            object.num_dynrelocs += 1;

            if (action == .ifunc) elf_file.num_ifunc_dynrelocs += 1;
        },
    }
}

inline fn textReloc(self: Atom, symbol: *const Symbol, elf_file: *Elf) !void {
    const is_writeable = self.getInputShdr(elf_file).sh_flags & elf.SHF_WRITE != 0;
    if (!is_writeable) {
        if (elf_file.options.z_text) {
            elf_file.base.fatal("{s}: {s}: relocation against symbol '{s}' in read-only section", .{
                self.getObject(elf_file).fmtPath(),
                self.getName(elf_file),
                symbol.getName(elf_file),
            });
            return error.RelocError;
        } else {
            elf_file.has_text_reloc = true;
        }
    }
}

inline fn noPicError(self: Atom, symbol: *const Symbol, rel: elf.Elf64_Rela, elf_file: *Elf) !void {
    elf_file.base.fatal(
        "{s}: {s}: {} relocation at offset 0x{x} against symbol '{s}' cannot be used; recompile with -fno-PIC",
        .{
            self.getObject(elf_file).fmtPath(),
            self.getName(elf_file),
            fmtRelocType(rel.r_type()),
            rel.r_offset,
            symbol.getName(elf_file),
        },
    );
    return error.RelocError;
}

inline fn picError(self: Atom, symbol: *const Symbol, rel: elf.Elf64_Rela, elf_file: *Elf) !void {
    elf_file.base.fatal(
        "{s}: {s}: {} relocation at offset 0x{x} against symbol '{s}' cannot be used; recompile with -fPIC",
        .{
            self.getObject(elf_file).fmtPath(),
            self.getName(elf_file),
            fmtRelocType(rel.r_type()),
            rel.r_offset,
            symbol.getName(elf_file),
        },
    );
    return error.RelocError;
}

const RelocAction = enum {
    none,
    @"error",
    copyrel,
    dyn_copyrel,
    plt,
    dyn_cplt,
    cplt,
    dynrel,
    baserel,
    ifunc,
};

fn getPcRelocAction(symbol: *const Symbol, elf_file: *Elf) RelocAction {
    // zig fmt: off
    const table: [3][4]RelocAction = .{
        //  Abs       Local   Import data  Import func
        .{ .@"error", .none,  .@"error",   .plt  }, // Shared object
        .{ .@"error", .none,  .copyrel,    .plt  }, // PIE
        .{ .none,     .none,  .copyrel,    .cplt }, // Non-PIE
    };
    // zig fmt: on
    const output = getOutputType(elf_file);
    const data = getDataType(symbol, elf_file);
    return table[output][data];
}

fn getAbsRelocAction(symbol: *const Symbol, elf_file: *Elf) RelocAction {
    // zig fmt: off
    const table: [3][4]RelocAction = .{
        //  Abs    Local       Import data  Import func
        .{ .none,  .@"error",  .@"error",   .@"error"  }, // Shared object
        .{ .none,  .@"error",  .@"error",   .@"error"  }, // PIE
        .{ .none,  .none,      .copyrel,    .cplt      }, // Non-PIE
    };
    // zig fmt: on
    const output = getOutputType(elf_file);
    const data = getDataType(symbol, elf_file);
    return table[output][data];
}

fn getDynAbsRelocAction(symbol: *const Symbol, elf_file: *Elf) RelocAction {
    if (symbol.isIFunc(elf_file)) return .ifunc;
    // zig fmt: off
    const table: [3][4]RelocAction = .{
        //  Abs    Local       Import data   Import func
        .{ .none,  .baserel,  .dynrel,       .dynrel    }, // Shared object
        .{ .none,  .baserel,  .dynrel,       .dynrel    }, // PIE
        .{ .none,  .none,     .dyn_copyrel,  .dyn_cplt  }, // Non-PIE
    };
    // zig fmt: on
    const output = getOutputType(elf_file);
    const data = getDataType(symbol, elf_file);
    return table[output][data];
}

inline fn getOutputType(elf_file: *Elf) u2 {
    if (elf_file.options.shared) return 0;
    return if (elf_file.options.pie) 1 else 2;
}

inline fn getDataType(symbol: *const Symbol, elf_file: *Elf) u2 {
    if (symbol.isAbs(elf_file)) return 0;
    if (!symbol.flags.import) return 1;
    if (symbol.getType(elf_file) != elf.STT_FUNC) return 2;
    return 3;
}

fn reportUndefSymbol(self: Atom, rel: elf.Elf64_Rela, elf_file: *Elf) !bool {
    const object = self.getObject(elf_file);
    const sym = object.getSymbol(rel.r_sym(), elf_file);
    const s_rel_sym = object.symtab.items[rel.r_sym()];

    // Check for violation of One Definition Rule for COMDATs.
    if (sym.getFile(elf_file) == null) {
        elf_file.base.fatal("{}: {s}: {s} refers to a discarded COMDAT section", .{
            object.fmtPath(),
            self.getName(elf_file),
            sym.getName(elf_file),
        });
        return true;
    }

    // Next, report any undefined non-weak symbols that are not imports.
    const s_sym = sym.getSourceSymbol(elf_file);
    if (s_rel_sym.st_shndx == elf.SHN_UNDEF and
        s_rel_sym.st_bind() == elf.STB_GLOBAL and
        sym.sym_idx > 0 and
        !sym.flags.import and
        s_sym.st_shndx == elf.SHN_UNDEF)
    {
        const gpa = elf_file.base.allocator;
        const gop = try elf_file.undefs.getOrPut(gpa, object.symbols.items[rel.r_sym()]);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(gpa, self.atom_index);
        return true;
    }

    return false;
}

pub fn resolveRelocsAlloc(self: Atom, elf_file: *Elf, writer: anytype) !void {
    const tracy = trace(@src());
    defer tracy.end();

    assert(self.getInputShdr(elf_file).sh_flags & elf.SHF_ALLOC != 0);
    const gpa = elf_file.base.allocator;
    const code = try self.getCodeUncompressAlloc(elf_file);
    defer gpa.free(code);
    const relocs = self.getRelocs(elf_file);
    const object = self.getObject(elf_file);

    relocs_log.debug("{x}: {s}", .{ self.getAddress(elf_file), self.getName(elf_file) });

    var stream = std.io.fixedBufferStream(code);
    const cwriter = stream.writer();

    var i: usize = 0;
    while (i < relocs.len) : (i += 1) {
        const rel = relocs[i];
        const r_type = rel.r_type();

        if (r_type == elf.R_X86_64_NONE) continue;

        const target = object.getSymbol(rel.r_sym(), elf_file);

        // We will use equation format to resolve relocations:
        // https://intezer.com/blog/malware-analysis/executable-and-linkable-format-101-part-3-relocations/
        //
        // Address of the source atom.
        const P = @as(i64, @intCast(self.getAddress(elf_file) + rel.r_offset));
        // Addend from the relocation.
        const A = rel.r_addend;
        // Address of the target symbol - can be address of the symbol within an atom or address of PLT stub.
        const S = @as(i64, @intCast(target.getAddress(.{}, elf_file)));
        // Address of the global offset table.
        const GOT = blk: {
            const shndx = if (elf_file.got_plt_sect_index) |shndx|
                shndx
            else if (elf_file.got_sect_index) |shndx|
                shndx
            else
                null;
            break :blk if (shndx) |index| @as(i64, @intCast(elf_file.sections.items(.shdr)[index].sh_addr)) else 0;
        };
        // Relative offset to the start of the global offset table.
        const G = @as(i64, @intCast(target.getGotAddress(elf_file))) - GOT;
        // Address of the thread pointer.
        const TP = @as(i64, @intCast(elf_file.getTpAddress()));
        // Address of the dynamic thread pointer.
        const DTP = @as(i64, @intCast(elf_file.getDtpAddress()));

        relocs_log.debug("  {s}: {x}: [{x} => {x}] G({x}) ({s})", .{
            fmtRelocType(r_type),
            rel.r_offset,
            P,
            S + A,
            G + GOT + A,
            target.getName(elf_file),
        });

        try stream.seekTo(rel.r_offset);

        switch (r_type) {
            elf.R_X86_64_NONE => unreachable,
            elf.R_X86_64_64 => {
                try self.resolveDynAbsReloc(
                    target,
                    rel,
                    getDynAbsRelocAction(target, elf_file),
                    elf_file,
                    cwriter,
                );
            },

            elf.R_X86_64_PLT32,
            elf.R_X86_64_PC32,
            => try cwriter.writeInt(i32, @as(i32, @intCast(S + A - P)), .little),

            elf.R_X86_64_GOTPCREL => try cwriter.writeInt(i32, @as(i32, @intCast(G + GOT + A - P)), .little),
            elf.R_X86_64_GOTPC32 => try cwriter.writeInt(i32, @as(i32, @intCast(GOT + A - P)), .little),
            elf.R_X86_64_GOTPC64 => try cwriter.writeInt(i64, GOT + A - P, .little),

            elf.R_X86_64_GOTPCRELX => {
                if (!target.flags.import and !target.isIFunc(elf_file) and !target.isAbs(elf_file)) blk: {
                    relaxGotpcrelx(code[rel.r_offset - 2 ..]) catch break :blk;
                    try cwriter.writeInt(i32, @as(i32, @intCast(S + A - P)), .little);
                    continue;
                }
                try cwriter.writeInt(i32, @as(i32, @intCast(G + GOT + A - P)), .little);
            },

            elf.R_X86_64_REX_GOTPCRELX => {
                if (!target.flags.import and !target.isIFunc(elf_file) and !target.isAbs(elf_file)) blk: {
                    relaxRexGotpcrelx(code[rel.r_offset - 3 ..]) catch break :blk;
                    try cwriter.writeInt(i32, @as(i32, @intCast(S + A - P)), .little);
                    continue;
                }
                try cwriter.writeInt(i32, @as(i32, @intCast(G + GOT + A - P)), .little);
            },

            elf.R_X86_64_32 => try cwriter.writeInt(u32, @as(u32, @truncate(@as(u64, @intCast(S + A)))), .little),
            elf.R_X86_64_32S => try cwriter.writeInt(i32, @as(i32, @truncate(S + A)), .little),

            elf.R_X86_64_TPOFF32 => try cwriter.writeInt(i32, @as(i32, @truncate(S + A - TP)), .little),
            elf.R_X86_64_TPOFF64 => try cwriter.writeInt(i64, S + A - TP, .little),
            elf.R_X86_64_DTPOFF32 => try cwriter.writeInt(i32, @as(i32, @truncate(S + A - DTP)), .little),
            elf.R_X86_64_DTPOFF64 => try cwriter.writeInt(i64, S + A - DTP, .little),

            elf.R_X86_64_GOTTPOFF => {
                if (target.flags.gottp) {
                    const S_ = @as(i64, @intCast(target.getGotTpAddress(elf_file)));
                    try cwriter.writeInt(i32, @as(i32, @intCast(S_ + A - P)), .little);
                } else {
                    try relaxGotTpOff(code[rel.r_offset - 3 ..]);
                    try cwriter.writeInt(i32, @as(i32, @intCast(S - TP)), .little);
                }
            },

            elf.R_X86_64_TLSGD => {
                if (target.flags.tlsgd) {
                    const S_ = @as(i64, @intCast(target.getTlsGdAddress(elf_file)));
                    try cwriter.writeInt(i32, @as(i32, @intCast(S_ + A - P)), .little);
                } else if (target.flags.gottp) {
                    const S_ = @as(i64, @intCast(target.getGotTpAddress(elf_file)));
                    try relaxTlsGdToIe(relocs[i .. i + 2], @intCast(S_ - P), elf_file, &stream);
                    i += 1;
                } else {
                    try relaxTlsGdToLe(relocs[i .. i + 2], @as(i32, @intCast(S - TP)), elf_file, &stream);
                    i += 1;
                }
            },

            elf.R_X86_64_TLSLD => {
                if (elf_file.got.tlsld_index) |entry_index| {
                    const tlsld_entry = elf_file.got.entries.items[entry_index];
                    const S_ = @as(i64, @intCast(tlsld_entry.getAddress(elf_file)));
                    try cwriter.writeInt(i32, @as(i32, @intCast(S_ + A - P)), .little);
                } else {
                    try relaxTlsLdToLe(
                        relocs[i .. i + 2],
                        @as(i32, @intCast(TP - @as(i64, @intCast(elf_file.getTlsAddress())))),
                        elf_file,
                        &stream,
                    );
                    i += 1;
                }
            },

            elf.R_X86_64_GOTPC32_TLSDESC => {
                if (target.flags.tlsdesc) {
                    const S_ = @as(i64, @intCast(target.getTlsDescAddress(elf_file)));
                    try cwriter.writeInt(i32, @as(i32, @intCast(S_ + A - P)), .little);
                } else {
                    try relaxGotPcTlsDesc(code[rel.r_offset - 3 ..]);
                    try cwriter.writeInt(i32, @as(i32, @intCast(S - TP)), .little);
                }
            },

            elf.R_X86_64_TLSDESC_CALL => if (!target.flags.tlsdesc) {
                // call -> nop
                try cwriter.writeAll(&.{ 0x66, 0x90 });
            },

            else => elf_file.base.fatal("unhandled relocation type: {}", .{fmtRelocType(r_type)}),
        }
    }

    try writer.writeAll(code);
}

fn resolveDynAbsReloc(
    self: Atom,
    target: *const Symbol,
    rel: elf.Elf64_Rela,
    action: RelocAction,
    elf_file: *Elf,
    writer: anytype,
) !void {
    const tracy = trace(@src());
    defer tracy.end();

    const P = self.getAddress(elf_file) + rel.r_offset;
    const A = rel.r_addend;
    const S = @as(i64, @intCast(target.getAddress(.{}, elf_file)));
    const is_writeable = self.getInputShdr(elf_file).sh_flags & elf.SHF_WRITE != 0;
    const object = self.getObject(elf_file);

    try elf_file.rela_dyn.ensureUnusedCapacity(elf_file.base.allocator, object.num_dynrelocs);

    switch (action) {
        .@"error",
        .plt,
        => unreachable,

        .copyrel,
        .cplt,
        .none,
        => try writer.writeInt(i32, @as(i32, @truncate(S + A)), .little),

        .dyn_copyrel => {
            if (is_writeable or elf_file.options.z_nocopyreloc) {
                elf_file.addRelaDynAssumeCapacity(.{
                    .offset = P,
                    .sym = target.getExtra(elf_file).?.dynamic,
                    .type = elf.R_X86_64_64,
                    .addend = A,
                });
                try applyDynamicReloc(A, elf_file, writer);
            } else {
                try writer.writeInt(i32, @as(i32, @truncate(S + A)), .little);
            }
        },

        .dyn_cplt => {
            if (is_writeable) {
                elf_file.addRelaDynAssumeCapacity(.{
                    .offset = P,
                    .sym = target.getExtra(elf_file).?.dynamic,
                    .type = elf.R_X86_64_64,
                    .addend = A,
                });
                try applyDynamicReloc(A, elf_file, writer);
            } else {
                try writer.writeInt(i32, @as(i32, @truncate(S + A)), .little);
            }
        },

        .dynrel => {
            elf_file.addRelaDynAssumeCapacity(.{
                .offset = P,
                .sym = target.getExtra(elf_file).?.dynamic,
                .type = elf.R_X86_64_64,
                .addend = A,
            });
            try applyDynamicReloc(A, elf_file, writer);
        },

        .baserel => {
            elf_file.addRelaDynAssumeCapacity(.{
                .offset = P,
                .type = elf.R_X86_64_RELATIVE,
                .addend = S + A,
            });
            try applyDynamicReloc(S + A, elf_file, writer);
        },

        .ifunc => {
            const S_ = @as(i64, @intCast(target.getAddress(.{ .plt = false }, elf_file)));
            elf_file.addRelaDynAssumeCapacity(.{
                .offset = P,
                .type = elf.R_X86_64_IRELATIVE,
                .addend = S_ + A,
            });
            try applyDynamicReloc(S_ + A, elf_file, writer);
        },
    }
}

inline fn applyDynamicReloc(value: i64, elf_file: *Elf, writer: anytype) !void {
    if (elf_file.options.apply_dynamic_relocs) {
        try writer.writeInt(i64, value, .little);
    }
}

pub fn resolveRelocsNonAlloc(self: Atom, elf_file: *Elf, writer: anytype) !void {
    const tracy = trace(@src());
    defer tracy.end();

    assert(self.getInputShdr(elf_file).sh_flags & elf.SHF_ALLOC == 0);
    const gpa = elf_file.base.allocator;
    const code = try self.getCodeUncompressAlloc(elf_file);
    defer gpa.free(code);
    const relocs = self.getRelocs(elf_file);
    const object = self.getObject(elf_file);

    relocs_log.debug("{x}: {s}", .{ self.value, self.getName(elf_file) });

    var stream = std.io.fixedBufferStream(code);
    const cwriter = stream.writer();

    var i: usize = 0;
    while (i < relocs.len) : (i += 1) {
        const rel = relocs[i];
        const r_type = rel.r_type();

        if (r_type == elf.R_X86_64_NONE) continue;
        if (try self.reportUndefSymbol(rel, elf_file)) continue;

        const target = object.getSymbol(rel.r_sym(), elf_file);

        // We will use equation format to resolve relocations:
        // https://intezer.com/blog/malware-analysis/executable-and-linkable-format-101-part-3-relocations/
        //
        const P = self.value + rel.r_offset;
        // Addend from the relocation.
        const A = rel.r_addend;
        // Address of the target symbol - can be address of the symbol within an atom or address of PLT stub.
        const S = @as(i64, @intCast(target.getAddress(.{}, elf_file)));
        // Address of the global offset table.
        const GOT = blk: {
            const shndx = if (elf_file.got_plt_sect_index) |shndx|
                shndx
            else if (elf_file.got_sect_index) |shndx|
                shndx
            else
                null;
            break :blk if (shndx) |index| @as(i64, @intCast(elf_file.sections.items(.shdr)[index].sh_addr)) else 0;
        };
        // Address of the dynamic thread pointer.
        const DTP = @as(i64, @intCast(elf_file.getDtpAddress()));

        relocs_log.debug("  {s}: {x}: [{x} => {x}] ({s})", .{
            fmtRelocType(r_type),
            rel.r_offset,
            P,
            S + A,
            target.getName(elf_file),
        });

        try stream.seekTo(rel.r_offset);

        switch (r_type) {
            elf.R_X86_64_NONE => unreachable,
            elf.R_X86_64_8 => try cwriter.writeInt(u8, @as(u8, @bitCast(@as(i8, @intCast(S + A)))), .little),
            elf.R_X86_64_16 => try cwriter.writeInt(u16, @as(u16, @bitCast(@as(i16, @intCast(S + A)))), .little),
            elf.R_X86_64_32 => try cwriter.writeInt(u32, @as(u32, @bitCast(@as(i32, @intCast(S + A)))), .little),
            elf.R_X86_64_32S => try cwriter.writeInt(i32, @as(i32, @intCast(S + A)), .little),
            elf.R_X86_64_64 => try cwriter.writeInt(i64, S + A, .little),
            elf.R_X86_64_DTPOFF32 => try cwriter.writeInt(i32, @as(i32, @intCast(S + A - DTP)), .little),
            elf.R_X86_64_DTPOFF64 => try cwriter.writeInt(i64, S + A - DTP, .little),
            elf.R_X86_64_GOTOFF64 => try cwriter.writeInt(i64, S + A - GOT, .little),
            elf.R_X86_64_GOTPC64 => try cwriter.writeInt(i64, GOT + A, .little),
            elf.R_X86_64_SIZE32 => {
                const size = @as(i64, @intCast(target.getSourceSymbol(elf_file).st_size));
                try cwriter.writeInt(u32, @as(u32, @bitCast(@as(i32, @intCast(size + A)))), .little);
            },
            elf.R_X86_64_SIZE64 => {
                const size = @as(i64, @intCast(target.getSourceSymbol(elf_file).st_size));
                try cwriter.writeInt(i64, @as(i64, @intCast(size + A)), .little);
            },
            else => elf_file.base.fatal("{s}: invalid relocation type for non-alloc section: {}", .{
                self.getName(elf_file),
                fmtRelocType(r_type),
            }),
        }
    }

    try writer.writeAll(code);
}

fn relaxGotpcrelx(code: []u8) !void {
    const old_inst = disassemble(code) orelse return error.RelaxFail;
    const inst = switch (old_inst.encoding.mnemonic) {
        .call => try Instruction.new(old_inst.prefix, .call, &.{
            // TODO: hack to force imm32s in the assembler
            .{ .imm = Immediate.s(-129) },
        }),
        .jmp => try Instruction.new(old_inst.prefix, .jmp, &.{
            // TODO: hack to force imm32s in the assembler
            .{ .imm = Immediate.s(-129) },
        }),
        else => return error.RelaxFail,
    };
    relocs_log.debug("    relaxing {} => {}", .{ old_inst.encoding, inst.encoding });
    const nop = try Instruction.new(.none, .nop, &.{});
    encode(&.{ nop, inst }, code) catch return error.RelaxFail;
}

fn relaxRexGotpcrelx(code: []u8) !void {
    const old_inst = disassemble(code) orelse return error.RelaxFail;
    switch (old_inst.encoding.mnemonic) {
        .mov => {
            const inst = try Instruction.new(old_inst.prefix, .lea, &old_inst.ops);
            relocs_log.debug("    relaxing {} => {}", .{ old_inst.encoding, inst.encoding });
            encode(&.{inst}, code) catch return error.RelaxFail;
        },
        else => return error.RelaxFail,
    }
}

fn relaxTlsGdToIe(rels: []align(1) const elf.Elf64_Rela, value: i32, elf_file: *Elf, stream: anytype) !void {
    assert(rels.len == 2);
    const writer = stream.writer();
    switch (rels[1].r_type()) {
        elf.R_X86_64_PC32,
        elf.R_X86_64_PLT32,
        => {
            var insts = [_]u8{
                0x64, 0x48, 0x8b, 0x04, 0x25, 0, 0, 0, 0, // movq %fs:0,%rax
                0x48, 0x03, 0x05, 0, 0, 0, 0, // add foo@gottpoff(%rip), %rax
            };
            mem.writeInt(i32, insts[12..][0..4], value - 12, .little);
            try stream.seekBy(-4);
            try writer.writeAll(&insts);
        },

        else => elf_file.base.fatal("TODO rewrite {} when followed by {}", .{
            fmtRelocType(rels[0].r_type()),
            fmtRelocType(rels[1].r_type()),
        }),
    }
}

fn relaxTlsGdToLe(rels: []align(1) const elf.Elf64_Rela, value: i32, elf_file: *Elf, stream: anytype) !void {
    assert(rels.len == 2);
    const writer = stream.writer();
    switch (rels[1].r_type()) {
        elf.R_X86_64_PC32,
        elf.R_X86_64_PLT32,
        elf.R_X86_64_GOTPCREL,
        elf.R_X86_64_GOTPCRELX,
        => {
            var insts = [_]u8{
                0x64, 0x48, 0x8b, 0x04, 0x25, 0, 0, 0, 0, // movq %fs:0,%rax
                0x48, 0x81, 0xc0, 0, 0, 0, 0, // add $tp_offset, %rax
            };
            mem.writeInt(i32, insts[12..][0..4], value, .little);
            try stream.seekBy(-4);
            try writer.writeAll(&insts);
        },

        else => elf_file.base.fatal("TODO rewrite {} when followed by {}", .{
            fmtRelocType(rels[0].r_type()),
            fmtRelocType(rels[1].r_type()),
        }),
    }
}

fn relaxTlsLdToLe(rels: []align(1) const elf.Elf64_Rela, value: i32, elf_file: *Elf, stream: anytype) !void {
    assert(rels.len == 2);
    const writer = stream.writer();
    switch (rels[1].r_type()) {
        elf.R_X86_64_PC32,
        elf.R_X86_64_PLT32,
        => {
            var insts = [_]u8{
                0x31, 0xc0, // xor %eax, %eax
                0x64, 0x48, 0x8b, 0, // mov %fs:(%rax), %rax
                0x48, 0x2d, 0, 0, 0, 0, // sub $tls_size, %rax
            };
            mem.writeInt(i32, insts[8..][0..4], value, .little);
            try stream.seekBy(-3);
            try writer.writeAll(&insts);
        },

        elf.R_X86_64_GOTPCREL,
        elf.R_X86_64_GOTPCRELX,
        => {
            var insts = [_]u8{
                0x31, 0xc0, // xor %eax, %eax
                0x64, 0x48, 0x8b, 0, // mov %fs:(%rax), %rax
                0x48, 0x2d, 0, 0, 0, 0, // sub $tls_size, %rax
                0x90, // nop
            };
            mem.writeInt(i32, insts[8..][0..4], value, .little);
            try stream.seekBy(-3);
            try writer.writeAll(&insts);
        },

        else => elf_file.base.fatal("TODO rewrite {} when followed by {}", .{
            fmtRelocType(rels[0].r_type()),
            fmtRelocType(rels[1].r_type()),
        }),
    }
}

fn relaxGotTpOff(code: []u8) !void {
    const old_inst = disassemble(code) orelse return error.RelaxFail;
    switch (old_inst.encoding.mnemonic) {
        .mov => {
            const inst = try Instruction.new(old_inst.prefix, .mov, &.{
                old_inst.ops[0],
                // TODO: hack to force imm32s in the assembler
                .{ .imm = Immediate.s(-129) },
            });
            relocs_log.debug("    relaxing {} => {}", .{ old_inst.encoding, inst.encoding });
            encode(&.{inst}, code) catch return error.RelaxFail;
        },
        else => return error.RelaxFail,
    }
}

fn relaxGotPcTlsDesc(code: []u8) !void {
    const old_inst = disassemble(code) orelse return error.RelaxFail;
    switch (old_inst.encoding.mnemonic) {
        .lea => {
            const inst = try Instruction.new(old_inst.prefix, .mov, &.{
                old_inst.ops[0],
                // TODO: hack to force imm32s in the assembler
                .{ .imm = Immediate.s(-129) },
            });
            relocs_log.debug("    relaxing {} => {}", .{ old_inst.encoding, inst.encoding });
            encode(&.{inst}, code) catch return error.RelaxFail;
        },
        else => return error.RelaxFail,
    }
}

fn disassemble(code: []const u8) ?Instruction {
    var disas = Disassembler.init(code);
    const inst = disas.next() catch return null;
    return inst;
}

fn encode(insts: []const Instruction, code: []u8) !void {
    var stream = std.io.fixedBufferStream(code);
    const writer = stream.writer();
    for (insts) |inst| {
        try inst.encode(writer, .{});
    }
}

pub fn fmtRelocType(r_type: u32) std.fmt.Formatter(formatRelocType) {
    return .{ .data = r_type };
}

fn formatRelocType(
    r_type: u32,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = unused_fmt_string;
    _ = options;
    const str = switch (r_type) {
        elf.R_X86_64_NONE => "R_X86_64_NONE",
        elf.R_X86_64_64 => "R_X86_64_64",
        elf.R_X86_64_PC32 => "R_X86_64_PC32",
        elf.R_X86_64_GOT32 => "R_X86_64_GOT32",
        elf.R_X86_64_PLT32 => "R_X86_64_PLT32",
        elf.R_X86_64_COPY => "R_X86_64_COPY",
        elf.R_X86_64_GLOB_DAT => "R_X86_64_GLOB_DAT",
        elf.R_X86_64_JUMP_SLOT => "R_X86_64_JUMP_SLOT",
        elf.R_X86_64_RELATIVE => "R_X86_64_RELATIVE",
        elf.R_X86_64_GOTPCREL => "R_X86_64_GOTPCREL",
        elf.R_X86_64_32 => "R_X86_64_32",
        elf.R_X86_64_32S => "R_X86_64_32S",
        elf.R_X86_64_16 => "R_X86_64_16",
        elf.R_X86_64_PC16 => "R_X86_64_PC16",
        elf.R_X86_64_8 => "R_X86_64_8",
        elf.R_X86_64_PC8 => "R_X86_64_PC8",
        elf.R_X86_64_DTPMOD64 => "R_X86_64_DTPMOD64",
        elf.R_X86_64_DTPOFF64 => "R_X86_64_DTPOFF64",
        elf.R_X86_64_TPOFF64 => "R_X86_64_TPOFF64",
        elf.R_X86_64_TLSGD => "R_X86_64_TLSGD",
        elf.R_X86_64_TLSLD => "R_X86_64_TLSLD",
        elf.R_X86_64_DTPOFF32 => "R_X86_64_DTPOFF32",
        elf.R_X86_64_GOTTPOFF => "R_X86_64_GOTTPOFF",
        elf.R_X86_64_TPOFF32 => "R_X86_64_TPOFF32",
        elf.R_X86_64_PC64 => "R_X86_64_PC64",
        elf.R_X86_64_GOTOFF64 => "R_X86_64_GOTOFF64",
        elf.R_X86_64_GOTPC32 => "R_X86_64_GOTPC32",
        elf.R_X86_64_GOT64 => "R_X86_64_GOT64",
        elf.R_X86_64_GOTPCREL64 => "R_X86_64_GOTPCREL64",
        elf.R_X86_64_GOTPC64 => "R_X86_64_GOTPC64",
        elf.R_X86_64_GOTPLT64 => "R_X86_64_GOTPLT64",
        elf.R_X86_64_PLTOFF64 => "R_X86_64_PLTOFF64",
        elf.R_X86_64_SIZE32 => "R_X86_64_SIZE32",
        elf.R_X86_64_SIZE64 => "R_X86_64_SIZE64",
        elf.R_X86_64_GOTPC32_TLSDESC => "R_X86_64_GOTPC32_TLSDESC",
        elf.R_X86_64_TLSDESC_CALL => "R_X86_64_TLSDESC_CALL",
        elf.R_X86_64_TLSDESC => "R_X86_64_TLSDESC",
        elf.R_X86_64_IRELATIVE => "R_X86_64_IRELATIVE",
        elf.R_X86_64_RELATIVE64 => "R_X86_64_RELATIVE64",
        elf.R_X86_64_GOTPCRELX => "R_X86_64_GOTPCRELX",
        elf.R_X86_64_REX_GOTPCRELX => "R_X86_64_REX_GOTPCRELX",
        elf.R_X86_64_NUM => "R_X86_64_NUM",
        else => "R_X86_64_UNKNOWN",
    };
    try writer.print("{s}", .{str});
}

pub fn format(
    atom: Atom,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = atom;
    _ = unused_fmt_string;
    _ = options;
    _ = writer;
    @compileError("do not format symbols directly");
}

pub fn fmt(atom: Atom, elf_file: *Elf) std.fmt.Formatter(format2) {
    return .{ .data = .{
        .atom = atom,
        .elf_file = elf_file,
    } };
}

const FormatContext = struct {
    atom: Atom,
    elf_file: *Elf,
};

fn format2(
    ctx: FormatContext,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = unused_fmt_string;
    const atom = ctx.atom;
    const elf_file = ctx.elf_file;
    try writer.print("atom({d}) : {s} : @{x} : sect({d}) : align({x}) : size({x})", .{
        atom.atom_index, atom.getName(elf_file), atom.getAddress(elf_file),
        atom.out_shndx,  atom.alignment,         atom.size,
    });
    if (atom.fde_start != atom.fde_end) {
        try writer.writeAll(" : fdes{ ");
        for (atom.getFdes(elf_file), atom.fde_start..) |fde, i| {
            try writer.print("{d}", .{i});
            if (!fde.alive) try writer.writeAll("([*])");
            if (i < atom.fde_end - 1) try writer.writeAll(", ");
        }
        try writer.writeAll(" }");
    }
    if (elf_file.options.gc_sections and !atom.flags.alive) {
        try writer.writeAll(" : [*]");
    }
}

pub const Index = u32;

pub const Flags = packed struct {
    /// Specifies whether this atom is alive or has been garbage collected.
    alive: bool = true,

    /// Specifies if the atom has been visited during garbage collection.
    visited: bool = false,
};

const Atom = @This();

const std = @import("std");
const assert = std.debug.assert;
const dis_x86_64 = @import("dis_x86_64");
const elf = std.elf;
const log = std.log.scoped(.elf);
const relocs_log = std.log.scoped(.relocs);
const math = std.math;
const mem = std.mem;
const trace = @import("../tracy.zig").trace;

const Allocator = mem.Allocator;
const Disassembler = dis_x86_64.Disassembler;
const Elf = @import("../Elf.zig");
const Fde = @import("eh_frame.zig").Fde;
const File = @import("file.zig").File;
const Instruction = dis_x86_64.Instruction;
const Immediate = dis_x86_64.Immediate;
const Object = @import("Object.zig");
const Symbol = @import("Symbol.zig");
