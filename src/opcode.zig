const Value = @import("value.zig").Value;
const std = @import("std");

const OpcodeError = error{
    InvalidOpcode,
};

pub const Opcode = enum(u8) {
    op_return,
    op_constant,
    op_nil,
    op_true,
    op_false,
    op_pop,
    op_get_local,
    op_get_global,
    op_define_global,
    op_set_local,
    op_set_global,
    op_equal,
    op_greater,
    op_less,
    op_add,
    op_subtract,
    op_multiply,
    op_divide,
    op_not,
    op_negate,
    op_print,
    op_jump,
    op_jump_if_false,
    op_loop,

    pub fn handleBinaryOp(self: Opcode, a: f64, b: f64) !Value {
        return switch (self) {
            Opcode.op_add => Value.newNumber(a + b),
            Opcode.op_greater => Value.newBool(a > b),
            Opcode.op_less => Value.newBool(a < b),
            Opcode.op_subtract => Value.newNumber(a - b),
            Opcode.op_multiply => Value.newNumber(a * b),
            Opcode.op_divide => Value.newNumber(a / b),
            else => return error.InvalidOpcode,
        };
    }
};
