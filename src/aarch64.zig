/// General purpose registers in the AArch64 instruction set
pub const Register = enum(u7) {
    // zig fmt: off
    // 64-bit registers
    x0, x1, x2, x3, x4, x5, x6, x7,
    x8, x9, x10, x11, x12, x13, x14, x15,
    x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28, x29, x30, xzr,

    // 32-bit registers
    w0, w1, w2, w3, w4, w5, w6, w7,
    w8, w9, w10, w11, w12, w13, w14, w15,
    w16, w17, w18, w19, w20, w21, w22, w23,
    w24, w25, w26, w27, w28, w29, w30, wzr,

    // Stack pointer
    sp, wsp,
// zig fmt: on

    pub fn id(self: Register) u6 {
        return switch (@intFromEnum(self)) {
            0...63 => return @as(u6, @as(u5, @truncate(@intFromEnum(self)))),
            64...65 => 32,
            else => unreachable,
        };
    }

    pub fn enc(self: Register) u5 {
        return switch (@intFromEnum(self)) {
            0...63 => return @as(u5, @truncate(@intFromEnum(self))),
            64...65 => 31,
            else => unreachable,
        };
    }

    /// Returns the bit-width of the register.
    pub fn size(self: Register) u7 {
        return switch (@intFromEnum(self)) {
            0...31 => 64,
            32...63 => 32,
            64 => 64,
            65 => 32,
            else => unreachable,
        };
    }

    /// Convert from any register to its 64 bit alias.
    pub fn to64(self: Register) Register {
        return switch (@intFromEnum(self)) {
            0...31 => self,
            32...63 => @as(Register, @enumFromInt(@intFromEnum(self) - 32)),
            64 => .sp,
            65 => .sp,
            else => unreachable,
        };
    }

    /// Convert from any register to its 32 bit alias.
    pub fn to32(self: Register) Register {
        return switch (@intFromEnum(self)) {
            0...31 => @as(Register, @enumFromInt(@intFromEnum(self) + 32)),
            32...63 => self,
            64 => .wsp,
            65 => .wsp,
            else => unreachable,
        };
    }

    pub fn dwarfLocOp(self: Register) u8 {
        return @as(u8, self.enc()) + DW.OP.reg0;
    }
};

test "Register.enc" {
    try testing.expectEqual(@as(u5, 0), Register.x0.enc());
    try testing.expectEqual(@as(u5, 0), Register.w0.enc());

    try testing.expectEqual(@as(u5, 31), Register.xzr.enc());
    try testing.expectEqual(@as(u5, 31), Register.wzr.enc());

    try testing.expectEqual(@as(u5, 31), Register.sp.enc());
    try testing.expectEqual(@as(u5, 31), Register.sp.enc());
}

test "Register.size" {
    try testing.expectEqual(@as(u7, 64), Register.x19.size());
    try testing.expectEqual(@as(u7, 32), Register.w3.size());
}

test "Register.to64/to32" {
    try testing.expectEqual(Register.x0, Register.w0.to64());
    try testing.expectEqual(Register.x0, Register.x0.to64());

    try testing.expectEqual(Register.w3, Register.w3.to32());
    try testing.expectEqual(Register.w3, Register.x3.to32());
}

/// Scalar floating point registers in the aarch64 instruction set
pub const FloatingPointRegister = enum(u8) {
    // zig fmt: off
    // 128-bit registers
    q0, q1, q2, q3, q4, q5, q6, q7,
    q8, q9, q10, q11, q12, q13, q14, q15,
    q16, q17, q18, q19, q20, q21, q22, q23,
    q24, q25, q26, q27, q28, q29, q30, q31,

    // 64-bit registers
    d0, d1, d2, d3, d4, d5, d6, d7,
    d8, d9, d10, d11, d12, d13, d14, d15,
    d16, d17, d18, d19, d20, d21, d22, d23,
    d24, d25, d26, d27, d28, d29, d30, d31,

    // 32-bit registers
    s0, s1, s2, s3, s4, s5, s6, s7,
    s8, s9, s10, s11, s12, s13, s14, s15,
    s16, s17, s18, s19, s20, s21, s22, s23,
    s24, s25, s26, s27, s28, s29, s30, s31,

    // 16-bit registers
    h0, h1, h2, h3, h4, h5, h6, h7,
    h8, h9, h10, h11, h12, h13, h14, h15,
    h16, h17, h18, h19, h20, h21, h22, h23,
    h24, h25, h26, h27, h28, h29, h30, h31,

    // 8-bit registers
    b0, b1, b2, b3, b4, b5, b6, b7,
    b8, b9, b10, b11, b12, b13, b14, b15,
    b16, b17, b18, b19, b20, b21, b22, b23,
    b24, b25, b26, b27, b28, b29, b30, b31,

// zig fmt: on

    pub fn id(self: FloatingPointRegister) u5 {
        return @as(u5, @truncate(@intFromEnum(self)));
    }

    /// Returns the bit-width of the register.
    pub fn size(self: FloatingPointRegister) u8 {
        return switch (@intFromEnum(self)) {
            0...31 => 128,
            32...63 => 64,
            64...95 => 32,
            96...127 => 16,
            128...159 => 8,
            else => unreachable,
        };
    }

    /// Convert from any register to its 128 bit alias.
    pub fn to128(self: FloatingPointRegister) FloatingPointRegister {
        return @as(FloatingPointRegister, @enumFromInt(self.id()));
    }

    /// Convert from any register to its 64 bit alias.
    pub fn to64(self: FloatingPointRegister) FloatingPointRegister {
        return @as(FloatingPointRegister, @enumFromInt(@as(u8, self.id()) + 32));
    }

    /// Convert from any register to its 32 bit alias.
    pub fn to32(self: FloatingPointRegister) FloatingPointRegister {
        return @as(FloatingPointRegister, @enumFromInt(@as(u8, self.id()) + 64));
    }

    /// Convert from any register to its 16 bit alias.
    pub fn to16(self: FloatingPointRegister) FloatingPointRegister {
        return @as(FloatingPointRegister, @enumFromInt(@as(u8, self.id()) + 96));
    }

    /// Convert from any register to its 8 bit alias.
    pub fn to8(self: FloatingPointRegister) FloatingPointRegister {
        return @as(FloatingPointRegister, @enumFromInt(@as(u8, self.id()) + 128));
    }
};

test "FloatingPointRegister.id" {
    try testing.expectEqual(@as(u5, 0), FloatingPointRegister.b0.id());
    try testing.expectEqual(@as(u5, 0), FloatingPointRegister.h0.id());
    try testing.expectEqual(@as(u5, 0), FloatingPointRegister.s0.id());
    try testing.expectEqual(@as(u5, 0), FloatingPointRegister.d0.id());
    try testing.expectEqual(@as(u5, 0), FloatingPointRegister.q0.id());

    try testing.expectEqual(@as(u5, 2), FloatingPointRegister.q2.id());
    try testing.expectEqual(@as(u5, 31), FloatingPointRegister.d31.id());
}

test "FloatingPointRegister.size" {
    try testing.expectEqual(@as(u8, 128), FloatingPointRegister.q1.size());
    try testing.expectEqual(@as(u8, 64), FloatingPointRegister.d2.size());
    try testing.expectEqual(@as(u8, 32), FloatingPointRegister.s3.size());
    try testing.expectEqual(@as(u8, 16), FloatingPointRegister.h4.size());
    try testing.expectEqual(@as(u8, 8), FloatingPointRegister.b5.size());
}

test "FloatingPointRegister.toX" {
    try testing.expectEqual(FloatingPointRegister.q1, FloatingPointRegister.q1.to128());
    try testing.expectEqual(FloatingPointRegister.q2, FloatingPointRegister.b2.to128());
    try testing.expectEqual(FloatingPointRegister.q3, FloatingPointRegister.h3.to128());

    try testing.expectEqual(FloatingPointRegister.d0, FloatingPointRegister.q0.to64());
    try testing.expectEqual(FloatingPointRegister.s1, FloatingPointRegister.d1.to32());
    try testing.expectEqual(FloatingPointRegister.h2, FloatingPointRegister.s2.to16());
    try testing.expectEqual(FloatingPointRegister.b3, FloatingPointRegister.h3.to8());
}

/// Represents an instruction in the AArch64 instruction set
pub const Instruction = union(enum) {
    move_wide_immediate: packed struct {
        rd: u5,
        imm16: u16,
        hw: u2,
        fixed: u6 = 0b100101,
        opc: u2,
        sf: u1,
    },
    pc_relative_address: packed struct {
        rd: u5,
        immhi: u19,
        fixed: u5 = 0b10000,
        immlo: u2,
        op: u1,
    },
    load_store_register: packed struct {
        rt: u5,
        rn: u5,
        offset: u12,
        opc: u2,
        op1: u2,
        v: u1,
        fixed: u3 = 0b111,
        size: u2,
    },
    load_store_register_pair: packed struct {
        rt1: u5,
        rn: u5,
        rt2: u5,
        imm7: u7,
        load: u1,
        encoding: u2,
        fixed: u5 = 0b101_0_0,
        opc: u2,
    },
    load_literal: packed struct {
        rt: u5,
        imm19: u19,
        fixed: u6 = 0b011_0_00,
        opc: u2,
    },
    exception_generation: packed struct {
        ll: u2,
        op2: u3,
        imm16: u16,
        opc: u3,
        fixed: u8 = 0b1101_0100,
    },
    unconditional_branch_register: packed struct {
        op4: u5,
        rn: u5,
        op3: u6,
        op2: u5,
        opc: u4,
        fixed: u7 = 0b1101_011,
    },
    unconditional_branch_immediate: packed struct {
        imm26: u26,
        fixed: u5 = 0b00101,
        op: u1,
    },
    no_operation: packed struct {
        fixed: u32 = 0b1101010100_0_00_011_0010_0000_000_11111,
    },
    logical_shifted_register: packed struct {
        rd: u5,
        rn: u5,
        imm6: u6,
        rm: u5,
        n: u1,
        shift: u2,
        fixed: u5 = 0b01010,
        opc: u2,
        sf: u1,
    },
    add_subtract_immediate: packed struct {
        rd: u5,
        rn: u5,
        imm12: u12,
        sh: u1,
        fixed: u6 = 0b100010,
        s: u1,
        op: u1,
        sf: u1,
    },
    logical_immediate: packed struct {
        rd: u5,
        rn: u5,
        imms: u6,
        immr: u6,
        n: u1,
        fixed: u6 = 0b100100,
        opc: u2,
        sf: u1,
    },
    bitfield: packed struct {
        rd: u5,
        rn: u5,
        imms: u6,
        immr: u6,
        n: u1,
        fixed: u6 = 0b100110,
        opc: u2,
        sf: u1,
    },
    add_subtract_shifted_register: packed struct {
        rd: u5,
        rn: u5,
        imm6: u6,
        rm: u5,
        fixed_1: u1 = 0b0,
        shift: u2,
        fixed_2: u5 = 0b01011,
        s: u1,
        op: u1,
        sf: u1,
    },
    add_subtract_extended_register: packed struct {
        rd: u5,
        rn: u5,
        imm3: u3,
        option: u3,
        rm: u5,
        fixed: u8 = 0b01011_00_1,
        s: u1,
        op: u1,
        sf: u1,
    },
    conditional_branch: struct {
        cond: u4,
        o0: u1,
        imm19: u19,
        o1: u1,
        fixed: u7 = 0b0101010,
    },
    compare_and_branch: struct {
        rt: u5,
        imm19: u19,
        op: u1,
        fixed: u6 = 0b011010,
        sf: u1,
    },
    conditional_select: struct {
        rd: u5,
        rn: u5,
        op2: u2,
        cond: u4,
        rm: u5,
        fixed: u8 = 0b11010100,
        s: u1,
        op: u1,
        sf: u1,
    },
    data_processing_3_source: packed struct {
        rd: u5,
        rn: u5,
        ra: u5,
        o0: u1,
        rm: u5,
        op31: u3,
        fixed: u5 = 0b11011,
        op54: u2,
        sf: u1,
    },
    data_processing_2_source: packed struct {
        rd: u5,
        rn: u5,
        opcode: u6,
        rm: u5,
        fixed_1: u8 = 0b11010110,
        s: u1,
        fixed_2: u1 = 0b0,
        sf: u1,
    },

    pub const Condition = enum(u4) {
        /// Integer: Equal
        /// Floating point: Equal
        eq,
        /// Integer: Not equal
        /// Floating point: Not equal or unordered
        ne,
        /// Integer: Carry set
        /// Floating point: Greater than, equal, or unordered
        cs,
        /// Integer: Carry clear
        /// Floating point: Less than
        cc,
        /// Integer: Minus, negative
        /// Floating point: Less than
        mi,
        /// Integer: Plus, positive or zero
        /// Floating point: Greater than, equal, or unordered
        pl,
        /// Integer: Overflow
        /// Floating point: Unordered
        vs,
        /// Integer: No overflow
        /// Floating point: Ordered
        vc,
        /// Integer: Unsigned higher
        /// Floating point: Greater than, or unordered
        hi,
        /// Integer: Unsigned lower or same
        /// Floating point: Less than or equal
        ls,
        /// Integer: Signed greater than or equal
        /// Floating point: Greater than or equal
        ge,
        /// Integer: Signed less than
        /// Floating point: Less than, or unordered
        lt,
        /// Integer: Signed greater than
        /// Floating point: Greater than
        gt,
        /// Integer: Signed less than or equal
        /// Floating point: Less than, equal, or unordered
        le,
        /// Integer: Always
        /// Floating point: Always
        al,
        /// Integer: Always
        /// Floating point: Always
        nv,

        /// Converts a std.math.CompareOperator into a condition flag,
        /// i.e. returns the condition that is true iff the result of the
        /// comparison is true. Assumes signed comparison
        pub fn fromCompareOperatorSigned(op: std.math.CompareOperator) Condition {
            return switch (op) {
                .gte => .ge,
                .gt => .gt,
                .neq => .ne,
                .lt => .lt,
                .lte => .le,
                .eq => .eq,
            };
        }

        /// Converts a std.math.CompareOperator into a condition flag,
        /// i.e. returns the condition that is true iff the result of the
        /// comparison is true. Assumes unsigned comparison
        pub fn fromCompareOperatorUnsigned(op: std.math.CompareOperator) Condition {
            return switch (op) {
                .gte => .cs,
                .gt => .hi,
                .neq => .ne,
                .lt => .cc,
                .lte => .ls,
                .eq => .eq,
            };
        }

        /// Returns the condition which is true iff the given condition is
        /// false (if such a condition exists)
        pub fn negate(cond: Condition) Condition {
            return switch (cond) {
                .eq => .ne,
                .ne => .eq,
                .cs => .cc,
                .cc => .cs,
                .mi => .pl,
                .pl => .mi,
                .vs => .vc,
                .vc => .vs,
                .hi => .ls,
                .ls => .hi,
                .ge => .lt,
                .lt => .ge,
                .gt => .le,
                .le => .gt,
                .al => unreachable,
                .nv => unreachable,
            };
        }
    };

    pub fn toU32(self: Instruction) u32 {
        return switch (self) {
            .move_wide_immediate => |v| @as(u32, @bitCast(v)),
            .pc_relative_address => |v| @as(u32, @bitCast(v)),
            .load_store_register => |v| @as(u32, @bitCast(v)),
            .load_store_register_pair => |v| @as(u32, @bitCast(v)),
            .load_literal => |v| @as(u32, @bitCast(v)),
            .exception_generation => |v| @as(u32, @bitCast(v)),
            .unconditional_branch_register => |v| @as(u32, @bitCast(v)),
            .unconditional_branch_immediate => |v| @as(u32, @bitCast(v)),
            .no_operation => |v| @as(u32, @bitCast(v)),
            .logical_shifted_register => |v| @as(u32, @bitCast(v)),
            .add_subtract_immediate => |v| @as(u32, @bitCast(v)),
            .logical_immediate => |v| @as(u32, @bitCast(v)),
            .bitfield => |v| @as(u32, @bitCast(v)),
            .add_subtract_shifted_register => |v| @as(u32, @bitCast(v)),
            .add_subtract_extended_register => |v| @as(u32, @bitCast(v)),
            // TODO once packed structs work, this can be refactored
            .conditional_branch => |v| @as(u32, v.cond) | (@as(u32, v.o0) << 4) | (@as(u32, v.imm19) << 5) | (@as(u32, v.o1) << 24) | (@as(u32, v.fixed) << 25),
            .compare_and_branch => |v| @as(u32, v.rt) | (@as(u32, v.imm19) << 5) | (@as(u32, v.op) << 24) | (@as(u32, v.fixed) << 25) | (@as(u32, v.sf) << 31),
            .conditional_select => |v| @as(u32, v.rd) | @as(u32, v.rn) << 5 | @as(u32, v.op2) << 10 | @as(u32, v.cond) << 12 | @as(u32, v.rm) << 16 | @as(u32, v.fixed) << 21 | @as(u32, v.s) << 29 | @as(u32, v.op) << 30 | @as(u32, v.sf) << 31,
            .data_processing_3_source => |v| @as(u32, @bitCast(v)),
            .data_processing_2_source => |v| @as(u32, @bitCast(v)),
        };
    }

    fn moveWideImmediate(
        opc: u2,
        rd: Register,
        imm16: u16,
        shift: u6,
    ) Instruction {
        assert(shift % 16 == 0);
        assert(!(rd.size() == 32 and shift > 16));
        assert(!(rd.size() == 64 and shift > 48));

        return Instruction{
            .move_wide_immediate = .{
                .rd = rd.enc(),
                .imm16 = imm16,
                .hw = @as(u2, @intCast(shift / 16)),
                .opc = opc,
                .sf = switch (rd.size()) {
                    32 => 0,
                    64 => 1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn pcRelativeAddress(rd: Register, imm21: i21, op: u1) Instruction {
        assert(rd.size() == 64);
        const imm21_u = @as(u21, @bitCast(imm21));
        return Instruction{
            .pc_relative_address = .{
                .rd = rd.enc(),
                .immlo = @as(u2, @truncate(imm21_u)),
                .immhi = @as(u19, @truncate(imm21_u >> 2)),
                .op = op,
            },
        };
    }

    pub const LoadStoreOffsetImmediate = union(enum) {
        post_index: i9,
        pre_index: i9,
        unsigned: u12,
    };

    pub const LoadStoreOffsetRegister = struct {
        rm: u5,
        shift: union(enum) {
            uxtw: u2,
            lsl: u2,
            sxtw: u2,
            sxtx: u2,
        },
    };

    /// Represents the offset operand of a load or store instruction.
    /// Data can be loaded from memory with either an immediate offset
    /// or an offset that is stored in some register.
    pub const LoadStoreOffset = union(enum) {
        immediate: LoadStoreOffsetImmediate,
        register: LoadStoreOffsetRegister,

        pub const none = LoadStoreOffset{
            .immediate = .{ .unsigned = 0 },
        };

        pub fn toU12(self: LoadStoreOffset) u12 {
            return switch (self) {
                .immediate => |imm_type| switch (imm_type) {
                    .post_index => |v| (@as(u12, @intCast(@as(u9, @bitCast(v)))) << 2) + 1,
                    .pre_index => |v| (@as(u12, @intCast(@as(u9, @bitCast(v)))) << 2) + 3,
                    .unsigned => |v| v,
                },
                .register => |r| switch (r.shift) {
                    .uxtw => |v| (@as(u12, @intCast(r.rm)) << 6) + (@as(u12, @intCast(v)) << 2) + 16 + 2050,
                    .lsl => |v| (@as(u12, @intCast(r.rm)) << 6) + (@as(u12, @intCast(v)) << 2) + 24 + 2050,
                    .sxtw => |v| (@as(u12, @intCast(r.rm)) << 6) + (@as(u12, @intCast(v)) << 2) + 48 + 2050,
                    .sxtx => |v| (@as(u12, @intCast(r.rm)) << 6) + (@as(u12, @intCast(v)) << 2) + 56 + 2050,
                },
            };
        }

        pub fn imm(offset: u12) LoadStoreOffset {
            return .{
                .immediate = .{ .unsigned = offset },
            };
        }

        pub fn imm_post_index(offset: i9) LoadStoreOffset {
            return .{
                .immediate = .{ .post_index = offset },
            };
        }

        pub fn imm_pre_index(offset: i9) LoadStoreOffset {
            return .{
                .immediate = .{ .pre_index = offset },
            };
        }

        pub fn reg(rm: Register) LoadStoreOffset {
            return .{
                .register = .{
                    .rm = rm.enc(),
                    .shift = .{
                        .lsl = 0,
                    },
                },
            };
        }

        pub fn reg_uxtw(rm: Register, shift: u2) LoadStoreOffset {
            assert(rm.size() == 32 and (shift == 0 or shift == 2));
            return .{
                .register = .{
                    .rm = rm.enc(),
                    .shift = .{
                        .uxtw = shift,
                    },
                },
            };
        }

        pub fn reg_lsl(rm: Register, shift: u2) LoadStoreOffset {
            assert(rm.size() == 64 and (shift == 0 or shift == 3));
            return .{
                .register = .{
                    .rm = rm.enc(),
                    .shift = .{
                        .lsl = shift,
                    },
                },
            };
        }

        pub fn reg_sxtw(rm: Register, shift: u2) LoadStoreOffset {
            assert(rm.size() == 32 and (shift == 0 or shift == 2));
            return .{
                .register = .{
                    .rm = rm.enc(),
                    .shift = .{
                        .sxtw = shift,
                    },
                },
            };
        }

        pub fn reg_sxtx(rm: Register, shift: u2) LoadStoreOffset {
            assert(rm.size() == 64 and (shift == 0 or shift == 3));
            return .{
                .register = .{
                    .rm = rm.enc(),
                    .shift = .{
                        .sxtx = shift,
                    },
                },
            };
        }
    };

    /// Which kind of load/store to perform
    const LoadStoreVariant = enum {
        /// 32 bits or 64 bits
        str,
        /// 8 bits, zero-extended
        strb,
        /// 16 bits, zero-extended
        strh,
        /// 32 bits or 64 bits
        ldr,
        /// 8 bits, zero-extended
        ldrb,
        /// 16 bits, zero-extended
        ldrh,
        /// 8 bits, sign extended
        ldrsb,
        /// 16 bits, sign extended
        ldrsh,
        /// 32 bits, sign extended
        ldrsw,
    };

    fn loadStoreRegister(
        rt: Register,
        rn: Register,
        offset: LoadStoreOffset,
        variant: LoadStoreVariant,
    ) Instruction {
        assert(rn.size() == 64);
        assert(rn.id() != Register.xzr.id());

        const off = offset.toU12();

        const op1: u2 = blk: {
            switch (offset) {
                .immediate => |imm| switch (imm) {
                    .unsigned => break :blk 0b01,
                    else => {},
                },
                else => {},
            }
            break :blk 0b00;
        };

        const opc: u2 = blk: {
            switch (variant) {
                .ldr, .ldrh, .ldrb => break :blk 0b01,
                .str, .strh, .strb => break :blk 0b00,
                .ldrsb,
                .ldrsh,
                => switch (rt.size()) {
                    32 => break :blk 0b11,
                    64 => break :blk 0b10,
                    else => unreachable, // unexpected register size
                },
                .ldrsw => break :blk 0b10,
            }
        };

        const size: u2 = blk: {
            switch (variant) {
                .ldr, .str => switch (rt.size()) {
                    32 => break :blk 0b10,
                    64 => break :blk 0b11,
                    else => unreachable, // unexpected register size
                },
                .ldrsw => break :blk 0b10,
                .ldrh, .ldrsh, .strh => break :blk 0b01,
                .ldrb, .ldrsb, .strb => break :blk 0b00,
            }
        };

        return Instruction{
            .load_store_register = .{
                .rt = rt.enc(),
                .rn = rn.enc(),
                .offset = off,
                .opc = opc,
                .op1 = op1,
                .v = 0,
                .size = size,
            },
        };
    }

    fn loadStoreRegisterPair(
        rt1: Register,
        rt2: Register,
        rn: Register,
        offset: i9,
        encoding: u2,
        load: bool,
    ) Instruction {
        assert(rn.size() == 64);
        assert(rn.id() != Register.xzr.id());

        switch (rt1.size()) {
            32 => {
                assert(-256 <= offset and offset <= 252);
                const imm7 = @as(u7, @truncate(@as(u9, @bitCast(offset >> 2))));
                return Instruction{
                    .load_store_register_pair = .{
                        .rt1 = rt1.enc(),
                        .rn = rn.enc(),
                        .rt2 = rt2.enc(),
                        .imm7 = imm7,
                        .load = @intFromBool(load),
                        .encoding = encoding,
                        .opc = 0b00,
                    },
                };
            },
            64 => {
                assert(-512 <= offset and offset <= 504);
                const imm7 = @as(u7, @truncate(@as(u9, @bitCast(offset >> 3))));
                return Instruction{
                    .load_store_register_pair = .{
                        .rt1 = rt1.enc(),
                        .rn = rn.enc(),
                        .rt2 = rt2.enc(),
                        .imm7 = imm7,
                        .load = @intFromBool(load),
                        .encoding = encoding,
                        .opc = 0b10,
                    },
                };
            },
            else => unreachable, // unexpected register size
        }
    }

    fn loadLiteral(rt: Register, imm19: u19) Instruction {
        return Instruction{
            .load_literal = .{
                .rt = rt.enc(),
                .imm19 = imm19,
                .opc = switch (rt.size()) {
                    32 => 0b00,
                    64 => 0b01,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn exceptionGeneration(
        opc: u3,
        op2: u3,
        ll: u2,
        imm16: u16,
    ) Instruction {
        return Instruction{
            .exception_generation = .{
                .ll = ll,
                .op2 = op2,
                .imm16 = imm16,
                .opc = opc,
            },
        };
    }

    fn unconditionalBranchRegister(
        opc: u4,
        op2: u5,
        op3: u6,
        rn: Register,
        op4: u5,
    ) Instruction {
        assert(rn.size() == 64);

        return Instruction{
            .unconditional_branch_register = .{
                .op4 = op4,
                .rn = rn.enc(),
                .op3 = op3,
                .op2 = op2,
                .opc = opc,
            },
        };
    }

    fn unconditionalBranchImmediate(
        op: u1,
        offset: i28,
    ) Instruction {
        return Instruction{
            .unconditional_branch_immediate = .{
                .imm26 = @as(u26, @bitCast(@as(i26, @intCast(offset >> 2)))),
                .op = op,
            },
        };
    }

    pub const LogicalShiftedRegisterShift = enum(u2) { lsl, lsr, asr, ror };

    fn logicalShiftedRegister(
        opc: u2,
        n: u1,
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(rd.size() == rm.size());
        if (rd.size() == 32) assert(amount < 32);

        return Instruction{
            .logical_shifted_register = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imm6 = amount,
                .rm = rm.enc(),
                .n = n,
                .shift = @intFromEnum(shift),
                .opc = opc,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable,
                },
            },
        };
    }

    fn addSubtractImmediate(
        op: u1,
        s: u1,
        rd: Register,
        rn: Register,
        imm12: u12,
        shift: bool,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(rn.id() != Register.xzr.id());

        return Instruction{
            .add_subtract_immediate = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imm12 = imm12,
                .sh = @intFromBool(shift),
                .s = s,
                .op = op,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn logicalImmediate(
        opc: u2,
        rd: Register,
        rn: Register,
        imms: u6,
        immr: u6,
        n: u1,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(!(rd.size() == 32 and n != 0));

        return Instruction{
            .logical_immediate = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imms = imms,
                .immr = immr,
                .n = n,
                .opc = opc,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn bitfield(
        opc: u2,
        n: u1,
        rd: Register,
        rn: Register,
        immr: u6,
        imms: u6,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(!(rd.size() == 64 and n != 1));
        assert(!(rd.size() == 32 and (n != 0 or immr >> 5 != 0 or immr >> 5 != 0)));

        return Instruction{
            .bitfield = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imms = imms,
                .immr = immr,
                .n = n,
                .opc = opc,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    pub const AddSubtractShiftedRegisterShift = enum(u2) { lsl, lsr, asr, _ };

    fn addSubtractShiftedRegister(
        op: u1,
        s: u1,
        shift: AddSubtractShiftedRegisterShift,
        rd: Register,
        rn: Register,
        rm: Register,
        imm6: u6,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(rd.size() == rm.size());

        return Instruction{
            .add_subtract_shifted_register = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imm6 = imm6,
                .rm = rm.enc(),
                .shift = @intFromEnum(shift),
                .s = s,
                .op = op,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    pub const AddSubtractExtendedRegisterOption = enum(u3) {
        uxtb,
        uxth,
        uxtw,
        uxtx, // serves also as lsl
        sxtb,
        sxth,
        sxtw,
        sxtx,
    };

    fn addSubtractExtendedRegister(
        op: u1,
        s: u1,
        rd: Register,
        rn: Register,
        rm: Register,
        extend: AddSubtractExtendedRegisterOption,
        imm3: u3,
    ) Instruction {
        return Instruction{
            .add_subtract_extended_register = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .imm3 = imm3,
                .option = @intFromEnum(extend),
                .rm = rm.enc(),
                .s = s,
                .op = op,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn conditionalBranch(
        o0: u1,
        o1: u1,
        cond: Condition,
        offset: i21,
    ) Instruction {
        assert(offset & 0b11 == 0b00);

        return Instruction{
            .conditional_branch = .{
                .cond = @intFromEnum(cond),
                .o0 = o0,
                .imm19 = @as(u19, @bitCast(@as(i19, @intCast(offset >> 2)))),
                .o1 = o1,
            },
        };
    }

    fn compareAndBranch(
        op: u1,
        rt: Register,
        offset: i21,
    ) Instruction {
        assert(offset & 0b11 == 0b00);

        return Instruction{
            .compare_and_branch = .{
                .rt = rt.enc(),
                .imm19 = @as(u19, @bitCast(@as(i19, @intCast(offset >> 2)))),
                .op = op,
                .sf = switch (rt.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn conditionalSelect(
        op2: u2,
        op: u1,
        s: u1,
        rd: Register,
        rn: Register,
        rm: Register,
        cond: Condition,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(rd.size() == rm.size());

        return Instruction{
            .conditional_select = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .op2 = op2,
                .cond = @intFromEnum(cond),
                .rm = rm.enc(),
                .s = s,
                .op = op,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn dataProcessing3Source(
        op54: u2,
        op31: u3,
        o0: u1,
        rd: Register,
        rn: Register,
        rm: Register,
        ra: Register,
    ) Instruction {
        return Instruction{
            .data_processing_3_source = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .ra = ra.enc(),
                .o0 = o0,
                .rm = rm.enc(),
                .op31 = op31,
                .op54 = op54,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    fn dataProcessing2Source(
        s: u1,
        opcode: u6,
        rd: Register,
        rn: Register,
        rm: Register,
    ) Instruction {
        assert(rd.size() == rn.size());
        assert(rd.size() == rm.size());

        return Instruction{
            .data_processing_2_source = .{
                .rd = rd.enc(),
                .rn = rn.enc(),
                .opcode = opcode,
                .rm = rm.enc(),
                .s = s,
                .sf = switch (rd.size()) {
                    32 => 0b0,
                    64 => 0b1,
                    else => unreachable, // unexpected register size
                },
            },
        };
    }

    // Helper functions for assembly syntax functions

    // Move wide (immediate)

    pub fn movn(rd: Register, imm16: u16, shift: u6) Instruction {
        return moveWideImmediate(0b00, rd, imm16, shift);
    }

    pub fn movz(rd: Register, imm16: u16, shift: u6) Instruction {
        return moveWideImmediate(0b10, rd, imm16, shift);
    }

    pub fn movk(rd: Register, imm16: u16, shift: u6) Instruction {
        return moveWideImmediate(0b11, rd, imm16, shift);
    }

    // PC relative address

    pub fn adr(rd: Register, imm21: i21) Instruction {
        return pcRelativeAddress(rd, imm21, 0b0);
    }

    pub fn adrp(rd: Register, imm21: i21) Instruction {
        return pcRelativeAddress(rd, imm21, 0b1);
    }

    // Load or store register

    pub fn ldrLiteral(rt: Register, literal: u19) Instruction {
        return loadLiteral(rt, literal);
    }

    pub fn ldr(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldr);
    }

    pub fn ldrh(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldrh);
    }

    pub fn ldrb(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldrb);
    }

    pub fn ldrsb(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldrsb);
    }

    pub fn ldrsh(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldrsh);
    }

    pub fn ldrsw(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .ldrsw);
    }

    pub fn str(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .str);
    }

    pub fn strh(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .strh);
    }

    pub fn strb(rt: Register, rn: Register, offset: LoadStoreOffset) Instruction {
        return loadStoreRegister(rt, rn, offset, .strb);
    }

    // Load or store pair of registers

    pub const LoadStorePairOffset = struct {
        encoding: enum(u2) {
            post_index = 0b01,
            signed = 0b10,
            pre_index = 0b11,
        },
        offset: i9,

        pub fn none() LoadStorePairOffset {
            return .{ .encoding = .signed, .offset = 0 };
        }

        pub fn post_index(imm: i9) LoadStorePairOffset {
            return .{ .encoding = .post_index, .offset = imm };
        }

        pub fn pre_index(imm: i9) LoadStorePairOffset {
            return .{ .encoding = .pre_index, .offset = imm };
        }

        pub fn signed(imm: i9) LoadStorePairOffset {
            return .{ .encoding = .signed, .offset = imm };
        }
    };

    pub fn ldp(rt1: Register, rt2: Register, rn: Register, offset: LoadStorePairOffset) Instruction {
        return loadStoreRegisterPair(rt1, rt2, rn, offset.offset, @intFromEnum(offset.encoding), true);
    }

    pub fn ldnp(rt1: Register, rt2: Register, rn: Register, offset: i9) Instruction {
        return loadStoreRegisterPair(rt1, rt2, rn, offset, 0, true);
    }

    pub fn stp(rt1: Register, rt2: Register, rn: Register, offset: LoadStorePairOffset) Instruction {
        return loadStoreRegisterPair(rt1, rt2, rn, offset.offset, @intFromEnum(offset.encoding), false);
    }

    pub fn stnp(rt1: Register, rt2: Register, rn: Register, offset: i9) Instruction {
        return loadStoreRegisterPair(rt1, rt2, rn, offset, 0, false);
    }

    // Exception generation

    pub fn svc(imm16: u16) Instruction {
        return exceptionGeneration(0b000, 0b000, 0b01, imm16);
    }

    pub fn hvc(imm16: u16) Instruction {
        return exceptionGeneration(0b000, 0b000, 0b10, imm16);
    }

    pub fn smc(imm16: u16) Instruction {
        return exceptionGeneration(0b000, 0b000, 0b11, imm16);
    }

    pub fn brk(imm16: u16) Instruction {
        return exceptionGeneration(0b001, 0b000, 0b00, imm16);
    }

    pub fn hlt(imm16: u16) Instruction {
        return exceptionGeneration(0b010, 0b000, 0b00, imm16);
    }

    // Unconditional branch (register)

    pub fn br(rn: Register) Instruction {
        return unconditionalBranchRegister(0b0000, 0b11111, 0b000000, rn, 0b00000);
    }

    pub fn blr(rn: Register) Instruction {
        return unconditionalBranchRegister(0b0001, 0b11111, 0b000000, rn, 0b00000);
    }

    pub fn ret(rn: ?Register) Instruction {
        return unconditionalBranchRegister(0b0010, 0b11111, 0b000000, rn orelse .x30, 0b00000);
    }

    // Unconditional branch (immediate)

    pub fn b(offset: i28) Instruction {
        return unconditionalBranchImmediate(0, offset);
    }

    pub fn bl(offset: i28) Instruction {
        return unconditionalBranchImmediate(1, offset);
    }

    // Nop

    pub fn nop() Instruction {
        return Instruction{ .no_operation = .{} };
    }

    // Logical (shifted register)

    pub fn andShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b00, 0b0, rd, rn, rm, shift, amount);
    }

    pub fn bicShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b00, 0b1, rd, rn, rm, shift, amount);
    }

    pub fn orrShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b01, 0b0, rd, rn, rm, shift, amount);
    }

    pub fn ornShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b01, 0b1, rd, rn, rm, shift, amount);
    }

    pub fn eorShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b10, 0b0, rd, rn, rm, shift, amount);
    }

    pub fn eonShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b10, 0b1, rd, rn, rm, shift, amount);
    }

    pub fn andsShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b11, 0b0, rd, rn, rm, shift, amount);
    }

    pub fn bicsShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: LogicalShiftedRegisterShift,
        amount: u6,
    ) Instruction {
        return logicalShiftedRegister(0b11, 0b1, rd, rn, rm, shift, amount);
    }

    // Add/subtract (immediate)

    pub fn add(rd: Register, rn: Register, imm: u12, shift: bool) Instruction {
        return addSubtractImmediate(0b0, 0b0, rd, rn, imm, shift);
    }

    pub fn adds(rd: Register, rn: Register, imm: u12, shift: bool) Instruction {
        return addSubtractImmediate(0b0, 0b1, rd, rn, imm, shift);
    }

    pub fn sub(rd: Register, rn: Register, imm: u12, shift: bool) Instruction {
        return addSubtractImmediate(0b1, 0b0, rd, rn, imm, shift);
    }

    pub fn subs(rd: Register, rn: Register, imm: u12, shift: bool) Instruction {
        return addSubtractImmediate(0b1, 0b1, rd, rn, imm, shift);
    }

    // Logical (immediate)

    pub fn andImmediate(rd: Register, rn: Register, imms: u6, immr: u6, n: u1) Instruction {
        return logicalImmediate(0b00, rd, rn, imms, immr, n);
    }

    pub fn orrImmediate(rd: Register, rn: Register, imms: u6, immr: u6, n: u1) Instruction {
        return logicalImmediate(0b01, rd, rn, imms, immr, n);
    }

    pub fn eorImmediate(rd: Register, rn: Register, imms: u6, immr: u6, n: u1) Instruction {
        return logicalImmediate(0b10, rd, rn, imms, immr, n);
    }

    pub fn andsImmediate(rd: Register, rn: Register, imms: u6, immr: u6, n: u1) Instruction {
        return logicalImmediate(0b11, rd, rn, imms, immr, n);
    }

    // Bitfield

    pub fn sbfm(rd: Register, rn: Register, immr: u6, imms: u6) Instruction {
        const n: u1 = switch (rd.size()) {
            32 => 0b0,
            64 => 0b1,
            else => unreachable, // unexpected register size
        };
        return bitfield(0b00, n, rd, rn, immr, imms);
    }

    pub fn bfm(rd: Register, rn: Register, immr: u6, imms: u6) Instruction {
        const n: u1 = switch (rd.size()) {
            32 => 0b0,
            64 => 0b1,
            else => unreachable, // unexpected register size
        };
        return bitfield(0b01, n, rd, rn, immr, imms);
    }

    pub fn ubfm(rd: Register, rn: Register, immr: u6, imms: u6) Instruction {
        const n: u1 = switch (rd.size()) {
            32 => 0b0,
            64 => 0b1,
            else => unreachable, // unexpected register size
        };
        return bitfield(0b10, n, rd, rn, immr, imms);
    }

    pub fn asrImmediate(rd: Register, rn: Register, shift: u6) Instruction {
        const imms = @as(u6, @intCast(rd.size() - 1));
        return sbfm(rd, rn, shift, imms);
    }

    pub fn sbfx(rd: Register, rn: Register, lsb: u6, width: u7) Instruction {
        return sbfm(rd, rn, lsb, @as(u6, @intCast(lsb + width - 1)));
    }

    pub fn sxtb(rd: Register, rn: Register) Instruction {
        return sbfm(rd, rn, 0, 7);
    }

    pub fn sxth(rd: Register, rn: Register) Instruction {
        return sbfm(rd, rn, 0, 15);
    }

    pub fn sxtw(rd: Register, rn: Register) Instruction {
        assert(rd.size() == 64);
        return sbfm(rd, rn, 0, 31);
    }

    pub fn lslImmediate(rd: Register, rn: Register, shift: u6) Instruction {
        const size = @as(u6, @intCast(rd.size() - 1));
        return ubfm(rd, rn, size - shift + 1, size - shift);
    }

    pub fn lsrImmediate(rd: Register, rn: Register, shift: u6) Instruction {
        const imms = @as(u6, @intCast(rd.size() - 1));
        return ubfm(rd, rn, shift, imms);
    }

    pub fn ubfx(rd: Register, rn: Register, lsb: u6, width: u7) Instruction {
        return ubfm(rd, rn, lsb, @as(u6, @intCast(lsb + width - 1)));
    }

    pub fn uxtb(rd: Register, rn: Register) Instruction {
        return ubfm(rd, rn, 0, 7);
    }

    pub fn uxth(rd: Register, rn: Register) Instruction {
        return ubfm(rd, rn, 0, 15);
    }

    // Add/subtract (shifted register)

    pub fn addShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: AddSubtractShiftedRegisterShift,
        imm6: u6,
    ) Instruction {
        return addSubtractShiftedRegister(0b0, 0b0, shift, rd, rn, rm, imm6);
    }

    pub fn addsShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: AddSubtractShiftedRegisterShift,
        imm6: u6,
    ) Instruction {
        return addSubtractShiftedRegister(0b0, 0b1, shift, rd, rn, rm, imm6);
    }

    pub fn subShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: AddSubtractShiftedRegisterShift,
        imm6: u6,
    ) Instruction {
        return addSubtractShiftedRegister(0b1, 0b0, shift, rd, rn, rm, imm6);
    }

    pub fn subsShiftedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        shift: AddSubtractShiftedRegisterShift,
        imm6: u6,
    ) Instruction {
        return addSubtractShiftedRegister(0b1, 0b1, shift, rd, rn, rm, imm6);
    }

    // Add/subtract (extended register)

    pub fn addExtendedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        extend: AddSubtractExtendedRegisterOption,
        imm3: u3,
    ) Instruction {
        return addSubtractExtendedRegister(0b0, 0b0, rd, rn, rm, extend, imm3);
    }

    pub fn addsExtendedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        extend: AddSubtractExtendedRegisterOption,
        imm3: u3,
    ) Instruction {
        return addSubtractExtendedRegister(0b0, 0b1, rd, rn, rm, extend, imm3);
    }

    pub fn subExtendedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        extend: AddSubtractExtendedRegisterOption,
        imm3: u3,
    ) Instruction {
        return addSubtractExtendedRegister(0b1, 0b0, rd, rn, rm, extend, imm3);
    }

    pub fn subsExtendedRegister(
        rd: Register,
        rn: Register,
        rm: Register,
        extend: AddSubtractExtendedRegisterOption,
        imm3: u3,
    ) Instruction {
        return addSubtractExtendedRegister(0b1, 0b1, rd, rn, rm, extend, imm3);
    }

    // Conditional branch

    pub fn bCond(cond: Condition, offset: i21) Instruction {
        return conditionalBranch(0b0, 0b0, cond, offset);
    }

    // Compare and branch

    pub fn cbz(rt: Register, offset: i21) Instruction {
        return compareAndBranch(0b0, rt, offset);
    }

    pub fn cbnz(rt: Register, offset: i21) Instruction {
        return compareAndBranch(0b1, rt, offset);
    }

    // Conditional select

    pub fn csel(rd: Register, rn: Register, rm: Register, cond: Condition) Instruction {
        return conditionalSelect(0b00, 0b0, 0b0, rd, rn, rm, cond);
    }

    pub fn csinc(rd: Register, rn: Register, rm: Register, cond: Condition) Instruction {
        return conditionalSelect(0b01, 0b0, 0b0, rd, rn, rm, cond);
    }

    pub fn csinv(rd: Register, rn: Register, rm: Register, cond: Condition) Instruction {
        return conditionalSelect(0b00, 0b1, 0b0, rd, rn, rm, cond);
    }

    pub fn csneg(rd: Register, rn: Register, rm: Register, cond: Condition) Instruction {
        return conditionalSelect(0b01, 0b1, 0b0, rd, rn, rm, cond);
    }

    // Data processing (3 source)

    pub fn madd(rd: Register, rn: Register, rm: Register, ra: Register) Instruction {
        return dataProcessing3Source(0b00, 0b000, 0b0, rd, rn, rm, ra);
    }

    pub fn smaddl(rd: Register, rn: Register, rm: Register, ra: Register) Instruction {
        assert(rd.size() == 64 and rn.size() == 32 and rm.size() == 32 and ra.size() == 64);
        return dataProcessing3Source(0b00, 0b001, 0b0, rd, rn, rm, ra);
    }

    pub fn umaddl(rd: Register, rn: Register, rm: Register, ra: Register) Instruction {
        assert(rd.size() == 64 and rn.size() == 32 and rm.size() == 32 and ra.size() == 64);
        return dataProcessing3Source(0b00, 0b101, 0b0, rd, rn, rm, ra);
    }

    pub fn msub(rd: Register, rn: Register, rm: Register, ra: Register) Instruction {
        return dataProcessing3Source(0b00, 0b000, 0b1, rd, rn, rm, ra);
    }

    pub fn mul(rd: Register, rn: Register, rm: Register) Instruction {
        return madd(rd, rn, rm, .xzr);
    }

    pub fn smull(rd: Register, rn: Register, rm: Register) Instruction {
        return smaddl(rd, rn, rm, .xzr);
    }

    pub fn smulh(rd: Register, rn: Register, rm: Register) Instruction {
        assert(rd.size() == 64);
        return dataProcessing3Source(0b00, 0b010, 0b0, rd, rn, rm, .xzr);
    }

    pub fn umull(rd: Register, rn: Register, rm: Register) Instruction {
        return umaddl(rd, rn, rm, .xzr);
    }

    pub fn umulh(rd: Register, rn: Register, rm: Register) Instruction {
        assert(rd.size() == 64);
        return dataProcessing3Source(0b00, 0b110, 0b0, rd, rn, rm, .xzr);
    }

    pub fn mneg(rd: Register, rn: Register, rm: Register) Instruction {
        return msub(rd, rn, rm, .xzr);
    }

    // Data processing (2 source)

    pub fn lslv(rd: Register, rn: Register, rm: Register) Instruction {
        return dataProcessing2Source(0b0, 0b001000, rd, rn, rm);
    }

    pub fn lsrv(rd: Register, rn: Register, rm: Register) Instruction {
        return dataProcessing2Source(0b0, 0b001001, rd, rn, rm);
    }

    pub fn asrv(rd: Register, rn: Register, rm: Register) Instruction {
        return dataProcessing2Source(0b0, 0b001010, rd, rn, rm);
    }

    pub const asrRegister = asrv;
    pub const lslRegister = lslv;
    pub const lsrRegister = lsrv;
};

pub inline fn isArithmeticOp(inst: *const [4]u8) bool {
    const group_decode = @as(u5, @truncate(inst[3]));
    return ((group_decode >> 2) == 4);
}

pub const PageOffsetInstKind = enum {
    arithmetic,
    load_store_8,
    load_store_16,
    load_store_32,
    load_store_64,
    load_store_128,
};

pub fn classifyInst(code: *const [4]u8) PageOffsetInstKind {
    if (isArithmeticOp(code)) return .arithmetic;
    const inst = Instruction{
        .load_store_register = mem.bytesToValue(std.meta.TagPayload(
            Instruction,
            Instruction.load_store_register,
        ), code),
    };
    return switch (inst.load_store_register.size) {
        0 => if (inst.load_store_register.v == 1) .load_store_128 else .load_store_8,
        1 => .load_store_16,
        2 => .load_store_32,
        3 => .load_store_64,
    };
}

pub fn calcPageOffset(kind: PageOffsetInstKind, taddr: u64) !u12 {
    const narrowed = @as(u12, @truncate(taddr));
    return switch (kind) {
        .arithmetic, .load_store_8 => narrowed,
        .load_store_16 => try math.divExact(u12, narrowed, 2),
        .load_store_32 => try math.divExact(u12, narrowed, 4),
        .load_store_64 => try math.divExact(u12, narrowed, 8),
        .load_store_128 => try math.divExact(u12, narrowed, 16),
    };
}

pub fn writePageOffset(kind: PageOffsetInstKind, taddr: u64, code: *[4]u8) !void {
    const value = try calcPageOffset(kind, taddr);
    switch (kind) {
        .arithmetic => {
            var inst = Instruction{
                .add_subtract_immediate = mem.bytesToValue(std.meta.TagPayload(
                    Instruction,
                    Instruction.add_subtract_immediate,
                ), code),
            };
            inst.add_subtract_immediate.imm12 = value;
            mem.writeInt(u32, code, inst.toU32(), .little);
        },
        else => {
            var inst: Instruction = .{
                .load_store_register = mem.bytesToValue(std.meta.TagPayload(
                    Instruction,
                    Instruction.load_store_register,
                ), code),
            };
            inst.load_store_register.offset = value;
            mem.writeInt(u32, code, inst.toU32(), .little);
        },
    }
}

pub fn calcNumberOfPages(saddr: u64, taddr: u64) error{Overflow}!i21 {
    const spage = math.cast(i32, saddr >> 12) orelse return error.Overflow;
    const tpage = math.cast(i32, taddr >> 12) orelse return error.Overflow;
    const pages = math.cast(i21, tpage - spage) orelse return error.Overflow;
    return pages;
}

pub fn writePages(pages: u21, code: *[4]u8) !void {
    var inst = Instruction{
        .pc_relative_address = mem.bytesToValue(std.meta.TagPayload(
            Instruction,
            Instruction.pc_relative_address,
        ), code),
    };
    inst.pc_relative_address.immhi = @as(u19, @truncate(pages >> 2));
    inst.pc_relative_address.immlo = @as(u2, @truncate(pages));
    mem.writeInt(u32, code, inst.toU32(), .little);
}

pub fn writeBranchImm(disp: i28, code: *[4]u8) !void {
    var inst = Instruction{
        .unconditional_branch_immediate = mem.bytesToValue(std.meta.TagPayload(
            Instruction,
            Instruction.unconditional_branch_immediate,
        ), code),
    };
    inst.unconditional_branch_immediate.imm26 = @as(u26, @truncate(@as(u28, @bitCast(disp >> 2))));
    mem.writeInt(u32, code, inst.toU32(), .little);
}

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const mem = std.mem;
const DW = std.dwarf;
const assert = std.debug.assert;
const testing = std.testing;
