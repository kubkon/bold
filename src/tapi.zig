const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const log = std.log.scoped(.tapi);

const Allocator = mem.Allocator;
const Yaml = @import("yaml").Yaml;

const VersionField = union(enum) {
    string: []const u8,
    float: f64,
    int: u64,
};

pub const TbdV3 = struct {
    archs: []const []const u8,
    uuids: []const []const u8,
    platform: []const u8,
    install_name: []const u8,
    current_version: ?VersionField,
    compatibility_version: ?VersionField,
    objc_constraint: ?[]const u8,
    parent_umbrella: ?[]const u8,
    exports: ?[]const struct {
        archs: []const []const u8,
        allowable_clients: ?[]const []const u8,
        re_exports: ?[]const []const u8,
        symbols: ?[]const []const u8,
        weak_symbols: ?[]const []const u8,
        objc_classes: ?[]const []const u8,
        objc_ivars: ?[]const []const u8,
        objc_eh_types: ?[]const []const u8,
    },
};

pub const TbdV4 = struct {
    tbd_version: u3,
    targets: []const []const u8,
    uuids: ?[]const struct {
        target: []const u8,
        value: []const u8,
    },
    install_name: []const u8,
    current_version: ?VersionField,
    compatibility_version: ?VersionField,
    reexported_libraries: ?[]const struct {
        targets: []const []const u8,
        libraries: []const []const u8,
    },
    parent_umbrella: ?[]const struct {
        targets: []const []const u8,
        umbrella: []const u8,
    },
    exports: ?[]const struct {
        targets: []const []const u8,
        symbols: ?[]const []const u8,
        weak_symbols: ?[]const []const u8,
        objc_classes: ?[]const []const u8,
        objc_ivars: ?[]const []const u8,
        objc_eh_types: ?[]const []const u8,
    },
    reexports: ?[]const struct {
        targets: []const []const u8,
        symbols: ?[]const []const u8,
        weak_symbols: ?[]const []const u8,
        objc_classes: ?[]const []const u8,
        objc_ivars: ?[]const []const u8,
        objc_eh_types: ?[]const []const u8,
    },
    allowable_clients: ?[]const struct {
        targets: []const []const u8,
        clients: []const []const u8,
    },
    objc_classes: ?[]const []const u8,
    objc_ivars: ?[]const []const u8,
    objc_eh_types: ?[]const []const u8,
};

pub const LibStub = struct {
    arena: std.heap.ArenaAllocator,
    inner: union(enum) {
        v3_list: []const TbdV3,
        v3: TbdV3,
        v4_list: []const TbdV4,
        v4: TbdV4,
    },

    pub fn loadFromFile(gpa: Allocator, file: fs.File) !LibStub {
        const filesize = blk: {
            const stat = file.stat() catch break :blk std.math.maxInt(u32);
            break :blk @min(stat.size, std.math.maxInt(u32));
        };
        const source = try gpa.alloc(u8, filesize);
        defer gpa.free(source);
        const amt = try file.preadAll(source, 0);
        if (amt != filesize) return error.InputOutput;

        var yaml: Yaml = .{ .source = source };
        defer yaml.deinit(gpa);
        try yaml.load(gpa);

        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();

        var lib_stub = LibStub{
            .arena = arena,
            .inner = undefined,
        };

        // TODO revisit this logic in the hope of simplifying it.
        blk: {
            err: {
                log.debug("trying to parse as []TbdV4", .{});
                const inner = yaml.parse(arena.allocator(), []TbdV4) catch break :err;
                lib_stub.inner = .{ .v4_list = inner };
                break :blk;
            }

            err: {
                log.debug("trying to parse as TbdV4", .{});
                const inner = yaml.parse(arena.allocator(), TbdV4) catch break :err;
                lib_stub.inner = .{ .v4 = inner };
                break :blk;
            }

            err: {
                log.debug("trying to parse as []TbdV3", .{});
                const inner = yaml.parse(arena.allocator(), []TbdV3) catch break :err;
                lib_stub.inner = .{ .v3_list = inner };
                break :blk;
            }

            err: {
                log.debug("trying to parse as TbdV3", .{});
                const inner = yaml.parse(arena.allocator(), TbdV3) catch break :err;
                lib_stub.inner = .{ .v3 = inner };
                break :blk;
            }

            return error.NotLibStub;
        }

        return lib_stub;
    }

    pub fn deinit(self: *LibStub) void {
        self.arena.deinit();
    }
};
