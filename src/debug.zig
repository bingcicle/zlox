const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;
const Chunk = @import("chunk.zig");
const WriteError = std.os.WriteError;
const Value = @import("value.zig").Value;
const Obj = @import("Object.zig");

pub fn printValue(value: Value) void {
    switch (value.type) {
        Value.Type.bool => std.debug.print("{}", .{Value.asBool(value)}),
        Value.Type.nil => std.debug.print("nil", .{}),
        Value.Type.number => std.debug.print("{d:.5}", .{Value.asNumber(value)}),
        Value.Type.obj => Obj.print(value),
    }
}

pub fn byteInstruction(name: []const u8, chunk: anytype, offset: usize) usize {
    var slot = chunk.code.ptr[offset + 1];
    std.debug.print("{s} {d:.4}\n", .{ name, slot });
    return offset + 2;
}

pub fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

pub fn constantInstruction(name: []const u8, chunk: anytype, offset: usize) usize {
    var constant = chunk.code.ptr[offset + 1];
    std.debug.print("{s} {d:.4} ", .{ name, constant });
    printValue(chunk.constants.values.ptr[constant]);
    std.debug.print("\n", .{});
    return offset + 2;
}

pub fn jumpInstruction(name: []const u8, sign: isize, chunk: anytype, offset: usize) usize {
    var jump = @as(u16, chunk.code.ptr[offset + 1]);
    jump <<= 8;
    jump |= chunk.code.ptr[offset + 2];

    std.debug.print("{s} {d:.4} -> {d}\n", .{ name, offset, @intCast(isize, offset) + 3 + sign * @intCast(isize, jump) });
    return offset + 3;
}

pub fn disassembleInstruction(chunk: anytype, offset: usize) usize {
    if (offset > 99) {
        std.debug.print("{d} ", .{offset});
    } else if (offset > 9) {
        std.debug.print("{d}  ", .{offset});
    } else {
        std.debug.print("{d}   ", .{offset});
    }

    if (offset > 0 and chunk.lines.ptr[offset] == chunk.lines.ptr[offset - 1]) {
        std.debug.print("  | ", .{});
    } else {
        std.debug.print("{d} ", .{chunk.lines.ptr[offset]});
    }
    var instruction = chunk.code.ptr[offset];
    switch (@intToEnum(Opcode, instruction)) {
        Opcode.op_return => {
            return simpleInstruction("OP_RETURN", offset);
        },
        Opcode.op_constant => {
            return constantInstruction("OP_CONSTANT", chunk, offset);
        },
        Opcode.op_add => {
            return simpleInstruction("OP_ADD", offset);
        },
        Opcode.op_subtract => {
            return simpleInstruction("OP_SUBTRACT", offset);
        },
        Opcode.op_multiply => {
            return simpleInstruction("OP_MULTIPLY", offset);
        },
        Opcode.op_divide => {
            return simpleInstruction("OP_DIVIDE", offset);
        },
        Opcode.op_negate => {
            return simpleInstruction("OP_NEGATE", offset);
        },
        Opcode.op_nil => {
            return simpleInstruction("OP_NIL", offset);
        },
        Opcode.op_true => {
            return simpleInstruction("OP_TRUE", offset);
        },
        Opcode.op_false => {
            return simpleInstruction("OP_FALSE", offset);
        },
        Opcode.op_pop => {
            return simpleInstruction("OP_POP", offset);
        },
        Opcode.op_get_local => {
            return byteInstruction("OP_GET_LOCAL", chunk, offset);
        },
        Opcode.op_set_local => {
            return byteInstruction("OP_SET_LOCAL", chunk, offset);
        },
        Opcode.op_get_global => {
            return constantInstruction("OP_GET_GLOBAL", chunk, offset);
        },
        Opcode.op_define_global => {
            return constantInstruction("OP_DEFINE_GLOBAL", chunk, offset);
        },
        Opcode.op_set_global => {
            return constantInstruction("OP_SET_GLOBAL", chunk, offset);
        },
        Opcode.op_equal => {
            return simpleInstruction("OP_EQUAL", offset);
        },
        Opcode.op_greater => {
            return simpleInstruction("OP_GREATER", offset);
        },
        Opcode.op_less => {
            return simpleInstruction("OP_LESS", offset);
        },
        Opcode.op_not => {
            return simpleInstruction("OP_NOT", offset);
        },
        Opcode.op_print => {
            return simpleInstruction("OP_PRINT", offset);
        },
        Opcode.op_jump => {
            return jumpInstruction("OP_JUMP", 1, chunk, offset);
        },
        Opcode.op_jump_if_false => {
            return jumpInstruction("OP_JUMP_IF_FALSE", 1, chunk, offset);
        },
        Opcode.op_loop => {
            return jumpInstruction("OP_LOOP", -1, chunk, offset);
        },
    }
}

pub fn disassembleChunk(chunk: *Chunk, name: []const u8, writer: anytype) WriteError!void {
    _ = try writer.print("\n== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count) {
        offset = disassembleInstruction(chunk, offset);
    }
}
