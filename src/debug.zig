const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;
const Chunk = @import("chunk.zig");
const WriteError = std.os.WriteError;
const Value = @import("value.zig").Value;

pub fn printValue(value: Value) void {
    switch (value.type) {
        Value.Type.bool => std.debug.print("{}", .{Value.asBool(value)}),
        Value.Type.nil => std.debug.print("nil", .{}),
        Value.Type.number => std.debug.print("{d:.5}", .{Value.asNumber(value)}),
    }
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

pub fn disassembleInstruction(chunk: anytype, offset: usize) usize {
    if (offset > 9) {
        std.debug.print("{d}", .{offset});
    } else {
        std.debug.print("{d} ", .{offset});
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
    }
}

pub fn disassembleChunk(chunk: *Chunk, name: []const u8, writer: anytype) WriteError!void {
    _ = try writer.print("\n== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count) {
        offset = disassembleInstruction(chunk, offset);
    }
}
