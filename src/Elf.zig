base: Zld,
arena: std.heap.ArenaAllocator.State,
options: Options,
shoff: u64 = 0,

objects: std.ArrayListUnmanaged(u32) = .{},
shared_objects: std.ArrayListUnmanaged(u32) = .{},
files: std.MultiArrayList(File.Entry) = .{},

sections: std.MultiArrayList(Section) = .{},
phdrs: std.ArrayListUnmanaged(elf.Elf64_Phdr) = .{},

tls_phdr_index: ?u16 = null,

text_sect_index: ?u16 = null,
plt_sect_index: ?u16 = null,
got_sect_index: ?u16 = null,
got_plt_sect_index: ?u16 = null,
rela_dyn_sect_index: ?u16 = null,
rela_plt_sect_index: ?u16 = null,
symtab_sect_index: ?u16 = null,
strtab_sect_index: ?u16 = null,
shstrtab_sect_index: ?u16 = null,
interp_sect_index: ?u16 = null,
dynamic_sect_index: ?u16 = null,
dynsymtab_sect_index: ?u16 = null,
dynstrtab_sect_index: ?u16 = null,
hash_sect_index: ?u16 = null,

internal_object_index: ?u32 = null,
dynamic_index: ?u32 = null,
init_array_start_index: ?u32 = null,
init_array_end_index: ?u32 = null,
fini_array_start_index: ?u32 = null,
fini_array_end_index: ?u32 = null,
got_index: ?u32 = null,

entry_index: ?u32 = null,

symbols: std.ArrayListUnmanaged(Symbol) = .{},
symbols_extra: std.ArrayListUnmanaged(u32) = .{},
// TODO convert to context-adapted
globals: std.StringHashMapUnmanaged(u32) = .{},

string_intern: StringTable(.string_intern) = .{},

shstrtab: StringTable(.shstrtab) = .{},
strtab: StringTable(.strtab) = .{},
symtab: SymtabSection = .{},
dynsym: DynsymSection = .{},
dynstrtab: StringTable(.dynstrtab) = .{},

dynamic: DynamicSection = .{},
hash: HashSection = .{},
got: GotSection = .{},
plt: PltSection = .{},

atoms: std.ArrayListUnmanaged(Atom) = .{},

pub fn openPath(allocator: Allocator, options: Options, thread_pool: *ThreadPool) !*Elf {
    const file = try options.emit.directory.createFile(options.emit.sub_path, .{
        .truncate = true,
        .read = true,
        .mode = if (builtin.os.tag == .windows) 0 else 0o777,
    });
    errdefer file.close();

    const self = try createEmpty(allocator, options, thread_pool);
    errdefer allocator.destroy(self);

    self.base.file = file;

    return self;
}

fn createEmpty(gpa: Allocator, options: Options, thread_pool: *ThreadPool) !*Elf {
    const self = try gpa.create(Elf);

    self.* = .{
        .base = .{
            .tag = .elf,
            .allocator = gpa,
            .file = undefined,
            .thread_pool = thread_pool,
        },
        .arena = std.heap.ArenaAllocator.init(gpa).state,
        .options = options,
    };

    return self;
}

pub fn deinit(self: *Elf) void {
    const gpa = self.base.allocator;
    self.string_intern.deinit(gpa);
    self.symtab.deinit(gpa);
    self.strtab.deinit(gpa);
    self.shstrtab.deinit(gpa);
    self.atoms.deinit(gpa);
    self.symbols.deinit(gpa);
    self.symbols_extra.deinit(gpa);
    self.globals.deinit(gpa);
    self.got.deinit(gpa);
    self.plt.deinit(gpa);
    self.phdrs.deinit(gpa);
    self.sections.deinit(gpa);
    for (self.files.items(.tags), self.files.items(.data)) |tag, *data| switch (tag) {
        .null => {},
        .internal => data.internal.deinit(gpa),
        .object => data.object.deinit(gpa),
        .shared => data.shared.deinit(gpa),
    };
    self.files.deinit(gpa);
    self.objects.deinit(gpa);
    self.shared_objects.deinit(gpa);
    self.dynsym.deinit(gpa);
    self.dynstrtab.deinit(gpa);
    self.dynamic.deinit(gpa);
    self.hash.deinit(gpa);
    self.arena.promote(gpa).deinit();
}

fn resolveLib(
    arena: Allocator,
    search_dirs: []const []const u8,
    name: []const u8,
    opts: Zld.SystemLib,
) !?[]const u8 {
    if (fs.path.isAbsolute(name)) return try arena.dupe(u8, name);
    if (!opts.static) {
        const search_name = blk: {
            if (hasSharedLibraryExt(name)) break :blk name;
            break :blk try std.fmt.allocPrint(arena, "lib{s}.so", .{name});
        };
        if (try resolveLibPath(arena, search_dirs, search_name)) |full_path| return full_path;
    }
    const search_name = blk: {
        if (mem.endsWith(u8, name, ".a")) break :blk name;
        break :blk try std.fmt.allocPrint(arena, "lib{s}.a", .{name});
    };
    if (try resolveLibPath(arena, search_dirs, search_name)) |full_path| return full_path;
    return null;
}

fn resolveLibPath(arena: Allocator, search_dirs: []const []const u8, search_name: []const u8) !?[]const u8 {
    for (search_dirs) |dir| {
        const full_path = try fs.path.join(arena, &[_][]const u8{ dir, search_name });
        // Check if the file exists.
        const tmp = fs.cwd().openFile(full_path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| return e,
        };
        defer tmp.close();
        return full_path;
    }
    return null;
}

fn hasSharedLibraryExt(filename: []const u8) bool {
    if (mem.endsWith(u8, filename, ".so")) return true;
    // Look for .so.X, .so.X.Y, .so.X.Y.Z
    var it = mem.split(u8, filename, ".");
    _ = it.first();
    var so_txt = it.next() orelse return false;
    while (!mem.eql(u8, so_txt, "so")) {
        so_txt = it.next() orelse return false;
    }
    const n1 = it.next() orelse return false;
    const n2 = it.next();
    const n3 = it.next();

    _ = std.fmt.parseInt(u32, n1, 10) catch return false;
    if (n2) |x| _ = std.fmt.parseInt(u32, x, 10) catch return false;
    if (n3) |x| _ = std.fmt.parseInt(u32, x, 10) catch return false;
    if (it.next() != null) return false;

    return true;
}

pub fn flush(self: *Elf) !void {
    const gpa = self.base.allocator;

    // Append empty string to string tables.
    try self.string_intern.buffer.append(gpa, 0);
    try self.shstrtab.buffer.append(gpa, 0);
    try self.strtab.buffer.append(gpa, 0);
    try self.dynstrtab.buffer.append(gpa, 0);
    // Append null section.
    _ = try self.addSection(.{ .name = "" });
    // Append null atom.
    try self.atoms.append(gpa, .{});
    // Append null symbols.
    try self.symbols_extra.append(gpa, 0);
    // Append null file.
    try self.files.append(gpa, .null);

    var arena_allocator = self.arena.promote(gpa);
    defer self.arena = arena_allocator.state;
    const arena = arena_allocator.allocator();

    var search_dirs = std.ArrayList([]const u8).init(arena);
    for (self.options.search_dirs) |dir| {
        // Verify that search path actually exists
        var tmp = fs.cwd().openDir(dir, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                self.base.warn("{s}: library search directory not found", .{dir});
                continue;
            },
            else => |e| return e,
        };
        defer tmp.close();
        try search_dirs.append(dir);
    }

    var libs = std.StringArrayHashMap(Zld.SystemLib).init(arena);

    const parse_ctx = ParseLibsCtx{
        .search_dirs = search_dirs.items,
        .libs = &libs,
    };

    for (self.options.positionals) |obj| {
        try self.parsePositional(arena, obj, parse_ctx);
    }

    self.base.reportWarningsAndErrorsAndExit();

    for (self.options.libs.keys(), self.options.libs.values()) |lib_name, lib_info| {
        try self.parseLib(arena, lib_name, lib_info, parse_ctx);
    }

    if (self.base.errors.items.len > 0) {
        self.base.fatal("library search paths:", .{});
        for (search_dirs.items) |dir| {
            self.base.fatal("  {s}", .{dir});
        }
    }
    self.base.reportWarningsAndErrorsAndExit();

    // Dedup DSOs
    {
        var seen_dsos = std.StringHashMap(void).init(gpa);
        defer seen_dsos.deinit();
        try seen_dsos.ensureTotalCapacity(@intCast(u32, self.shared_objects.items.len));

        var i: usize = 0;
        while (i < self.shared_objects.items.len) {
            const index = self.shared_objects.items[i];
            const shared = self.getFile(index).?.shared;
            const soname = shared.getSoname();
            const gop = seen_dsos.getOrPutAssumeCapacity(soname);
            if (gop.found_existing) {
                _ = self.shared_objects.swapRemove(i);
            } else i += 1;
        }
    }

    {
        const index = @intCast(File.Index, try self.files.addOne(gpa));
        self.files.set(index, .{ .internal = .{ .index = index } });
        self.internal_object_index = index;
    }

    try self.resolveSymbols();
    try self.markImportsAndExports();

    // Set the entrypoint if found
    self.entry_index = blk: {
        if (self.options.output_mode != .exe) break :blk null;
        const entry_name = self.options.entry orelse "_start";
        break :blk self.globals.get(entry_name) orelse null;
    };
    if (self.options.output_mode == .exe and self.entry_index == null) {
        self.base.fatal("no entrypoint found: '{s}'", .{self.options.entry orelse "_start"});
    }

    if (self.options.gc_sections) {
        try gc.gcAtoms(self);

        if (self.options.print_gc_sections) {
            try gc.dumpPrunedAtoms(self);
        }
    }

    if (!self.options.allow_multiple_definition) {
        self.checkDuplicates();
        self.base.reportWarningsAndErrorsAndExit();
    }

    try self.resolveSyntheticSymbols();

    if (self.options.execstack_if_needed) {
        for (self.objects.items) |index| {
            if (self.getFile(index).?.object.needs_exec_stack) {
                self.options.execstack = true;
                break;
            }
        }
    }

    self.claimUnresolved();
    try self.scanRelocs();
    self.checkUndefined();
    self.base.reportWarningsAndErrorsAndExit();

    try self.initSections();
    try self.sortSections();
    try self.setDynamic();
    try self.setHash();
    try self.setSymtab();
    try self.calcSectionSizes();

    try self.allocateSections();
    self.allocateAtoms();
    self.allocateLocals();
    self.allocateGlobals();
    self.allocateSyntheticSymbols();

    self.shoff = blk: {
        const shdr = self.sections.items(.shdr)[self.sections.len - 1];
        const offset = shdr.sh_offset + shdr.sh_size;
        break :blk mem.alignForwardGeneric(u64, offset, @alignOf(elf.Elf64_Shdr));
    };

    state_log.debug("{}", .{self.dumpState()});

    try self.writeAtoms();
    try self.writeSyntheticSections();
    try self.writePhdrs();
    try self.writeShdrs();
    try self.writeHeader();

    self.base.reportWarningsAndErrorsAndExit();
}

fn initSections(self: *Elf) !void {
    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.atoms.items) |atom_index| {
            const atom = self.getAtom(atom_index) orelse continue;
            if (!atom.is_alive) continue;
            try atom.initOutputSection(self);
        }
    }

    if (self.got.symbols.items.len > 0) {
        self.got_sect_index = try self.addSection(.{
            .name = ".got",
            .type = elf.SHT_PROGBITS,
            .flags = elf.SHF_ALLOC | elf.SHF_WRITE,
            .addralign = @alignOf(u64),
        });

        if (self.got.needs_rela) {
            self.rela_dyn_sect_index = try self.addSection(.{
                .name = ".rela.dyn",
                .type = elf.SHT_RELA,
                .flags = elf.SHF_ALLOC,
                .addralign = @alignOf(elf.Elf64_Rela),
                .entsize = @sizeOf(elf.Elf64_Rela),
            });
        }
    }

    if (self.plt.symbols.items.len > 0) {
        self.plt_sect_index = try self.addSection(.{
            .name = ".plt",
            .type = elf.SHT_PROGBITS,
            .flags = elf.SHF_ALLOC | elf.SHF_EXECINSTR,
            .addralign = 16,
        });
        self.got_plt_sect_index = try self.addSection(.{
            .name = ".got.plt",
            .type = elf.SHT_PROGBITS,
            .flags = elf.SHF_ALLOC | elf.SHF_WRITE,
            .addralign = @alignOf(u64),
        });
        self.rela_plt_sect_index = try self.addSection(.{
            .name = ".rela.plt",
            .type = elf.SHT_RELA,
            .flags = elf.SHF_ALLOC,
            .addralign = @alignOf(elf.Elf64_Rela),
            .entsize = @sizeOf(elf.Elf64_Rela),
        });
    }

    self.shstrtab_sect_index = try self.addSection(.{
        .name = ".shstrtab",
        .type = elf.SHT_STRTAB,
        .entsize = 1,
        .addralign = 1,
    });

    if (!self.options.strip_all) {
        self.strtab_sect_index = try self.addSection(.{
            .name = ".strtab",
            .type = elf.SHT_STRTAB,
            .entsize = 1,
            .addralign = 1,
        });
        self.symtab_sect_index = try self.addSection(.{
            .name = ".symtab",
            .type = elf.SHT_SYMTAB,
            .addralign = @alignOf(elf.Elf64_Sym),
            .entsize = @sizeOf(elf.Elf64_Sym),
        });
    }

    if (self.options.dynamic_linker != null) {
        self.interp_sect_index = try self.addSection(.{
            .name = ".interp",
            .type = elf.SHT_PROGBITS,
            .flags = elf.SHF_ALLOC,
            .addralign = 1,
        });
    }

    if (self.shared_objects.items.len > 0) {
        self.dynstrtab_sect_index = try self.addSection(.{
            .name = ".dynstr",
            .flags = elf.SHF_ALLOC,
            .type = elf.SHT_STRTAB,
            .entsize = 1,
            .addralign = 1,
        });
        self.dynamic_sect_index = try self.addSection(.{
            .name = ".dynamic",
            .flags = elf.SHF_ALLOC | elf.SHF_WRITE,
            .type = elf.SHT_DYNAMIC,
            .entsize = @sizeOf(elf.Elf64_Dyn),
            .addralign = @alignOf(elf.Elf64_Dyn),
        });
        self.dynsymtab_sect_index = try self.addSection(.{
            .name = ".dynsym",
            .flags = elf.SHF_ALLOC,
            .type = elf.SHT_DYNSYM,
            .addralign = @alignOf(elf.Elf64_Sym),
            .entsize = @sizeOf(elf.Elf64_Sym),
        });
        self.hash_sect_index = try self.addSection(.{
            .name = ".hash",
            .flags = elf.SHF_ALLOC,
            .type = elf.SHT_HASH,
            .addralign = 4,
            .entsize = 4,
        });
    }
}

fn calcSectionSizes(self: *Elf) !void {
    var slice = self.sections.slice();
    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.atoms.items) |atom_index| {
            const atom = self.getAtom(atom_index) orelse continue;
            if (!atom.is_alive) continue;

            var section = slice.get(atom.out_shndx);
            const alignment = try math.powi(u64, 2, atom.alignment);
            const addr = mem.alignForwardGeneric(u64, section.shdr.sh_size, alignment);
            const padding = addr - section.shdr.sh_size;
            atom.value = addr;
            section.shdr.sh_size += padding + atom.size;
            section.shdr.sh_addralign = @max(section.shdr.sh_addralign, alignment);

            if (section.last_atom) |last_atom_index| {
                const last_atom = self.getAtom(last_atom_index).?;
                last_atom.next = @intCast(u32, atom_index);
                atom.prev = last_atom_index;
            } else {
                assert(section.first_atom == null);
                section.first_atom = @intCast(u32, atom_index);
            }
            section.last_atom = @intCast(u32, atom_index);

            slice.set(atom.out_shndx, section);
        }
    }

    if (self.got_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.got.sizeGot();
        shdr.sh_addralign = @alignOf(u64);
    }

    if (self.plt_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.plt.sizePlt();
        shdr.sh_addralign = 16;
    }

    if (self.got_plt_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.plt.sizeGotPlt();
        shdr.sh_addralign = @alignOf(u64);
    }

    if (self.rela_dyn_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.got.sizeRela(self);
    }

    if (self.rela_plt_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.plt.sizeRela();
    }

    if (self.interp_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        const size = self.options.dynamic_linker.?.len + 1;
        shdr.sh_size = size;
        shdr.sh_addralign = 1;
    }

    if (self.hash_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.hash.size();
    }

    if (self.dynamic_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.dynamic.size(self);
    }

    if (self.dynsymtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.dynsym.size();
    }

    if (self.dynstrtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.dynstrtab.buffer.items.len;
    }

    if (self.symtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.symtab.size();
    }

    if (self.strtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.strtab.buffer.items.len;
    }

    if (self.shstrtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_size = self.shstrtab.buffer.items.len;
    }
}

fn initPhdrs(self: *Elf) !void {
    // Add PHDR phdr
    const phdr_index = try self.addPhdr(.{
        .type = elf.PT_PHDR,
        .flags = elf.PF_R,
        .@"align" = @alignOf(elf.Elf64_Phdr),
        .addr = default_base_addr + @sizeOf(elf.Elf64_Ehdr),
        .offset = @sizeOf(elf.Elf64_Ehdr),
    });

    // Add INTERP phdr if required
    if (self.interp_sect_index) |index| {
        const shdr = self.sections.items(.shdr)[index];
        _ = try self.addPhdr(.{
            .type = elf.PT_INTERP,
            .flags = elf.PF_R,
            .@"align" = 1,
            .offset = shdr.sh_offset,
            .addr = shdr.sh_addr,
            .filesz = shdr.sh_size,
            .memsz = shdr.sh_size,
        });
    }

    // Add LOAD phdrs
    const slice = self.sections.slice();
    {
        var last_phdr: ?u16 = null;
        var shndx: usize = 0;
        while (shndx < slice.len) {
            const shdr = &slice.items(.shdr)[shndx];
            if (!shdrIsAlloc(shdr) or shdrIsTbss(shdr)) {
                shndx += 1;
                continue;
            }
            last_phdr = try self.addPhdr(.{
                .type = elf.PT_LOAD,
                .flags = shdrToPhdrFlags(shdr.sh_flags),
                .@"align" = @max(default_page_size, shdr.sh_addralign),
                .offset = if (last_phdr == null) 0 else shdr.sh_offset,
                .addr = if (last_phdr == null) default_base_addr else shdr.sh_addr,
            });
            const p_flags = self.phdrs.items[last_phdr.?].p_flags;
            try self.addShdrToPhdr(last_phdr.?, shdr);
            shndx += 1;

            while (shndx < slice.len) : (shndx += 1) {
                const next = &slice.items(.shdr)[shndx];
                if (shdrIsTbss(next)) continue;
                if (p_flags == shdrToPhdrFlags(next.sh_flags)) {
                    if (shdrIsBss(next) or next.sh_offset - shdr.sh_offset == next.sh_addr - shdr.sh_addr) {
                        try self.addShdrToPhdr(last_phdr.?, next);
                        continue;
                    }
                }
                break;
            }
        }
    }

    // Add TLS phdr
    {
        var shndx: usize = 0;
        outer: while (shndx < slice.len) {
            const shdr = &slice.items(.shdr)[shndx];
            if (!shdrIsTls(shdr)) {
                shndx += 1;
                continue;
            }
            self.tls_phdr_index = try self.addPhdr(.{
                .type = elf.PT_TLS,
                .flags = elf.PF_R,
                .@"align" = shdr.sh_addralign,
                .offset = shdr.sh_offset,
                .addr = shdr.sh_addr,
            });
            try self.addShdrToPhdr(self.tls_phdr_index.?, shdr);
            shndx += 1;

            while (shndx < slice.len) : (shndx += 1) {
                const next = &slice.items(.shdr)[shndx];
                if (!shdrIsTls(next)) continue :outer;
                try self.addShdrToPhdr(self.tls_phdr_index.?, next);
            }
        }
    }

    // Add DYNAMIC phdr
    if (self.dynamic_sect_index) |index| {
        const shdr = self.sections.items(.shdr)[index];
        _ = try self.addPhdr(.{
            .type = elf.PT_DYNAMIC,
            .flags = elf.PF_R | elf.PF_W,
            .@"align" = shdr.sh_addralign,
            .offset = shdr.sh_offset,
            .addr = shdr.sh_addr,
            .memsz = shdr.sh_size,
            .filesz = shdr.sh_size,
        });
    }

    // Add PT_GNU_STACK phdr that controls some stack attributes that apparently may or may not
    // be respected by the OS.
    _ = try self.addPhdr(.{
        .type = elf.PT_GNU_STACK,
        .flags = if (self.options.execstack) elf.PF_W | elf.PF_R | elf.PF_X else elf.PF_W | elf.PF_R,
        .memsz = self.options.stack_size orelse 0,
    });

    // Backpatch size of the PHDR phdr
    {
        const phdr = &self.phdrs.items[phdr_index];
        const size = @sizeOf(elf.Elf64_Phdr) * self.phdrs.items.len;
        phdr.p_filesz = size;
        phdr.p_memsz = size;
    }
}

fn addShdrToPhdr(self: *Elf, phdr_index: u16, shdr: *const elf.Elf64_Shdr) !void {
    const phdr = &self.phdrs.items[phdr_index];
    phdr.p_align = @max(phdr.p_align, shdr.sh_addralign);
    if (shdr.sh_type != elf.SHT_NOBITS) {
        phdr.p_filesz = shdr.sh_addr + shdr.sh_size - phdr.p_vaddr;
    }
    phdr.p_memsz = shdr.sh_addr + shdr.sh_size - phdr.p_vaddr;
}

fn shdrToPhdrFlags(sh_flags: u64) u32 {
    const write = sh_flags & elf.SHF_WRITE != 0;
    const exec = sh_flags & elf.SHF_EXECINSTR != 0;
    var out_flags: u32 = elf.PF_R;
    if (write) out_flags |= elf.PF_W;
    if (exec) out_flags |= elf.PF_X;
    return out_flags;
}

inline fn shdrIsAlloc(shdr: *const elf.Elf64_Shdr) bool {
    return shdr.sh_flags & elf.SHF_ALLOC != 0;
}

inline fn shdrIsBss(shdr: *const elf.Elf64_Shdr) bool {
    return shdr.sh_type == elf.SHT_NOBITS and !shdrIsTls(shdr);
}

inline fn shdrIsTbss(shdr: *const elf.Elf64_Shdr) bool {
    return shdr.sh_type == elf.SHT_NOBITS and shdrIsTls(shdr);
}

inline fn shdrIsTls(shdr: *const elf.Elf64_Shdr) bool {
    return shdr.sh_flags & elf.SHF_TLS != 0;
}

fn allocateSectionsInMemory(self: *Elf, base_offset: u64) !void {
    var addr = default_base_addr + base_offset;
    outer: for (self.sections.items(.shdr)[1..], 1..) |*shdr, i| {
        if (!shdrIsAlloc(shdr)) continue;
        if (i != 1) {
            const prev_shdr = self.sections.items(.shdr)[i - 1];
            if (shdrToPhdrFlags(shdr.sh_flags) != shdrToPhdrFlags(prev_shdr.sh_flags)) {
                // We need advance by page size
                addr += default_page_size;
            }
        }
        if (shdrIsTbss(shdr)) {
            var tbss_addr = addr;
            for (self.sections.items(.shdr)[i..]) |*tbss_shdr| {
                if (!shdrIsTbss(tbss_shdr)) continue :outer;
                tbss_addr = mem.alignForwardGeneric(u64, tbss_addr, tbss_shdr.sh_addralign);
                tbss_shdr.sh_addr = tbss_addr;
                tbss_addr += tbss_shdr.sh_size;
            }
        }

        addr = mem.alignForwardGeneric(u64, addr, shdr.sh_addralign);
        shdr.sh_addr = addr;
        addr += shdr.sh_size;
    }
}

fn allocatesSectionsInFile(self: *Elf, base_offset: u64) void {
    var offset = base_offset;
    for (self.sections.items(.shdr)[1..]) |*shdr| {
        if (shdr.sh_type == elf.SHT_NOBITS) continue;
        shdr.sh_offset = mem.alignForwardGeneric(u64, offset, shdr.sh_addralign);
        offset = shdr.sh_offset + shdr.sh_size;
    }
}

fn allocateSections(self: *Elf) !void {
    while (true) {
        const nphdrs = self.phdrs.items.len;
        const base_offset: u64 = @sizeOf(elf.Elf64_Ehdr) + nphdrs * @sizeOf(elf.Elf64_Phdr);
        try self.allocateSectionsInMemory(base_offset);
        self.allocatesSectionsInFile(base_offset);
        self.phdrs.clearRetainingCapacity();
        try self.initPhdrs();
        if (nphdrs == self.phdrs.items.len) break;
    }
}

fn getSectionRank(self: *Elf, shndx: u16) u8 {
    const shdr = self.sections.items(.shdr)[shndx];
    const name = self.shstrtab.getAssumeExists(shdr.sh_name);
    const flags = shdr.sh_flags;
    switch (shdr.sh_type) {
        elf.SHT_NULL => return 0,
        elf.SHT_DYNSYM => return 2,
        elf.SHT_HASH => return 3,

        elf.SHT_PREINIT_ARRAY,
        elf.SHT_INIT_ARRAY,
        elf.SHT_FINI_ARRAY,
        => return 0xf2,

        elf.SHT_DYNAMIC => return 0xf3,

        elf.SHT_RELA => return 0xf,

        elf.SHT_PROGBITS => if (flags & elf.SHF_ALLOC != 0) {
            if (flags & elf.SHF_EXECINSTR != 0) {
                return 0xf1;
            } else if (flags & elf.SHF_WRITE != 0) {
                return if (flags & elf.SHF_TLS != 0) 0xf3 else 0xf5;
            } else if (mem.eql(u8, name, ".interp")) {
                return 1;
            } else {
                return 0xf0;
            }
        } else {
            if (mem.startsWith(u8, name, ".debug")) {
                return 0xf7;
            } else {
                return 0xf8;
            }
        },

        elf.SHT_NOBITS => return if (flags & elf.SHF_TLS != 0) 0xf4 else 0xf6,
        elf.SHT_SYMTAB => return 0xf9,
        elf.SHT_STRTAB => return if (mem.eql(u8, name, ".dynstr")) 4 else 0xfa,
        else => return 0xff,
    }
}

fn sortSections(self: *Elf) !void {
    const Entry = struct {
        shndx: u16,

        pub fn lessThan(elf_file: *Elf, lhs: @This(), rhs: @This()) bool {
            return elf_file.getSectionRank(lhs.shndx) < elf_file.getSectionRank(rhs.shndx);
        }
    };

    const gpa = self.base.allocator;

    var entries = try std.ArrayList(Entry).initCapacity(gpa, self.sections.slice().len);
    defer entries.deinit();
    for (0..self.sections.slice().len) |shndx| {
        entries.appendAssumeCapacity(.{ .shndx = @intCast(u16, shndx) });
    }

    std.sort.sort(Entry, entries.items, self, Entry.lessThan);

    const backlinks = try gpa.alloc(u16, entries.items.len);
    defer gpa.free(backlinks);
    for (entries.items, 0..) |entry, i| {
        backlinks[entry.shndx] = @intCast(u16, i);
    }

    var slice = self.sections.toOwnedSlice();
    defer slice.deinit(gpa);

    try self.sections.ensureTotalCapacity(gpa, slice.len);
    for (entries.items) |sorted| {
        self.sections.appendAssumeCapacity(slice.get(sorted.shndx));
    }

    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.atoms.items) |atom_index| {
            const atom = self.getAtom(atom_index) orelse continue;
            if (!atom.is_alive) continue;
            atom.out_shndx = backlinks[atom.out_shndx];
        }
    }

    for (&[_]*?u16{
        &self.text_sect_index,
        &self.got_sect_index,
        &self.symtab_sect_index,
        &self.strtab_sect_index,
        &self.shstrtab_sect_index,
        &self.interp_sect_index,
        &self.dynamic_sect_index,
        &self.dynsymtab_sect_index,
        &self.dynstrtab_sect_index,
        &self.hash_sect_index,
        &self.plt_sect_index,
        &self.got_plt_sect_index,
        &self.rela_dyn_sect_index,
        &self.rela_plt_sect_index,
    }) |maybe_index| {
        if (maybe_index.*) |*index| {
            index.* = backlinks[index.*];
        }
    }

    if (self.symtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.strtab_sect_index.?;
    }

    if (self.dynamic_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.dynstrtab_sect_index.?;
    }

    if (self.dynsymtab_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.dynstrtab_sect_index.?;
    }

    if (self.hash_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.dynsymtab_sect_index.?;
    }

    if (self.rela_dyn_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.dynsymtab_sect_index.?;
    }

    if (self.rela_plt_sect_index) |index| {
        const shdr = &self.sections.items(.shdr)[index];
        shdr.sh_link = self.dynsymtab_sect_index.?;
        shdr.sh_info = self.plt_sect_index.?;
    }
}

fn allocateAtoms(self: *Elf) void {
    const slice = self.sections.slice();
    for (slice.items(.shdr), 0..) |shdr, i| {
        var atom_index = slice.items(.first_atom)[i] orelse continue;

        while (true) {
            const atom = self.getAtom(atom_index).?;
            assert(atom.is_alive);
            atom.value += shdr.sh_addr;

            if (atom.next) |next| {
                atom_index = next;
            } else break;
        }
    }
}

fn allocateLocals(self: *Elf) void {
    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.getLocals()) |local_index| {
            const local = self.getSymbol(local_index);
            const atom = local.getAtom(self) orelse continue;
            if (!atom.is_alive) continue;
            local.value += atom.value;
            local.shndx = atom.out_shndx;
        }
    }
}

fn allocateGlobals(self: *Elf) void {
    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.getGlobals()) |global_index| {
            const global = self.getSymbol(global_index);
            const atom = global.getAtom(self) orelse continue;
            if (!atom.is_alive) continue;
            if (global.getFile(self).?.object.index != index) continue;
            global.value += atom.value;
            global.shndx = atom.out_shndx;
        }
    }
}

fn allocateSyntheticSymbols(self: *Elf) void {
    // _DYNAMIC
    {
        const shndx = self.dynamic_sect_index orelse self.got_sect_index.?;
        const shdr = self.sections.items(.shdr)[shndx];
        const symbol = self.getSymbol(self.dynamic_index.?);
        symbol.value = shdr.sh_addr;
        symbol.shndx = shndx;
    }

    // __init_array_start, __init_array_end
    if (self.getSectionByName(".init_array")) |shndx| {
        const start_sym = self.getSymbol(self.init_array_start_index.?);
        const end_sym = self.getSymbol(self.init_array_end_index.?);
        const shdr = self.sections.items(.shdr)[shndx];
        start_sym.shndx = shndx;
        start_sym.value = shdr.sh_addr;
        end_sym.shndx = shndx;
        end_sym.value = shdr.sh_addr + shdr.sh_size;
    }

    // __fini_array_start, __fini_array_end
    if (self.getSectionByName(".fini_array")) |shndx| {
        const start_sym = self.getSymbol(self.fini_array_start_index.?);
        const end_sym = self.getSymbol(self.fini_array_end_index.?);
        const shdr = self.sections.items(.shdr)[shndx];
        start_sym.shndx = shndx;
        start_sym.value = shdr.sh_addr;
        end_sym.shndx = shndx;
        end_sym.value = shdr.sh_addr + shdr.sh_size;
    }

    // _GLOBAL_OFFSET_TABLE_
    {
        const shndx = self.got_plt_sect_index orelse self.got_sect_index.?;
        const shdr = self.sections.items(.shdr)[shndx];
        const symbol = self.getSymbol(self.got_index.?);
        symbol.value = shdr.sh_addr;
        symbol.shndx = shndx;
    }
}

const ParseLibsCtx = struct {
    search_dirs: []const []const u8,
    libs: *std.StringArrayHashMap(Zld.SystemLib),
};

fn parsePositional(self: *Elf, arena: Allocator, pos: Zld.LinkObject, ctx: ParseLibsCtx) !void {
    const full_path = full_path: {
        var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
        const path = std.fs.realpath(pos.path, &buffer) catch |err| switch (err) {
            error.FileNotFound => return self.base.fatal("file not found '{s}'", .{pos.path}),
            else => |e| return e,
        };
        break :full_path try arena.dupe(u8, path);
    };

    log.debug("parsing input file path '{s}'", .{full_path});

    if (try self.parseObject(arena, full_path)) return;
    if (try self.parseArchive(arena, full_path)) return;
    if (try self.parseShared(arena, full_path, .{})) return;
    if (try self.parseLdScript(arena, full_path, .{}, ctx)) return;

    self.base.fatal("unknown filetype for positional input file: '{s}'", .{pos.path});
}

fn parseLib(
    self: *Elf,
    arena: Allocator,
    lib_name: []const u8,
    lib_info: Zld.SystemLib,
    ctx: ParseLibsCtx,
) anyerror!void {
    const full_path = (try resolveLib(arena, ctx.search_dirs, lib_name, lib_info)) orelse
        return self.base.fatal("{s}: library not found", .{lib_name});
    const gop = try ctx.libs.getOrPut(full_path);
    if (gop.found_existing) {
        // TODO should we check for differing AS_NEEDED directives and modify parsed DSO?
        return;
    }
    gop.value_ptr.* = lib_info;

    log.debug("parsing lib path '{s}'", .{full_path});

    if (try self.parseArchive(arena, full_path)) return;
    if (try self.parseShared(arena, full_path, lib_info)) return;
    if (try self.parseLdScript(arena, full_path, lib_info, ctx)) return;

    self.base.fatal("unknown filetype for a library: '{s}'", .{full_path});
}

fn parseObject(self: *Elf, arena: Allocator, path: []const u8) !bool {
    const gpa = self.base.allocator;
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const header = try file.reader().readStruct(elf.Elf64_Ehdr);
    try file.seekTo(0);

    if (!Object.isValidHeader(&header)) return false;
    self.validateOrSetCpuArch(path, header.e_machine.toTargetCpuArch().?);

    const data = try file.readToEndAlloc(arena, std.math.maxInt(u32));

    const index = @intCast(u32, try self.files.addOne(gpa));
    self.files.set(index, .{ .object = .{
        .path = path,
        .data = data,
        .index = index,
    } });
    const object = &self.files.items(.data)[index].object;
    try object.parse(self);
    try self.objects.append(gpa, index);

    return true;
}

fn parseArchive(self: *Elf, arena: Allocator, path: []const u8) !bool {
    const gpa = self.base.allocator;
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const magic = try file.reader().readBytesNoEof(Archive.SARMAG);
    try file.seekTo(0);

    if (!Archive.isValidMagic(&magic)) return false;

    const data = try file.readToEndAlloc(arena, std.math.maxInt(u32));
    var archive = Archive{ .path = path, .data = data };
    defer archive.deinit(gpa);
    try archive.parse(self);

    var it = archive.offsets.keyIterator();
    while (it.next()) |offset| {
        var extracted = try archive.getObject(arena, offset.*, self);
        const index = @intCast(File.Index, try self.files.addOne(gpa));
        extracted.index = index;
        self.files.set(index, .{ .object = extracted });
        const object = &self.files.items(.data)[index].object;
        try object.parse(self);
        try self.objects.append(gpa, index);
    }

    return true;
}

fn parseShared(self: *Elf, arena: Allocator, path: []const u8, opts: Zld.SystemLib) !bool {
    const gpa = self.base.allocator;
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const header = try file.reader().readStruct(elf.Elf64_Ehdr);
    try file.seekTo(0);

    if (!SharedObject.isValidHeader(&header)) return false;
    self.validateOrSetCpuArch(path, header.e_machine.toTargetCpuArch().?);

    const data = try file.readToEndAlloc(arena, std.math.maxInt(u32));

    const index = @intCast(File.Index, try self.files.addOne(gpa));
    self.files.set(index, .{ .shared = .{
        .path = path,
        .data = data,
        .index = index,
        .needed = opts.needed,
        .alive = !opts.needed,
    } });
    const dso = &self.files.items(.data)[index].shared;
    try dso.parse(self);
    try self.shared_objects.append(gpa, index);

    return true;
}

fn parseLdScript(self: *Elf, arena: Allocator, path: []const u8, opts: Zld.SystemLib, ctx: ParseLibsCtx) !bool {
    const gpa = self.base.allocator;
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(gpa, std.math.maxInt(u32));
    defer gpa.free(data);

    log.debug("parsing ld linker script path '{s}'", .{path});

    var script = LdScript{};
    defer script.deinit(gpa);
    script.parse(data, self) catch |err| switch (err) {
        error.InvalidScript => return false,
        else => |e| return e,
    };

    if (script.cpu_arch) |cpu_arch| {
        self.validateOrSetCpuArch(path, cpu_arch);
    }

    for (script.libs.keys(), script.libs.values()) |s_name, s_opts| {
        const actual_name = if (mem.startsWith(u8, s_name, "-l")) blk: {
            // I cannot believe we are forced to check this at this stage...
            break :blk mem.trimLeft(u8, s_name["-l".len..], " ");
        } else s_name;
        const static = opts.static or s_opts.static;
        const needed = opts.needed or s_opts.needed;
        try self.parseLib(arena, actual_name, .{
            .static = static,
            .needed = needed,
        }, ctx);
    }

    return true;
}

fn validateOrSetCpuArch(self: *Elf, name: []const u8, cpu_arch: std.Target.Cpu.Arch) void {
    const self_cpu_arch = self.options.cpu_arch orelse blk: {
        self.options.cpu_arch = cpu_arch;
        break :blk self.options.cpu_arch.?;
    };
    if (self_cpu_arch != cpu_arch) {
        self.base.fatal("{s}: invalid architecture '{s}', expected '{s}'", .{
            name,
            @tagName(cpu_arch.toElfMachine()),
            @tagName(self_cpu_arch.toElfMachine()),
        });
    }
}

/// When resolving symbols, we approach the problem similarly to `mold`.
/// 1. Resolve symbols across all objects (including those preemptively extracted archives).
/// 2. Resolve symbols across all shared objects.
/// 3. Mark live objects (see `Elf.markLive`)
/// 4. Reset state of all resolved globals since we will redo this bit on the pruned set.
/// 5. Remove references to dead objects/shared objects
/// 6. Re-run symbol resolution on pruned objects and shared objects sets.
fn resolveSymbols(self: *Elf) !void {
    // Resolve symbols on the set of all objects and shared objects (even if some are unneeded).
    for (self.objects.items) |index| self.getFile(index).?.resolveSymbols(self);
    for (self.shared_objects.items) |index| self.getFile(index).?.resolveSymbols(self);

    // Mark live objects.
    self.markLive();

    // Reset state of all globals after marking live objects.
    for (self.objects.items) |index| self.getFile(index).?.resetGlobals(self);
    for (self.shared_objects.items) |index| self.getFile(index).?.resetGlobals(self);

    // Prune dead objects and shared objects.
    var i: usize = 0;
    while (i < self.objects.items.len) {
        const index = self.objects.items[i];
        if (!self.getFile(index).?.isAlive()) {
            _ = self.objects.swapRemove(i);
        } else i += 1;
    }

    i = 0;
    while (i < self.shared_objects.items.len) {
        const index = self.shared_objects.items[i];
        if (!self.getFile(index).?.isAlive()) {
            _ = self.shared_objects.swapRemove(i);
        } else i += 1;
    }

    // Re-resolve the symbols.
    for (self.objects.items) |index| self.getFile(index).?.resolveSymbols(self);
    for (self.shared_objects.items) |index| self.getFile(index).?.resolveSymbols(self);
}

/// Traverses all objects and shared objects marking any object referenced by
/// a live object/shared object as alive itself.
/// This routine will prune unneeded objects extracted from archives and
/// unneeded shared objects.
fn markLive(self: *Elf) void {
    for (self.objects.items) |index| {
        const file = self.getFile(index).?;
        if (file.isAlive()) file.markLive(self);
    }
    for (self.shared_objects.items) |index| {
        const file = self.getFile(index).?;
        if (file.isAlive()) file.markLive(self);
    }
}

fn markImportsAndExports(self: *Elf) !void {
    for (self.shared_objects.items) |index| {
        for (self.getFile(index).?.shared.getGlobals()) |global_index| {
            const global = self.getSymbol(global_index);
            if (global.getFile(self)) |file| {
                if (file != .shared) global.@"export" = true;
            }
        }
    }

    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.getGlobals()) |global_index| {
            const global = self.getSymbol(global_index);
            if (global.getFile(self)) |file| {
                if (file == .shared and !global.isAbs(self)) {
                    global.import = true;
                }
            }
        }
    }
}

fn resolveSyntheticSymbols(self: *Elf) !void {
    const internal_index = self.internal_object_index orelse return;
    const internal = self.getFile(internal_index).?.internal;
    self.dynamic_index = try internal.addSyntheticGlobal("_DYNAMIC", self);
    self.init_array_start_index = try internal.addSyntheticGlobal("__init_array_start", self);
    self.init_array_end_index = try internal.addSyntheticGlobal("__init_array_end", self);
    self.fini_array_start_index = try internal.addSyntheticGlobal("__fini_array_start", self);
    self.fini_array_end_index = try internal.addSyntheticGlobal("__fini_array_end", self);
    self.got_index = try internal.addSyntheticGlobal("_GLOBAL_OFFSET_TABLE_", self);
    internal.resolveSymbols(self);
}

fn checkDuplicates(self: *Elf) void {
    for (self.objects.items) |index| self.getFile(index).?.object.checkDuplicates(self);
}

fn checkUndefined(self: *Elf) void {
    for (self.objects.items) |index| self.getFile(index).?.object.checkUndefined(self);
}

fn claimUnresolved(self: *Elf) void {
    for (self.objects.items) |index| {
        const object = self.getFile(index).?.object;
        const first_global = object.first_global orelse return;
        for (object.getGlobals(), 0..) |global_index, i| {
            const sym_idx = @intCast(u32, first_global + i);
            const sym = object.symtab[sym_idx];
            if (sym.st_shndx != elf.SHN_UNDEF) continue;

            const global = self.getSymbol(global_index);
            if (global.getFile(self)) |_| {
                if (global.getSourceSymbol(self).st_shndx != elf.SHN_UNDEF) continue;
            }

            global.* = .{
                .value = 0,
                .name = global.name,
                .atom = 0,
                .sym_idx = sym_idx,
                .file = object.index,
            };
        }
    }
}

fn scanRelocs(self: *Elf) !void {
    for (self.objects.items) |index| {
        for (self.getFile(index).?.object.atoms.items) |atom_index| {
            const atom = self.getAtom(atom_index) orelse continue;
            if (!atom.is_alive) continue;
            try atom.scanRelocs(self);
        }
    }

    for (self.symbols.items, 0..) |*symbol, i| {
        const index = @intCast(u32, i);
        if (symbol.import) {
            try self.dynsym.addSymbol(index, self);
        }
        if (symbol.flags.got) {
            log.debug("'{s}' needs GOT", .{symbol.getName(self)});
            try self.got.addSymbol(index, self);
            if (symbol.import) self.got.needs_rela = true;
        }
        if (symbol.flags.plt) {
            log.debug("'{s}' needs PLT", .{symbol.getName(self)});
            try self.plt.addSymbol(index, self);
        }
    }
}

fn setSymtab(self: *Elf) !void {
    if (self.symtab_sect_index == null) return;
    try self.symtab.set(self);
}

fn setDynamic(self: *Elf) !void {
    if (self.dynamic_sect_index == null) return;

    try self.dynamic.setRpath(self.options.rpath_list, self);

    for (self.shared_objects.items) |index| {
        const shared = self.getFile(index).?.shared;
        if (!shared.alive) continue;
        try self.dynamic.addNeeded(shared, self);
    }
}

fn setHash(self: *Elf) !void {
    if (self.hash_sect_index == null) return;
    try self.hash.generate(self);
}

fn writeAtoms(self: *Elf) !void {
    const slice = self.sections.slice();
    for (slice.items(.first_atom), 0..) |first_atom, i| {
        var atom_index = first_atom orelse continue;
        const shndx = @intCast(u16, i);
        const shdr = slice.items(.shdr)[shndx];

        if (shdr.sh_type == elf.SHT_NOBITS) continue;

        log.debug("writing atoms in '{s}' section", .{self.shstrtab.getAssumeExists(shdr.sh_name)});

        var buffer = try self.base.allocator.alloc(u8, shdr.sh_size);
        defer self.base.allocator.free(buffer);
        @memset(buffer, 0);

        var stream = std.io.fixedBufferStream(buffer);

        while (true) {
            const atom = self.getAtom(atom_index).?;
            assert(atom.is_alive);
            const off = atom.value - shdr.sh_addr;
            log.debug("writing ATOM(%{d},'{s}') at offset 0x{x}", .{
                atom_index,
                atom.getName(self),
                shdr.sh_offset + off,
            });
            try stream.seekTo(off);
            try atom.resolveRelocs(self, stream.writer());

            if (atom.next) |next| {
                atom_index = next;
            } else break;
        }

        try self.base.file.pwriteAll(buffer, shdr.sh_offset);
    }
}

fn writeSyntheticSections(self: *Elf) !void {
    const gpa = self.base.allocator;
    if (self.interp_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try gpa.alloc(u8, shdr.sh_size);
        defer gpa.free(buffer);
        const dylinker = self.options.dynamic_linker.?;
        @memcpy(buffer[0..dylinker.len], dylinker);
        buffer[dylinker.len] = 0;
        try self.base.file.pwriteAll(buffer, shdr.sh_offset);
    }

    if (self.hash_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        try self.base.file.pwriteAll(self.hash.buffer.items, shdr.sh_offset);
    }

    if (self.dynamic_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.dynamic.size(self));
        defer buffer.deinit();
        try self.dynamic.write(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.dynsymtab_sect_index) |shndx| {
        const shdr = &self.sections.items(.shdr)[shndx];
        shdr.sh_info = 1;
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.dynsym.size());
        defer buffer.deinit();
        try self.dynsym.write(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.dynstrtab_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        try self.base.file.pwriteAll(self.dynstrtab.buffer.items, shdr.sh_offset);
    }

    if (self.got_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.got.sizeGot());
        defer buffer.deinit();
        try self.got.writeGot(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.rela_dyn_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.got.sizeRela(self));
        defer buffer.deinit();
        try self.got.writeRela(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.plt_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.plt.sizePlt());
        defer buffer.deinit();
        try self.plt.writePlt(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.got_plt_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.plt.sizeGotPlt());
        defer buffer.deinit();
        try self.plt.writeGotPlt(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.rela_plt_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.plt.sizeRela());
        defer buffer.deinit();
        try self.plt.writeRela(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.symtab_sect_index) |shndx| {
        const shdr = &self.sections.items(.shdr)[shndx];
        shdr.sh_info = self.symtab.globalIndex();
        var buffer = try std.ArrayList(u8).initCapacity(gpa, self.symtab.size());
        defer buffer.deinit();
        try self.symtab.write(self, buffer.writer());
        try self.base.file.pwriteAll(buffer.items, shdr.sh_offset);
    }

    if (self.strtab_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        try self.base.file.pwriteAll(self.strtab.buffer.items, shdr.sh_offset);
    }

    if (self.shstrtab_sect_index) |shndx| {
        const shdr = self.sections.items(.shdr)[shndx];
        try self.base.file.pwriteAll(self.shstrtab.buffer.items, shdr.sh_offset);
    }
}

fn writePhdrs(self: *Elf) !void {
    const phoff = @sizeOf(elf.Elf64_Ehdr);
    const phdrs_size = self.phdrs.items.len * @sizeOf(elf.Elf64_Phdr);
    log.debug("writing program headers from 0x{x} to 0x{x}", .{ phoff, phoff + phdrs_size });
    try self.base.file.pwriteAll(mem.sliceAsBytes(self.phdrs.items), phoff);
}

fn writeShdrs(self: *Elf) !void {
    const size = self.sections.items(.shdr).len * @sizeOf(elf.Elf64_Shdr);
    log.debug("writing section headers from 0x{x} to 0x{x}", .{ self.shoff, self.shoff + size });
    try self.base.file.pwriteAll(mem.sliceAsBytes(self.sections.items(.shdr)), self.shoff);
}

fn writeHeader(self: *Elf) !void {
    var header = elf.Elf64_Ehdr{
        .e_ident = undefined,
        .e_type = switch (self.options.output_mode) {
            .exe => elf.ET.EXEC,
            .lib => elf.ET.DYN,
        },
        .e_machine = self.options.cpu_arch.?.toElfMachine(),
        .e_version = 1,
        .e_entry = if (self.entry_index) |index| self.getSymbol(index).value else 0,
        .e_phoff = @sizeOf(elf.Elf64_Ehdr),
        .e_shoff = self.shoff,
        .e_flags = 0,
        .e_ehsize = @sizeOf(elf.Elf64_Ehdr),
        .e_phentsize = @sizeOf(elf.Elf64_Phdr),
        .e_phnum = @intCast(u16, self.phdrs.items.len),
        .e_shentsize = @sizeOf(elf.Elf64_Shdr),
        .e_shnum = @intCast(u16, self.sections.items(.shdr).len),
        .e_shstrndx = self.shstrtab_sect_index.?,
    };
    // Magic
    mem.copy(u8, header.e_ident[0..4], "\x7fELF");
    // Class
    header.e_ident[4] = elf.ELFCLASS64;
    // Endianness
    header.e_ident[5] = elf.ELFDATA2LSB;
    // ELF version
    header.e_ident[6] = 1;
    // OS ABI, often set to 0 regardless of target platform
    // ABI Version, possibly used by glibc but not by static executables
    // padding
    @memset(header.e_ident[7..][0..9], 0);
    log.debug("writing ELF header {} at 0x{x}", .{ header, 0 });
    try self.base.file.pwriteAll(mem.asBytes(&header), 0);
}

pub const AddSectionOpts = struct {
    name: [:0]const u8,
    type: u32 = elf.SHT_NULL,
    flags: u64 = 0,
    link: u32 = 0,
    info: u32 = 0,
    addralign: u64 = 0,
    entsize: u64 = 0,
};

pub fn addSection(self: *Elf, opts: AddSectionOpts) !u16 {
    const gpa = self.base.allocator;
    const index = @intCast(u16, try self.sections.addOne(gpa));
    self.sections.set(index, .{
        .shdr = .{
            .sh_name = try self.shstrtab.insert(gpa, opts.name),
            .sh_type = opts.type,
            .sh_flags = opts.flags,
            .sh_addr = 0,
            .sh_offset = 0,
            .sh_size = 0,
            .sh_link = 0,
            .sh_info = opts.info,
            .sh_addralign = opts.addralign,
            .sh_entsize = opts.entsize,
        },
        .first_atom = null,
        .last_atom = null,
    });
    return index;
}

pub fn getSectionByName(self: *Elf, name: [:0]const u8) ?u16 {
    for (self.sections.items(.shdr), 0..) |shdr, i| {
        const this_name = self.shstrtab.getAssumeExists(shdr.sh_name);
        if (mem.eql(u8, this_name, name)) return @intCast(u16, i);
    } else return null;
}

fn addPhdr(self: *Elf, opts: struct {
    type: u32 = 0,
    flags: u32 = 0,
    @"align": u64 = 0,
    offset: u64 = 0,
    addr: u64 = 0,
    filesz: u64 = 0,
    memsz: u64 = 0,
}) !u16 {
    const index = @intCast(u16, self.phdrs.items.len);
    try self.phdrs.append(self.base.allocator, .{
        .p_type = opts.type,
        .p_flags = opts.flags,
        .p_offset = opts.offset,
        .p_vaddr = opts.addr,
        .p_paddr = opts.addr,
        .p_filesz = opts.filesz,
        .p_memsz = opts.memsz,
        .p_align = opts.@"align",
    });
    return index;
}

pub fn getFile(self: *Elf, index: File.Index) ?File {
    const tag = self.files.items(.tags)[index];
    return switch (tag) {
        .null => null,
        .internal => .{ .internal = &self.files.items(.data)[index].internal },
        .object => .{ .object = &self.files.items(.data)[index].object },
        .shared => .{ .shared = &self.files.items(.data)[index].shared },
    };
}

pub fn addAtom(self: *Elf) !Atom.Index {
    const index = @intCast(u32, self.atoms.items.len);
    const atom = try self.atoms.addOne(self.base.allocator);
    atom.* = .{};
    return index;
}

pub fn getAtom(self: Elf, atom_index: Atom.Index) ?*Atom {
    if (atom_index == 0) return null;
    assert(atom_index < self.atoms.items.len);
    return &self.atoms.items[atom_index];
}

pub fn addSymbol(self: *Elf) !u32 {
    const index = @intCast(u32, self.symbols.items.len);
    const symbol = try self.symbols.addOne(self.base.allocator);
    symbol.* = .{};
    return index;
}

pub fn getSymbol(self: *Elf, index: u32) *Symbol {
    assert(index < self.symbols.items.len);
    return &self.symbols.items[index];
}

pub fn addSymbolExtra(self: *Elf, extra: Symbol.Extra) !u32 {
    const fields = @typeInfo(Symbol.Extra).Struct.fields;
    try self.symbols_extra.ensureUnusedCapacity(self.base.allocator, fields.len);
    return self.addSymbolExtraAssumeCapacity(extra);
}

pub fn addSymbolExtraAssumeCapacity(self: *Elf, extra: Symbol.Extra) u32 {
    const index = @intCast(u32, self.symbols_extra.items.len);
    const fields = @typeInfo(Symbol.Extra).Struct.fields;
    inline for (fields) |field| {
        self.symbols_extra.appendAssumeCapacity(switch (field.type) {
            u32 => @field(extra, field.name),
            else => @compileError("bad field type"),
        });
    }
    return index;
}

pub fn getSymbolExtra(self: *Elf, index: u32) ?Symbol.Extra {
    if (index == 0) return null;
    const fields = @typeInfo(Symbol.Extra).Struct.fields;
    var i: usize = index;
    var result: Symbol.Extra = undefined;
    inline for (fields) |field| {
        @field(result, field.name) = switch (field.type) {
            u32 => self.symbols_extra.items[i],
            else => @compileError("bad field type"),
        };
        i += 1;
    }
    return result;
}

pub fn setSymbolExtra(self: *Elf, index: u32, extra: Symbol.Extra) void {
    assert(index > 0);
    const fields = @typeInfo(Symbol.Extra).Struct.fields;
    inline for (fields, 0..) |field, i| {
        self.symbols_extra.items[index + i] = switch (field.type) {
            u32 => @field(extra, field.name),
            else => @compileError("bad field type"),
        };
    }
}

const GetOrCreateGlobalResult = struct {
    found_existing: bool,
    index: u32,
};

pub fn getOrCreateGlobal(self: *Elf, name: [:0]const u8) !GetOrCreateGlobalResult {
    const gpa = self.base.allocator;
    const gop = try self.globals.getOrPut(gpa, name);
    if (!gop.found_existing) {
        const index = try self.addSymbol();
        const global = self.getSymbol(index);
        global.name = try self.string_intern.insert(gpa, name);
        gop.value_ptr.* = index;
    }
    return .{
        .found_existing = gop.found_existing,
        .index = gop.value_ptr.*,
    };
}

pub fn getGotAddress(self: *Elf) u64 {
    const shndx = self.got_sect_index orelse return 0;
    const shdr = self.sections.items(.shdr)[shndx];
    return shdr.sh_addr;
}

pub inline fn getGotEntryAddress(self: *Elf, index: u32) u64 {
    return self.getGotAddress() + index * @sizeOf(u64);
}

pub fn getPltAddress(self: *Elf) u64 {
    const shndx = self.plt_sect_index orelse return 0;
    const shdr = self.sections.items(.shdr)[shndx];
    return shdr.sh_addr;
}

pub inline fn getPltEntryAddress(self: *Elf, index: u32) u64 {
    return self.getPltAddress() + PltSection.plt_preamble_size + index * 16;
}

pub fn getTpAddress(self: *Elf) u64 {
    const index = self.tls_phdr_index orelse return 0;
    const phdr = self.phdrs.items[index];
    return mem.alignForwardGeneric(u64, phdr.p_vaddr + phdr.p_memsz, phdr.p_align);
}

pub fn getDtpAddress(self: *Elf) u64 {
    const index = self.tls_phdr_index orelse return 0;
    const phdr = self.phdrs.items[index];
    return phdr.p_vaddr;
}

fn fmtSections(self: *Elf) std.fmt.Formatter(formatSections) {
    return .{ .data = self };
}

fn formatSections(
    self: *Elf,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = unused_fmt_string;
    for (self.sections.items(.shdr), 0..) |shdr, i| {
        try writer.print("sect({d}) : {s} : @{x} ({x}) : align({x}) : size({x})\n", .{
            i,                 self.shstrtab.getAssumeExists(shdr.sh_name), shdr.sh_offset, shdr.sh_addr,
            shdr.sh_addralign, shdr.sh_size,
        });
    }
}

fn fmtPhdrs(self: *Elf) std.fmt.Formatter(formatPhdrs) {
    return .{ .data = self };
}

fn formatPhdrs(
    self: *Elf,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = unused_fmt_string;
    for (self.phdrs.items, 0..) |phdr, i| {
        const write = phdr.p_flags & elf.PF_W != 0;
        const read = phdr.p_flags & elf.PF_R != 0;
        const exec = phdr.p_flags & elf.PF_X != 0;
        var flags: [3]u8 = [_]u8{'_'} ** 3;
        if (exec) flags[0] = 'X';
        if (write) flags[1] = 'W';
        if (read) flags[2] = 'R';
        try writer.print("phdr({d}) : {s} : @{x} ({x}) : align({x}) : filesz({x}) : memsz({x})\n", .{
            i, flags, phdr.p_offset, phdr.p_vaddr, phdr.p_align, phdr.p_filesz, phdr.p_memsz,
        });
    }
}

fn dumpState(self: *Elf) std.fmt.Formatter(fmtDumpState) {
    return .{ .data = self };
}

fn fmtDumpState(
    self: *Elf,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = unused_fmt_string;
    for (self.objects.items) |index| {
        const object = self.getFile(index).?.object;
        try writer.print("object({d}) : {}", .{ index, object.fmtPath() });
        if (!object.alive) try writer.writeAll(" : [*]");
        try writer.writeByte('\n');
        try writer.print("{}{}\n", .{ object.fmtAtoms(self), object.fmtSymtab(self) });
    }
    for (self.shared_objects.items) |index| {
        const shared = self.getFile(index).?.shared;
        try writer.print("shared({d}) : ", .{index});
        try writer.print("{s}", .{shared.path});
        try writer.print(" : needed({})", .{shared.needed});
        if (!shared.alive) try writer.writeAll(" : [*]");
        try writer.writeByte('\n');
        try writer.print("{}\n", .{shared.fmtSymtab(self)});
    }
    if (self.internal_object_index) |index| {
        const internal = self.getFile(index).?.internal;
        try writer.print("internal({d}) : internal\n", .{index});
        try writer.print("{}\n", .{internal.fmtSymtab(self)});
    }
    try writer.writeAll("GOT\n");
    for (self.got.symbols.items, 0..) |sym_index, i| {
        try writer.print("  {d} => {d} '{s}'\n", .{ i, sym_index, self.getSymbol(sym_index).getName(self) });
    }
    try writer.writeByte('\n');
    try writer.writeAll("PLT\n");
    for (self.plt.symbols.items, 0..) |sym_index, i| {
        try writer.print("  {d} => {d} '{s}'\n", .{ i, sym_index, self.getSymbol(sym_index).getName(self) });
    }
    try writer.writeByte('\n');
    try writer.writeAll("Output sections\n");
    try writer.print("{}\n", .{self.fmtSections()});
    try writer.writeAll("Output phdrs\n");
    try writer.print("{}\n", .{self.fmtPhdrs()});
}

const Section = struct {
    shdr: elf.Elf64_Shdr,
    first_atom: ?Atom.Index,
    last_atom: ?Atom.Index,
};

const default_base_addr: u64 = 0x200000;
const default_page_size: u64 = 0x1000;

pub const null_sym = elf.Elf64_Sym{
    .st_name = 0,
    .st_info = 0,
    .st_other = 0,
    .st_shndx = 0,
    .st_value = 0,
    .st_size = 0,
};

pub const base_tag = Zld.Tag.elf;

const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const assert = std.debug.assert;
const elf = std.elf;
const fs = std.fs;
const gc = @import("Elf/gc.zig");
const log = std.log.scoped(.elf);
const state_log = std.log.scoped(.state);
const synthetic = @import("Elf/synthetic.zig");
const math = std.math;
const mem = std.mem;

const Allocator = mem.Allocator;
const Archive = @import("Elf/Archive.zig");
const Atom = @import("Elf/Atom.zig");
const DynamicSection = synthetic.DynamicSection;
const DynsymSection = synthetic.DynsymSection;
const Elf = @This();
const File = @import("Elf/file.zig").File;
const GotSection = synthetic.GotSection;
const HashSection = synthetic.HashSection;
const InternalObject = @import("Elf/InternalObject.zig");
const LdScript = @import("Elf/LdScript.zig");
const Object = @import("Elf/Object.zig");
pub const Options = @import("Elf/Options.zig");
const PltSection = synthetic.PltSection;
const SharedObject = @import("Elf/SharedObject.zig");
const StringTable = @import("strtab.zig").StringTable;
const Symbol = @import("Elf/Symbol.zig");
const SymtabSection = synthetic.SymtabSection;
const ThreadPool = @import("ThreadPool.zig");
const Zld = @import("Zld.zig");
