const Value = @import("value.zig").Value;
const std = @import("std");

const OpcodeError = error{
    InvalidOpcode,
};

pub const Opcode = enum(u8) {
    op_return = 0x0,
    op_constant = 0x1,
    op_add = 0x2,
    op_subtract = 0x3,
    op_multiply = 0x4,
    op_divide = 0x5,
    op_negate = 0x6,

    pub fn handleBinaryOp(self: Opcode, a: f64, b: f64) !Value {
        const value = switch (self) {
            Opcode.op_add => Value{ .data = a + b },
            Opcode.op_subtract => Value{ .data = a - b },
            Opcode.op_multiply => Value{ .data = a * b },
            Opcode.op_divide => Value{ .data = a / b },
            else => return error.InvalidOpcode,
        };

        return value;
    }
};
