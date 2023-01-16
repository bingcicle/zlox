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
    op_nil = 0x7,
    op_true = 0x8,
    op_false = 0x9,

    pub fn handleBinaryOp(self: Opcode, a: f64, b: f64) !Value {
        var result = switch (self) {
            Opcode.op_add => a + b,
            Opcode.op_subtract => a - b,
            Opcode.op_multiply => a * b,
            Opcode.op_divide => a / b,
            else => return error.InvalidOpcode,
        };

        return Value.newNumber(result);
    }
};
